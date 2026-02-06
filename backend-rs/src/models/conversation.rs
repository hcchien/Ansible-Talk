use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Conversation {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub conversation_type: ConversationType,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    pub created_by: Uuid,
    pub last_message_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "conversation_type", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ConversationType {
    Direct,
    Group,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Participant {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub role: ParticipantRole,
    pub joined_at: DateTime<Utc>,
    pub left_at: Option<DateTime<Utc>>,
    pub muted_until: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "participant_role", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ParticipantRole {
    Owner,
    Admin,
    Member,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationWithDetails {
    #[serde(flatten)]
    pub conversation: Conversation,
    pub participants: Vec<ParticipantWithUser>,
    pub unread_count: i64,
    pub last_message: Option<super::Message>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticipantWithUser {
    #[serde(flatten)]
    pub participant: Participant,
    pub user: Option<super::User>,
}
