use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub username: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub status: UserStatus,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "user_status", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum UserStatus {
    Online,
    Offline,
    Away,
}

impl Default for UserStatus {
    fn default() -> Self {
        Self::Offline
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: i32,
    pub token_hash: String,
    pub refresh_token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub last_used_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Otp {
    pub id: Uuid,
    pub target: String,
    #[serde(rename = "type")]
    pub otp_type: OtpType,
    pub code: String,
    pub expires_at: DateTime<Utc>,
    pub attempts: i32,
    pub verified: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "otp_type", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum OtpType {
    Phone,
    Email,
}
