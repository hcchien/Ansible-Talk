use redis::{aio::MultiplexedConnection, AsyncCommands, Client};
use std::time::Duration;

use crate::error::AppResult;

#[derive(Clone)]
pub struct RedisClient {
    client: Client,
    conn: MultiplexedConnection,
}

impl RedisClient {
    pub async fn new(url: &str) -> AppResult<Self> {
        let client = Client::open(url)?;
        let conn = client.get_multiplexed_async_connection().await?;
        Ok(Self { client, conn })
    }

    pub fn client(&self) -> &Client {
        &self.client
    }

    // Session management
    pub async fn set_session(
        &self,
        session_id: &str,
        user_id: &str,
        ttl: Duration,
    ) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let key = format!("session:{}", session_id);
        conn.set_ex(&key, user_id, ttl.as_secs()).await?;
        Ok(())
    }

    pub async fn get_session(&self, session_id: &str) -> AppResult<Option<String>> {
        let mut conn = self.conn.clone();
        let key = format!("session:{}", session_id);
        let value: Option<String> = conn.get(&key).await?;
        Ok(value)
    }

    pub async fn delete_session(&self, session_id: &str) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let key = format!("session:{}", session_id);
        conn.del(&key).await?;
        Ok(())
    }

    pub async fn delete_all_user_sessions(&self, user_id: &str) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let pattern = format!("session:{}:*", user_id);
        let keys: Vec<String> = conn.keys(&pattern).await?;
        if !keys.is_empty() {
            conn.del(keys).await?;
        }
        Ok(())
    }

    // OTP management
    pub async fn set_otp(&self, target: &str, code: &str, ttl: Duration) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let key = format!("otp:{}", target);
        conn.set_ex(&key, code, ttl.as_secs()).await?;
        Ok(())
    }

    pub async fn get_otp(&self, target: &str) -> AppResult<Option<String>> {
        let mut conn = self.conn.clone();
        let key = format!("otp:{}", target);
        let value: Option<String> = conn.get(&key).await?;
        Ok(value)
    }

    pub async fn delete_otp(&self, target: &str) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let key = format!("otp:{}", target);
        conn.del(&key).await?;
        Ok(())
    }

    // User presence
    pub async fn set_user_presence(
        &self,
        user_id: &str,
        status: &str,
        ttl: Duration,
    ) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let key = format!("presence:{}", user_id);
        conn.set_ex(&key, status, ttl.as_secs()).await?;
        Ok(())
    }

    pub async fn get_user_presence(&self, user_id: &str) -> AppResult<String> {
        let mut conn = self.conn.clone();
        let key = format!("presence:{}", user_id);
        let value: Option<String> = conn.get(&key).await?;
        Ok(value.unwrap_or_else(|| "offline".to_string()))
    }

    // Pub/Sub for messaging
    pub async fn publish_message(&self, user_id: &str, message: &str) -> AppResult<()> {
        let mut conn = self.conn.clone();
        let channel = format!("messages:{}", user_id);
        conn.publish(&channel, message).await?;
        Ok(())
    }

    pub async fn subscribe_messages(&self, user_id: &str) -> AppResult<redis::aio::PubSub> {
        let mut pubsub = self.client.get_async_pubsub().await?;
        let channel = format!("messages:{}", user_id);
        pubsub.subscribe(&channel).await?;
        Ok(pubsub)
    }
}
