use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use super::User;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Contact {
    pub id: Uuid,
    pub user_id: Uuid,
    pub contact_id: Uuid,
    pub nickname: Option<String>,
    pub is_blocked: bool,
    pub is_favorite: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContactWithUser {
    #[serde(flatten)]
    pub contact: Contact,
    pub user: Option<User>,
}
