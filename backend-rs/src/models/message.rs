use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    #[serde(rename = "type")]
    pub message_type: MessageType,
    pub content: Vec<u8>,
    pub sticker_id: Option<Uuid>,
    pub reply_to_id: Option<Uuid>,
    pub status: MessageStatus,
    pub edited_at: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "message_type", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum MessageType {
    Text,
    Image,
    Video,
    Audio,
    File,
    Sticker,
    System,
}

impl Default for MessageType {
    fn default() -> Self {
        Self::Text
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "message_status", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum MessageStatus {
    Sending,
    Sent,
    Delivered,
    Read,
    Failed,
}

impl Default for MessageStatus {
    fn default() -> Self {
        Self::Sent
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Receipt {
    pub id: Uuid,
    pub message_id: Uuid,
    pub user_id: Uuid,
    #[serde(rename = "type")]
    pub receipt_type: ReceiptType,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "receipt_type", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ReceiptType {
    Delivered,
    Read,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageWithSender {
    #[serde(flatten)]
    pub message: Message,
    pub sender: Option<super::User>,
}
