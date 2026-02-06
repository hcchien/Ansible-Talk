use axum::{
    extract::{Path, State},
    Extension, Json,
};
use serde::Serialize;
use uuid::Uuid;

use crate::{
    error::AppResult,
    services::{auth::Claims, messaging::MessagingService},
    AppState,
};

use super::super::middleware::get_user_id;

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn mark_delivered(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(message_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    messaging_service.mark_as_delivered(message_id, user_id).await?;

    Ok(Json(MessageResponse {
        message: "Marked as delivered".to_string(),
    }))
}

pub async fn mark_read(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(message_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    messaging_service.mark_as_read(message_id, user_id).await?;

    Ok(Json(MessageResponse {
        message: "Marked as read".to_string(),
    }))
}

pub async fn delete_message(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(message_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let messaging_service = MessagingService::new(state.db, state.redis);
    messaging_service.delete_message(message_id, user_id).await?;

    Ok(Json(MessageResponse {
        message: "Message deleted".to_string(),
    }))
}
