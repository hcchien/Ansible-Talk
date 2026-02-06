use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::{Deserialize, Serialize};

use crate::{
    error::AppResult,
    models::{KeyBundle, PreKeyBundle, RegisterKeysRequest, SignedPreKeyBundle},
    services::{auth::Claims, crypto::CryptoService},
    AppState,
};

use super::super::middleware::{get_device_id, get_user_id};

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn register_keys(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(mut req): Json<RegisterKeysRequest>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    // Use device_id from token if not provided
    if req.device_id == 0 {
        req.device_id = get_device_id(&claims)?;
    }

    let crypto_service = CryptoService::new(state.db);
    crypto_service.register_keys(user_id, req).await?;

    Ok(Json(MessageResponse {
        message: "Keys registered".to_string(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct KeyBundlePath {
    pub user_id: uuid::Uuid,
    pub device_id: i32,
}

pub async fn get_key_bundle(
    State(state): State<AppState>,
    Path(path): Path<KeyBundlePath>,
) -> AppResult<Json<KeyBundle>> {
    let crypto_service = CryptoService::new(state.db);
    let bundle = crypto_service
        .get_key_bundle(path.user_id, path.device_id)
        .await?;

    Ok(Json(bundle))
}

#[derive(Debug, Deserialize)]
pub struct PreKeyCountQuery {
    pub device_id: Option<i32>,
}

#[derive(Debug, Serialize)]
pub struct PreKeyCountResponse {
    pub count: i64,
}

pub async fn get_pre_key_count(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Query(query): Query<PreKeyCountQuery>,
) -> AppResult<Json<PreKeyCountResponse>> {
    let user_id = get_user_id(&claims)?;
    let device_id = query.device_id.unwrap_or_else(|| get_device_id(&claims).unwrap_or(1));

    let crypto_service = CryptoService::new(state.db);
    let count = crypto_service.get_pre_key_count(user_id, device_id).await?;

    Ok(Json(PreKeyCountResponse { count }))
}

#[derive(Debug, Deserialize)]
pub struct RefreshPreKeysRequest {
    pub device_id: i32,
    pub pre_keys: Vec<PreKeyBundle>,
}

pub async fn refresh_pre_keys(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<RefreshPreKeysRequest>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let crypto_service = CryptoService::new(state.db);
    crypto_service
        .refresh_pre_keys(user_id, req.device_id, req.pre_keys)
        .await?;

    Ok(Json(MessageResponse {
        message: "Pre-keys refreshed".to_string(),
    }))
}

pub async fn update_signed_pre_key(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<SignedPreKeyBundle>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;
    let device_id = get_device_id(&claims)?;

    let crypto_service = CryptoService::new(state.db);
    crypto_service
        .update_signed_pre_key(user_id, device_id, req)
        .await?;

    Ok(Json(MessageResponse {
        message: "Signed pre-key updated".to_string(),
    }))
}
