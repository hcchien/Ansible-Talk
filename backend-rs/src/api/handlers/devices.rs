use axum::{
    extract::{Path, State},
    Extension, Json,
};
use serde::Serialize;
use uuid::Uuid;

use crate::{
    error::AppResult,
    models::Device,
    services::auth::Claims,
    AppState,
};

use super::super::middleware::get_user_id;

pub async fn get_devices(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<Vec<Device>>> {
    let user_id = get_user_id(&claims)?;

    let devices: Vec<Device> = sqlx::query_as(
        r#"
        SELECT id, user_id, device_id, name, platform, push_token, last_active_at, created_at
        FROM devices WHERE user_id = $1
        ORDER BY last_active_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(devices))
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn remove_device(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(device_uuid): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    sqlx::query("DELETE FROM devices WHERE id = $1 AND user_id = $2")
        .bind(device_uuid)
        .bind(user_id)
        .execute(&state.db)
        .await?;

    Ok(Json(MessageResponse {
        message: "Device removed".to_string(),
    }))
}
