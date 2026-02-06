use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    models::{Contact, ContactWithUser, User},
};

pub struct ContactsService {
    db: PgPool,
}

impl ContactsService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Get all contacts for a user
    pub async fn get_contacts(
        &self,
        user_id: Uuid,
        include_blocked: bool,
    ) -> AppResult<Vec<ContactWithUser>> {
        let contacts: Vec<Contact> = if include_blocked {
            sqlx::query_as("SELECT * FROM contacts WHERE user_id = $1 ORDER BY created_at DESC")
                .bind(user_id)
                .fetch_all(&self.db)
                .await?
        } else {
            sqlx::query_as(
                "SELECT * FROM contacts WHERE user_id = $1 AND is_blocked = false ORDER BY created_at DESC",
            )
            .bind(user_id)
            .fetch_all(&self.db)
            .await?
        };

        let mut result = Vec::with_capacity(contacts.len());
        for contact in contacts {
            let user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
                .bind(contact.contact_id)
                .fetch_optional(&self.db)
                .await?;

            result.push(ContactWithUser { contact, user });
        }

        Ok(result)
    }

    /// Add a new contact
    pub async fn add_contact(
        &self,
        user_id: Uuid,
        contact_id: Uuid,
        nickname: Option<&str>,
    ) -> AppResult<ContactWithUser> {
        // Cannot add yourself
        if user_id == contact_id {
            return Err(AppError::CannotAddSelf);
        }

        // Check if contact user exists
        let contact_user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(contact_id)
            .fetch_optional(&self.db)
            .await?;

        if contact_user.is_none() {
            return Err(AppError::UserNotFound);
        }

        // Check if already exists
        let existing: Option<Contact> = sqlx::query_as(
            "SELECT * FROM contacts WHERE user_id = $1 AND contact_id = $2",
        )
        .bind(user_id)
        .bind(contact_id)
        .fetch_optional(&self.db)
        .await?;

        if existing.is_some() {
            return Err(AppError::ContactAlreadyExists);
        }

        // Create contact
        let contact: Contact = sqlx::query_as(
            r#"
            INSERT INTO contacts (id, user_id, contact_id, nickname, is_blocked, is_favorite)
            VALUES ($1, $2, $3, $4, false, false)
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(contact_id)
        .bind(nickname)
        .fetch_one(&self.db)
        .await?;

        Ok(ContactWithUser {
            contact,
            user: contact_user,
        })
    }

    /// Get a specific contact
    pub async fn get_contact(&self, user_id: Uuid, contact_id: Uuid) -> AppResult<ContactWithUser> {
        let contact: Option<Contact> = sqlx::query_as(
            "SELECT * FROM contacts WHERE user_id = $1 AND contact_id = $2",
        )
        .bind(user_id)
        .bind(contact_id)
        .fetch_optional(&self.db)
        .await?;

        let contact = contact.ok_or(AppError::ContactNotFound)?;

        let user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(contact.contact_id)
            .fetch_optional(&self.db)
            .await?;

        Ok(ContactWithUser { contact, user })
    }

    /// Update contact
    pub async fn update_contact(
        &self,
        user_id: Uuid,
        contact_id: Uuid,
        nickname: Option<&str>,
        is_favorite: Option<bool>,
    ) -> AppResult<ContactWithUser> {
        let contact: Option<Contact> = sqlx::query_as(
            r#"
            UPDATE contacts
            SET nickname = COALESCE($3, nickname),
                is_favorite = COALESCE($4, is_favorite),
                updated_at = NOW()
            WHERE user_id = $1 AND contact_id = $2
            RETURNING *
            "#,
        )
        .bind(user_id)
        .bind(contact_id)
        .bind(nickname)
        .bind(is_favorite)
        .fetch_optional(&self.db)
        .await?;

        let contact = contact.ok_or(AppError::ContactNotFound)?;

        let user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(contact.contact_id)
            .fetch_optional(&self.db)
            .await?;

        Ok(ContactWithUser { contact, user })
    }

    /// Delete contact
    pub async fn delete_contact(&self, user_id: Uuid, contact_id: Uuid) -> AppResult<()> {
        let result = sqlx::query("DELETE FROM contacts WHERE user_id = $1 AND contact_id = $2")
            .bind(user_id)
            .bind(contact_id)
            .execute(&self.db)
            .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::ContactNotFound);
        }

        Ok(())
    }

    /// Block a contact
    pub async fn block_contact(&self, user_id: Uuid, contact_id: Uuid) -> AppResult<()> {
        // First ensure contact exists or create it as blocked
        sqlx::query(
            r#"
            INSERT INTO contacts (id, user_id, contact_id, is_blocked, is_favorite)
            VALUES ($1, $2, $3, true, false)
            ON CONFLICT (user_id, contact_id)
            DO UPDATE SET is_blocked = true, updated_at = NOW()
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(contact_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Unblock a contact
    pub async fn unblock_contact(&self, user_id: Uuid, contact_id: Uuid) -> AppResult<()> {
        sqlx::query(
            "UPDATE contacts SET is_blocked = false, updated_at = NOW() WHERE user_id = $1 AND contact_id = $2",
        )
        .bind(user_id)
        .bind(contact_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Get blocked contacts
    pub async fn get_blocked_contacts(&self, user_id: Uuid) -> AppResult<Vec<ContactWithUser>> {
        let contacts: Vec<Contact> = sqlx::query_as(
            "SELECT * FROM contacts WHERE user_id = $1 AND is_blocked = true ORDER BY updated_at DESC",
        )
        .bind(user_id)
        .fetch_all(&self.db)
        .await?;

        let mut result = Vec::with_capacity(contacts.len());
        for contact in contacts {
            let user: Option<User> = sqlx::query_as("SELECT * FROM users WHERE id = $1")
                .bind(contact.contact_id)
                .fetch_optional(&self.db)
                .await?;

            result.push(ContactWithUser { contact, user });
        }

        Ok(result)
    }

    /// Search users by username or display name
    pub async fn search_users(&self, query: &str, limit: i32) -> AppResult<Vec<User>> {
        let search_pattern = format!("%{}%", query.to_lowercase());

        let users: Vec<User> = sqlx::query_as(
            r#"
            SELECT * FROM users
            WHERE LOWER(username) LIKE $1 OR LOWER(display_name) LIKE $1
            LIMIT $2
            "#,
        )
        .bind(&search_pattern)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;

        Ok(users)
    }

    /// Sync contacts from phone identifiers (phone numbers or emails)
    pub async fn sync_contacts(
        &self,
        _user_id: Uuid,
        identifiers: Vec<String>,
    ) -> AppResult<Vec<User>> {
        if identifiers.is_empty() {
            return Ok(vec![]);
        }

        let users: Vec<User> = sqlx::query_as(
            "SELECT * FROM users WHERE phone = ANY($1) OR email = ANY($1)",
        )
        .bind(&identifiers)
        .fetch_all(&self.db)
        .await?;

        Ok(users)
    }
}
