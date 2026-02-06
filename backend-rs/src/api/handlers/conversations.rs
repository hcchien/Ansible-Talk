use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::AppResult,
    models::{ConversationWithDetails, Message, MessageType},
    services::{auth::Claims, messaging::MessagingService},
    AppState,
};

use super::super::middleware::get_user_id;

#[derive(Debug, Deserialize)]
pub struct PaginationQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
}

fn default_limit() -> i32 {
    20
}

pub async fn get_conversations(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Query(query): Query<PaginationQuery>,
) -> AppResult<Json<Vec<ConversationWithDetails>>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    let conversations = messaging_service
        .get_user_conversations(user_id, query.limit, query.offset)
        .await?;

    Ok(Json(conversations))
}

#[derive(Debug, Deserialize)]
pub struct CreateDirectRequest {
    pub user_id: Uuid,
}

pub async fn create_direct_conversation(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<CreateDirectRequest>,
) -> AppResult<Json<ConversationWithDetails>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    let conversation = messaging_service
        .create_direct_conversation(user_id, req.user_id)
        .await?;

    Ok(Json(conversation))
}

#[derive(Debug, Deserialize)]
pub struct CreateGroupRequest {
    pub name: String,
    pub member_ids: Vec<Uuid>,
}

pub async fn create_group_conversation(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<CreateGroupRequest>,
) -> AppResult<Json<ConversationWithDetails>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    let conversation = messaging_service
        .create_group_conversation(user_id, &req.name, req.member_ids)
        .await?;

    Ok(Json(conversation))
}

pub async fn get_conversation(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(conversation_id): Path<Uuid>,
) -> AppResult<Json<ConversationWithDetails>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    let conversation = messaging_service
        .get_conversation(conversation_id, user_id)
        .await?;

    Ok(Json(conversation))
}

#[derive(Debug, Deserialize)]
pub struct MessagesQuery {
    #[serde(default = "default_message_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
    pub before: Option<Uuid>,
}

fn default_message_limit() -> i32 {
    50
}

pub async fn get_messages(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(conversation_id): Path<Uuid>,
    Query(query): Query<MessagesQuery>,
) -> AppResult<Json<Vec<Message>>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    let messages = messaging_service
        .get_messages(conversation_id, user_id, query.limit, query.offset, query.before)
        .await?;

    Ok(Json(messages))
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    #[serde(rename = "type")]
    pub message_type: String,
    pub content: Vec<u8>,
    pub sticker_id: Option<Uuid>,
    pub reply_to_id: Option<Uuid>,
}

pub async fn send_message(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(conversation_id): Path<Uuid>,
    Json(req): Json<SendMessageRequest>,
) -> AppResult<Json<Message>> {
    let user_id = get_user_id(&claims)?;

    let message_type = match req.message_type.as_str() {
        "text" => MessageType::Text,
        "image" => MessageType::Image,
        "video" => MessageType::Video,
        "audio" => MessageType::Audio,
        "file" => MessageType::File,
        "sticker" => MessageType::Sticker,
        "system" => MessageType::System,
        _ => MessageType::Text,
    };

    let messaging_service = MessagingService::new(state.db, state.redis);
    let message = messaging_service
        .send_message(
            conversation_id,
            user_id,
            message_type,
            req.content,
            req.sticker_id,
            req.reply_to_id,
        )
        .await?;

    Ok(Json(message))
}

#[derive(Debug, Deserialize)]
pub struct TypingRequest {
    pub is_typing: bool,
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn send_typing(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(conversation_id): Path<Uuid>,
    Json(req): Json<TypingRequest>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    messaging_service
        .broadcast_typing(conversation_id, user_id, req.is_typing)
        .await?;

    Ok(Json(MessageResponse {
        message: "ok".to_string(),
    }))
}
