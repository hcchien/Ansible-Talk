use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Device {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: i32,
    pub name: String,
    pub platform: String,
    pub push_token: Option<String>,
    pub last_active_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}
