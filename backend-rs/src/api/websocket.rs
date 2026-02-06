use std::{
    collections::HashMap,
    sync::Arc,
    time::Duration,
};

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::Response,
    Extension,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, RwLock};

use crate::{
    services::auth::Claims,
    storage::redis::RedisClient,
    AppState,
};

use super::middleware::{get_device_id, get_user_id};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsIncomingMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsOutgoingMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub payload: serde_json::Value,
}

pub struct WsHub {
    clients: RwLock<HashMap<String, mpsc::Sender<WsOutgoingMessage>>>,
    redis: RedisClient,
}

impl WsHub {
    pub fn new(redis: RedisClient) -> Self {
        Self {
            clients: RwLock::new(HashMap::new()),
            redis,
        }
    }

    pub async fn run(&self) {
        // This is a placeholder for any hub-level background tasks
        // In production, you might want to implement heartbeat checking here
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await;
        }
    }

    pub async fn register(&self, client_id: &str, sender: mpsc::Sender<WsOutgoingMessage>) {
        let mut clients = self.clients.write().await;
        clients.insert(client_id.to_string(), sender);
        tracing::info!("Client registered: {}", client_id);
    }

    pub async fn unregister(&self, client_id: &str) {
        let mut clients = self.clients.write().await;
        clients.remove(client_id);
        tracing::info!("Client unregistered: {}", client_id);
    }

    pub async fn send_to_user(&self, user_id: &str, message: WsOutgoingMessage) {
        let clients = self.clients.read().await;

        // Find all clients for this user (could be multiple devices)
        for (client_id, sender) in clients.iter() {
            if client_id.starts_with(&format!("{}:", user_id)) {
                let _ = sender.send(message.clone()).await;
            }
        }

        // Also publish to Redis for other server instances
        if let Ok(msg_str) = serde_json::to_string(&message) {
            let _ = self.redis.publish_message(user_id, &msg_str).await;
        }
    }

    pub async fn send_to_device(&self, user_id: &str, device_id: &str, message: WsOutgoingMessage) {
        let clients = self.clients.read().await;
        let client_id = format!("{}:{}", user_id, device_id);

        if let Some(sender) = clients.get(&client_id) {
            let _ = sender.send(message).await;
        }
    }
}

pub async fn handle_websocket(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> Response {
    let user_id = get_user_id(&claims).unwrap_or_default();
    let device_id = get_device_id(&claims).unwrap_or(1);

    ws.on_upgrade(move |socket| handle_socket(socket, state, user_id.to_string(), device_id))
}

async fn handle_socket(socket: WebSocket, state: AppState, user_id: String, device_id: i32) {
    let client_id = format!("{}:{}", user_id, device_id);
    let (mut ws_sender, mut ws_receiver) = socket.split();

    // Create channel for sending messages to this client
    let (tx, mut rx) = mpsc::channel::<WsOutgoingMessage>(256);

    // Register client
    state.ws_hub.register(&client_id, tx.clone()).await;

    // Set user presence to online
    let _ = state
        .redis
        .set_user_presence(&user_id, "online", Duration::from_secs(300))
        .await;

    // Subscribe to Redis for this user
    let redis_client = state.redis.clone();
    let user_id_clone = user_id.clone();
    let tx_clone = tx.clone();

    let redis_task = tokio::spawn(async move {
        if let Ok(mut pubsub) = redis_client.subscribe_messages(&user_id_clone).await {
            while let Some(msg) = pubsub.on_message().next().await {
                if let Ok(payload) = msg.get_payload::<String>() {
                    if let Ok(ws_msg) = serde_json::from_str::<WsOutgoingMessage>(&payload) {
                        let _ = tx_clone.send(ws_msg).await;
                    }
                }
            }
        }
    });

    // Task to send messages to WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if let Ok(json) = serde_json::to_string(&msg) {
                if ws_sender.send(Message::Text(json)).await.is_err() {
                    break;
                }
            }
        }
    });

    // Task to receive messages from WebSocket
    let hub = state.ws_hub.clone();
    let redis = state.redis.clone();
    let user_id_for_recv = user_id.clone();

    let recv_task = tokio::spawn(async move {
        while let Some(result) = ws_receiver.next().await {
            match result {
                Ok(Message::Text(text)) => {
                    if let Ok(msg) = serde_json::from_str::<WsIncomingMessage>(&text) {
                        handle_incoming_message(&hub, &redis, &user_id_for_recv, device_id, msg)
                            .await;
                    }
                }
                Ok(Message::Ping(data)) => {
                    // Pong is handled automatically by axum
                    let _ = data;
                }
                Ok(Message::Close(_)) => break,
                Err(_) => break,
                _ => {}
            }
        }
    });

    // Wait for any task to complete
    tokio::select! {
        _ = send_task => {},
        _ = recv_task => {},
        _ = redis_task => {},
    }

    // Cleanup
    state.ws_hub.unregister(&client_id).await;

    // Set user presence to offline
    let _ = state
        .redis
        .set_user_presence(&user_id, "offline", Duration::from_secs(1))
        .await;
}

async fn handle_incoming_message(
    hub: &Arc<WsHub>,
    redis: &RedisClient,
    user_id: &str,
    _device_id: i32,
    msg: WsIncomingMessage,
) {
    match msg.msg_type.as_str() {
        "ping" => {
            // Respond with pong
            let pong = WsOutgoingMessage {
                msg_type: "pong".to_string(),
                payload: serde_json::json!({}),
            };
            hub.send_to_user(user_id, pong).await;
        }
        "typing" => {
            // Forward typing indicator to conversation participants
            // This would need conversation_id from payload
            if let Some(conversation_id) = msg.payload.get("conversation_id") {
                tracing::debug!(
                    "User {} typing in conversation {}",
                    user_id,
                    conversation_id
                );
            }
        }
        "presence" => {
            // Update user presence
            if let Some(status) = msg.payload.get("status").and_then(|s| s.as_str()) {
                let _ = redis
                    .set_user_presence(user_id, status, Duration::from_secs(300))
                    .await;
            }
        }
        "ack" => {
            // Handle message acknowledgment
            tracing::debug!("User {} ack: {:?}", user_id, msg.payload);
        }
        _ => {
            tracing::warn!("Unknown message type: {}", msg.msg_type);
        }
    }
}
