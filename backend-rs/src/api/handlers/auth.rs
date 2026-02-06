use axum::{extract::State, Extension, Json};
use serde::{Deserialize, Serialize};

use crate::{
    error::{AppError, AppResult},
    models::{OtpType, TokenPair, User},
    services::auth::{AuthService, Claims},
    AppState,
};

use super::super::middleware::{get_device_id, get_user_id};

#[derive(Debug, Deserialize)]
pub struct SendOtpRequest {
    pub target: String,
    #[serde(rename = "type")]
    pub otp_type: String,
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn send_otp(
    State(state): State<AppState>,
    Json(req): Json<SendOtpRequest>,
) -> AppResult<Json<MessageResponse>> {
    let otp_type = match req.otp_type.as_str() {
        "phone" => OtpType::Phone,
        "email" => OtpType::Email,
        _ => return Err(AppError::BadRequest("Invalid OTP type".to_string())),
    };

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    auth_service.send_otp(&req.target, otp_type).await?;

    Ok(Json(MessageResponse {
        message: "OTP sent successfully".to_string(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct VerifyOtpRequest {
    pub target: String,
    #[serde(rename = "type")]
    pub otp_type: String,
    pub code: String,
}

#[derive(Debug, Serialize)]
pub struct VerifyResponse {
    pub verified: bool,
}

pub async fn verify_otp(
    State(state): State<AppState>,
    Json(req): Json<VerifyOtpRequest>,
) -> AppResult<Json<VerifyResponse>> {
    let otp_type = match req.otp_type.as_str() {
        "phone" => OtpType::Phone,
        "email" => OtpType::Email,
        _ => return Err(AppError::BadRequest("Invalid OTP type".to_string())),
    };

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    auth_service.verify_otp(&req.target, otp_type, &req.code).await?;

    Ok(Json(VerifyResponse { verified: true }))
}

#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub phone: Option<String>,
    pub email: Option<String>,
    pub username: String,
    pub display_name: String,
    pub device_name: String,
    pub platform: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub user: User,
    pub tokens: TokenPair,
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> AppResult<Json<AuthResponse>> {
    if req.phone.is_none() && req.email.is_none() {
        return Err(AppError::BadRequest("Phone or email is required".to_string()));
    }

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    let (user, tokens) = auth_service
        .register(
            req.phone.as_deref(),
            req.email.as_deref(),
            &req.username,
            &req.display_name,
            &req.device_name,
            &req.platform,
        )
        .await?;

    Ok(Json(AuthResponse { user, tokens }))
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub target: String,
    #[serde(rename = "type")]
    pub otp_type: String,
    pub device_name: String,
    pub platform: String,
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
    let otp_type = match req.otp_type.as_str() {
        "phone" => OtpType::Phone,
        "email" => OtpType::Email,
        _ => return Err(AppError::BadRequest("Invalid OTP type".to_string())),
    };

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    let (user, tokens) = auth_service
        .login(&req.target, otp_type, &req.device_name, &req.platform)
        .await?;

    Ok(Json(AuthResponse { user, tokens }))
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize)]
pub struct TokenResponse {
    pub tokens: TokenPair,
}

pub async fn refresh_token(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> AppResult<Json<TokenResponse>> {
    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    let tokens = auth_service.refresh_token(&req.refresh_token).await?;

    Ok(Json(TokenResponse { tokens }))
}

pub async fn logout(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;
    let device_id = get_device_id(&claims)?;

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    auth_service.logout(user_id, device_id).await?;

    Ok(Json(MessageResponse {
        message: "Logged out successfully".to_string(),
    }))
}

pub async fn logout_all(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let auth_service = AuthService::new(state.db, state.redis, (*state.config).clone());
    auth_service.logout_all(user_id).await?;

    Ok(Json(MessageResponse {
        message: "Logged out from all devices".to_string(),
    }))
}
