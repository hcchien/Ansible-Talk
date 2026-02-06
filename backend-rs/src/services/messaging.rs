use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    models::{
        Conversation, ConversationType, ConversationWithDetails, Message, MessageStatus,
        MessageType, Participant, ParticipantRole, ParticipantWithUser, ReceiptType, User,
    },
    storage::redis::RedisClient,
};

#[derive(Debug, Serialize, Deserialize)]
pub struct WsMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub payload: serde_json::Value,
}

pub struct MessagingService {
    db: PgPool,
    redis: RedisClient,
}

impl MessagingService {
    pub fn new(db: PgPool, redis: RedisClient) -> Self {
        Self { db, redis }
    }

    /// Create or get existing direct conversation
    pub async fn create_direct_conversation(
        &self,
        user_id: Uuid,
        other_user_id: Uuid,
    ) -> AppResult<ConversationWithDetails> {
        // Check if conversation already exists
        let existing: Option<Conversation> = sqlx::query_as(
            r#"
            SELECT c.* FROM conversations c
            JOIN participants p1 ON c.id = p1.conversation_id
            JOIN participants p2 ON c.id = p2.conversation_id
            WHERE c.type = 'direct'
            AND p1.user_id = $1 AND p2.user_id = $2
            AND p1.left_at IS NULL AND p2.left_at IS NULL
            "#,
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_optional(&self.db)
        .await?;

        if let Some(conv) = existing {
            return self.get_conversation(conv.id, user_id).await;
        }

        // Create new conversation
        let mut tx = self.db.begin().await?;

        let conv_id = Uuid::new_v4();
        let conversation: Conversation = sqlx::query_as(
            r#"
            INSERT INTO conversations (id, type, created_by)
            VALUES ($1, $2, $3)
            RETURNING *
            "#,
        )
        .bind(conv_id)
        .bind(ConversationType::Direct)
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await?;

        // Add both participants
        for uid in [user_id, other_user_id] {
            sqlx::query(
                r#"
                INSERT INTO participants (id, conversation_id, user_id, role, joined_at)
                VALUES ($1, $2, $3, $4, NOW())
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(conv_id)
            .bind(uid)
            .bind(ParticipantRole::Member)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        self.get_conversation(conversation.id, user_id).await
    }

    /// Create a group conversation
    pub async fn create_group_conversation(
        &self,
        user_id: Uuid,
        name: &str,
        member_ids: Vec<Uuid>,
    ) -> AppResult<ConversationWithDetails> {
        let mut tx = self.db.begin().await?;

        let conv_id = Uuid::new_v4();
        let conversation: Conversation = sqlx::query_as(
            r#"
            INSERT INTO conversations (id, type, name, created_by)
            VALUES ($1, $2, $3, $4)
            RETURNING *
            "#,
        )
        .bind(conv_id)
        .bind(ConversationType::Group)
        .bind(name)
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await?;

        // Add creator as owner
        sqlx::query(
            r#"
            INSERT INTO participants (id, conversation_id, user_id, role, joined_at)
            VALUES ($1, $2, $3, $4, NOW())
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(conv_id)
        .bind(user_id)
        .bind(ParticipantRole::Owner)
        .execute(&mut *tx)
        .await?;

        // Add members
        for member_id in member_ids {
            if member_id != user_id {
                sqlx::query(
                    r#"
                    INSERT INTO participants (id, conversation_id, user_id, role, joined_at)
                    VALUES ($1, $2, $3, $4, NOW())
                    "#,
                )
                .bind(Uuid::new_v4())
                .bind(conv_id)
                .bind(member_id)
                .bind(ParticipantRole::Member)
                .execute(&mut *tx)
                .await?;
            }
        }

        tx.commit().await?;

        self.get_conversation(conversation.id, user_id).await
    }

    /// Get conversation with details
    pub async fn get_conversation(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> AppResult<ConversationWithDetails> {
        // Check if user is participant
        let is_participant: Option<(i64,)> = sqlx::query_as(
            "SELECT 1 FROM participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_optional(&self.db)
        .await?;

        if is_participant.is_none() {
            return Err(AppError::NotParticipant);
        }

        let conversation: Option<Conversation> =
            sqlx::query_as("SELECT * FROM conversations WHERE id = $1")
                .bind(conversation_id)
                .fetch_optional(&self.db)
                .await?;

        let conversation = conversation.ok_or(AppError::ConversationNotFound)?;

        // Get participants
        let participants: Vec<Participant> = sqlx::query_as(
            "SELECT * FROM participants WHERE conversation_id = $1 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .fetch_all(&self.db)
        .await?;

        let mut participants_with_users = Vec::with_capacity(participants.len());
        for participant in participants {
            let user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
                .bind(participant.user_id)
                .fetch_optional(&self.db)
                .await?;
            participants_with_users.push(ParticipantWithUser { participant, user });
        }

        // Get unread count
        let unread_count: (i64,) = sqlx::query_as(
            r#"
            SELECT COUNT(*) FROM messages m
            LEFT JOIN receipts r ON m.id = r.message_id AND r.user_id = $2 AND r.type = 'read'
            WHERE m.conversation_id = $1 AND m.sender_id != $2 AND r.id IS NULL AND m.deleted_at IS NULL
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_one(&self.db)
        .await?;

        // Get last message
        let last_message: Option<Message> = sqlx::query_as(
            "SELECT * FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1",
        )
        .bind(conversation_id)
        .fetch_optional(&self.db)
        .await?;

        Ok(ConversationWithDetails {
            conversation,
            participants: participants_with_users,
            unread_count: unread_count.0,
            last_message,
        })
    }

    /// Get user's conversations
    pub async fn get_user_conversations(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> AppResult<Vec<ConversationWithDetails>> {
        let conversations: Vec<Conversation> = sqlx::query_as(
            r#"
            SELECT c.* FROM conversations c
            JOIN participants p ON c.id = p.conversation_id
            WHERE p.user_id = $1 AND p.left_at IS NULL
            ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        let mut result = Vec::with_capacity(conversations.len());
        for conv in conversations {
            let details = self.get_conversation(conv.id, user_id).await?;
            result.push(details);
        }

        Ok(result)
    }

    /// Send a message
    pub async fn send_message(
        &self,
        conversation_id: Uuid,
        sender_id: Uuid,
        message_type: MessageType,
        content: Vec<u8>,
        sticker_id: Option<Uuid>,
        reply_to_id: Option<Uuid>,
    ) -> AppResult<Message> {
        // Check if sender is participant
        let is_participant: Option<(i64,)> = sqlx::query_as(
            "SELECT 1 FROM participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .bind(sender_id)
        .fetch_optional(&self.db)
        .await?;

        if is_participant.is_none() {
            return Err(AppError::NotParticipant);
        }

        // Create message
        let message: Message = sqlx::query_as(
            r#"
            INSERT INTO messages (id, conversation_id, sender_id, type, content, sticker_id, reply_to_id, status)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(conversation_id)
        .bind(sender_id)
        .bind(message_type)
        .bind(&content)
        .bind(sticker_id)
        .bind(reply_to_id)
        .bind(MessageStatus::Sent)
        .fetch_one(&self.db)
        .await?;

        // Update conversation last_message_at
        sqlx::query("UPDATE conversations SET last_message_at = NOW(), updated_at = NOW() WHERE id = $1")
            .bind(conversation_id)
            .execute(&self.db)
            .await?;

        // Notify participants
        self.notify_participants(conversation_id, sender_id, &message)
            .await?;

        Ok(message)
    }

    /// Get messages for a conversation
    pub async fn get_messages(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        limit: i32,
        offset: i32,
        before: Option<Uuid>,
    ) -> AppResult<Vec<Message>> {
        // Check if user is participant
        let is_participant: Option<(i64,)> = sqlx::query_as(
            "SELECT 1 FROM participants WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_optional(&self.db)
        .await?;

        if is_participant.is_none() {
            return Err(AppError::NotParticipant);
        }

        let messages: Vec<Message> = if let Some(before_id) = before {
            sqlx::query_as(
                r#"
                SELECT * FROM messages
                WHERE conversation_id = $1 AND deleted_at IS NULL
                AND created_at < (SELECT created_at FROM messages WHERE id = $4)
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(conversation_id)
            .bind(limit)
            .bind(offset)
            .bind(before_id)
            .fetch_all(&self.db)
            .await?
        } else {
            sqlx::query_as(
                r#"
                SELECT * FROM messages
                WHERE conversation_id = $1 AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(conversation_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db)
            .await?
        };

        Ok(messages)
    }

    /// Mark message as delivered
    pub async fn mark_as_delivered(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        sqlx::query(
            r#"
            INSERT INTO receipts (id, message_id, user_id, type)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (message_id, user_id, type) DO NOTHING
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(message_id)
        .bind(user_id)
        .bind(ReceiptType::Delivered)
        .execute(&self.db)
        .await?;

        // Update message status if this was the last recipient
        sqlx::query(
            "UPDATE messages SET status = 'delivered' WHERE id = $1 AND status = 'sent'",
        )
        .bind(message_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Mark message as read
    pub async fn mark_as_read(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        // Also mark as delivered if not already
        sqlx::query(
            r#"
            INSERT INTO receipts (id, message_id, user_id, type)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (message_id, user_id, type) DO NOTHING
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(message_id)
        .bind(user_id)
        .bind(ReceiptType::Delivered)
        .execute(&self.db)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO receipts (id, message_id, user_id, type)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (message_id, user_id, type) DO NOTHING
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(message_id)
        .bind(user_id)
        .bind(ReceiptType::Read)
        .execute(&self.db)
        .await?;

        // Update message status
        sqlx::query(
            "UPDATE messages SET status = 'read' WHERE id = $1 AND status IN ('sent', 'delivered')",
        )
        .bind(message_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Delete a message (soft delete)
    pub async fn delete_message(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            "UPDATE messages SET deleted_at = NOW() WHERE id = $1 AND sender_id = $2 AND deleted_at IS NULL",
        )
        .bind(message_id)
        .bind(user_id)
        .execute(&self.db)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::MessageNotFound);
        }

        Ok(())
    }

    /// Broadcast typing indicator
    pub async fn broadcast_typing(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        is_typing: bool,
    ) -> AppResult<()> {
        let participants: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT user_id FROM participants WHERE conversation_id = $1 AND user_id != $2 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_all(&self.db)
        .await?;

        let message = WsMessage {
            msg_type: "typing".to_string(),
            payload: serde_json::json!({
                "conversation_id": conversation_id,
                "user_id": user_id,
                "is_typing": is_typing,
                "timestamp": Utc::now().to_rfc3339()
            }),
        };

        let msg_str = serde_json::to_string(&message)?;

        for (participant_id,) in participants {
            self.redis
                .publish_message(&participant_id.to_string(), &msg_str)
                .await?;
        }

        Ok(())
    }

    /// Update user presence
    pub async fn update_presence(&self, user_id: Uuid, status: &str) -> AppResult<()> {
        use std::time::Duration;

        self.redis
            .set_user_presence(&user_id.to_string(), status, Duration::from_secs(300))
            .await?;

        sqlx::query("UPDATE users SET status = $1, last_seen_at = NOW() WHERE id = $2")
            .bind(status)
            .bind(user_id)
            .execute(&self.db)
            .await?;

        Ok(())
    }

    /// Notify participants of new message
    async fn notify_participants(
        &self,
        conversation_id: Uuid,
        sender_id: Uuid,
        message: &Message,
    ) -> AppResult<()> {
        let participants: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT user_id FROM participants WHERE conversation_id = $1 AND user_id != $2 AND left_at IS NULL",
        )
        .bind(conversation_id)
        .bind(sender_id)
        .fetch_all(&self.db)
        .await?;

        let ws_message = WsMessage {
            msg_type: "new_message".to_string(),
            payload: serde_json::to_value(message)?,
        };

        let msg_str = serde_json::to_string(&ws_message)?;

        for (participant_id,) in participants {
            self.redis
                .publish_message(&participant_id.to_string(), &msg_str)
                .await?;
        }

        Ok(())
    }
}
