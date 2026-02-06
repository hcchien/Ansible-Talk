use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    // Auth errors
    #[error("Invalid credentials")]
    InvalidCredentials,
    #[error("Invalid token")]
    InvalidToken,
    #[error("Token expired")]
    TokenExpired,
    #[error("Unauthorized")]
    Unauthorized,

    // User errors
    #[error("User not found")]
    UserNotFound,
    #[error("User already exists")]
    UserAlreadyExists,

    // OTP errors
    #[error("Invalid OTP")]
    InvalidOtp,
    #[error("OTP expired")]
    OtpExpired,
    #[error("Too many attempts")]
    TooManyAttempts,
    #[error("OTP not verified")]
    OtpNotVerified,

    // Contact errors
    #[error("Contact not found")]
    ContactNotFound,
    #[error("Contact already exists")]
    ContactAlreadyExists,
    #[error("Cannot add yourself as contact")]
    CannotAddSelf,

    // Conversation errors
    #[error("Conversation not found")]
    ConversationNotFound,
    #[error("Not a participant")]
    NotParticipant,

    // Message errors
    #[error("Message not found")]
    MessageNotFound,

    // Signal key errors
    #[error("Identity key not found")]
    IdentityKeyNotFound,
    #[error("Pre-key not found")]
    PreKeyNotFound,

    // Sticker errors
    #[error("Sticker pack not found")]
    StickerPackNotFound,
    #[error("Sticker pack already owned")]
    StickerPackAlreadyOwned,
    #[error("Sticker pack not owned")]
    StickerPackNotOwned,

    // Validation errors
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("Bad request: {0}")]
    BadRequest(String),

    // Database errors
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    // Redis errors
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    // JWT errors
    #[error("JWT error: {0}")]
    Jwt(#[from] jsonwebtoken::errors::Error),

    // Internal errors
    #[error("Internal server error")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            // 400 Bad Request
            AppError::Validation(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::InvalidOtp => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::OtpExpired => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::CannotAddSelf => (StatusCode::BAD_REQUEST, self.to_string()),

            // 401 Unauthorized
            AppError::InvalidCredentials => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::InvalidToken => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::TokenExpired => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::Jwt(_) => (StatusCode::UNAUTHORIZED, "Invalid token".to_string()),

            // 403 Forbidden
            AppError::NotParticipant => (StatusCode::FORBIDDEN, self.to_string()),
            AppError::OtpNotVerified => (StatusCode::FORBIDDEN, self.to_string()),

            // 404 Not Found
            AppError::UserNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::ContactNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::ConversationNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::MessageNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::IdentityKeyNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::PreKeyNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::StickerPackNotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::StickerPackNotOwned => (StatusCode::NOT_FOUND, self.to_string()),

            // 409 Conflict
            AppError::UserAlreadyExists => (StatusCode::CONFLICT, self.to_string()),
            AppError::ContactAlreadyExists => (StatusCode::CONFLICT, self.to_string()),
            AppError::StickerPackAlreadyOwned => (StatusCode::CONFLICT, self.to_string()),

            // 429 Too Many Requests
            AppError::TooManyAttempts => (StatusCode::TOO_MANY_REQUESTS, self.to_string()),

            // 500 Internal Server Error
            AppError::Database(e) => {
                tracing::error!("Database error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Database error".to_string(),
                )
            }
            AppError::Redis(e) => {
                tracing::error!("Redis error: {}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "Cache error".to_string())
            }
            AppError::Internal(e) => {
                tracing::error!("Internal error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal server error".to_string(),
                )
            }
        };

        let body = Json(json!({
            "error": message
        }));

        (status, body).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;
