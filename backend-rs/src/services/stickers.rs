use bytes::Bytes;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    models::{Sticker, StickerPack, StickerPackWithStickers, UserStickerPack},
    storage::minio::MinioClient,
};

pub struct StickersService {
    db: PgPool,
    minio: MinioClient,
}

impl StickersService {
    pub fn new(db: PgPool, minio: MinioClient) -> Self {
        Self { db, minio }
    }

    /// Get sticker pack catalog
    pub async fn get_catalog(
        &self,
        limit: i32,
        offset: i32,
        official: Option<bool>,
    ) -> AppResult<Vec<StickerPack>> {
        let packs: Vec<StickerPack> = if let Some(is_official) = official {
            sqlx::query_as(
                r#"
                SELECT * FROM sticker_packs
                WHERE is_official = $1
                ORDER BY downloads DESC, created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(is_official)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db)
            .await?
        } else {
            sqlx::query_as(
                r#"
                SELECT * FROM sticker_packs
                ORDER BY downloads DESC, created_at DESC
                LIMIT $1 OFFSET $2
                "#,
            )
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db)
            .await?
        };

        Ok(packs)
    }

    /// Search sticker packs
    pub async fn search_packs(&self, query: &str, limit: i32) -> AppResult<Vec<StickerPack>> {
        let search_pattern = format!("%{}%", query.to_lowercase());

        let packs: Vec<StickerPack> = sqlx::query_as(
            r#"
            SELECT * FROM sticker_packs
            WHERE LOWER(name) LIKE $1 OR LOWER(description) LIKE $1 OR LOWER(author) LIKE $1
            ORDER BY downloads DESC
            LIMIT $2
            "#,
        )
        .bind(&search_pattern)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;

        Ok(packs)
    }

    /// Get a sticker pack with its stickers
    pub async fn get_pack(&self, pack_id: Uuid) -> AppResult<StickerPackWithStickers> {
        let pack: Option<StickerPack> =
            sqlx::query_as("SELECT * FROM sticker_packs WHERE id = $1")
                .bind(pack_id)
                .fetch_optional(&self.db)
                .await?;

        let pack = pack.ok_or(AppError::StickerPackNotFound)?;

        let stickers: Vec<Sticker> = sqlx::query_as(
            "SELECT * FROM stickers WHERE pack_id = $1 ORDER BY position ASC",
        )
        .bind(pack_id)
        .fetch_all(&self.db)
        .await?;

        Ok(StickerPackWithStickers { pack, stickers })
    }

    /// Download (add) a sticker pack to user's collection
    pub async fn download_pack(&self, user_id: Uuid, pack_id: Uuid) -> AppResult<()> {
        // Check if pack exists
        let pack_exists: Option<(i64,)> =
            sqlx::query_as("SELECT 1 FROM sticker_packs WHERE id = $1")
                .bind(pack_id)
                .fetch_optional(&self.db)
                .await?;

        if pack_exists.is_none() {
            return Err(AppError::StickerPackNotFound);
        }

        // Check if already owned
        let already_owned: Option<(i64,)> = sqlx::query_as(
            "SELECT 1 FROM user_sticker_packs WHERE user_id = $1 AND pack_id = $2",
        )
        .bind(user_id)
        .bind(pack_id)
        .fetch_optional(&self.db)
        .await?;

        if already_owned.is_some() {
            return Err(AppError::StickerPackAlreadyOwned);
        }

        // Get next position
        let max_pos: Option<i32> = sqlx::query_scalar(
            "SELECT MAX(position) FROM user_sticker_packs WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_one(&self.db)
        .await?;

        let position = max_pos.unwrap_or(-1) + 1;

        // Add to user's collection
        sqlx::query(
            r#"
            INSERT INTO user_sticker_packs (id, user_id, pack_id, position)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(pack_id)
        .bind(position)
        .execute(&self.db)
        .await?;

        // Increment download count
        sqlx::query("UPDATE sticker_packs SET downloads = downloads + 1 WHERE id = $1")
            .bind(pack_id)
            .execute(&self.db)
            .await?;

        Ok(())
    }

    /// Remove a sticker pack from user's collection
    pub async fn remove_pack(&self, user_id: Uuid, pack_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            "DELETE FROM user_sticker_packs WHERE user_id = $1 AND pack_id = $2",
        )
        .bind(user_id)
        .bind(pack_id)
        .execute(&self.db)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::StickerPackNotOwned);
        }

        Ok(())
    }

    /// Get user's sticker packs
    pub async fn get_user_packs(&self, user_id: Uuid) -> AppResult<Vec<StickerPackWithStickers>> {
        let user_packs: Vec<UserStickerPack> = sqlx::query_as(
            "SELECT * FROM user_sticker_packs WHERE user_id = $1 ORDER BY position ASC",
        )
        .bind(user_id)
        .fetch_all(&self.db)
        .await?;

        let mut result = Vec::with_capacity(user_packs.len());
        for user_pack in user_packs {
            let pack = self.get_pack(user_pack.pack_id).await?;
            result.push(pack);
        }

        Ok(result)
    }

    /// Reorder user's sticker packs
    pub async fn reorder_packs(&self, user_id: Uuid, pack_ids: Vec<Uuid>) -> AppResult<()> {
        let mut tx = self.db.begin().await?;

        for (position, pack_id) in pack_ids.iter().enumerate() {
            sqlx::query(
                "UPDATE user_sticker_packs SET position = $1 WHERE user_id = $2 AND pack_id = $3",
            )
            .bind(position as i32)
            .bind(user_id)
            .bind(pack_id)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    /// Create a new sticker pack (admin)
    pub async fn create_pack(
        &self,
        name: &str,
        author: &str,
        description: Option<&str>,
        is_official: bool,
        is_animated: bool,
    ) -> AppResult<StickerPack> {
        let pack: StickerPack = sqlx::query_as(
            r#"
            INSERT INTO sticker_packs (id, name, author, description, is_official, is_animated, price, downloads)
            VALUES ($1, $2, $3, $4, $5, $6, 0, 0)
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(name)
        .bind(author)
        .bind(description)
        .bind(is_official)
        .bind(is_animated)
        .fetch_one(&self.db)
        .await?;

        Ok(pack)
    }

    /// Upload pack cover image (admin)
    pub async fn upload_pack_cover(
        &self,
        pack_id: Uuid,
        data: Bytes,
        content_type: &str,
    ) -> AppResult<String> {
        let extension = get_extension_from_content_type(content_type);
        let key = format!("packs/{}/cover.{}", pack_id, extension);

        let url = self
            .minio
            .upload_file(self.minio.stickers_bucket(), &key, data, content_type)
            .await?;

        // Update pack
        sqlx::query("UPDATE sticker_packs SET cover_url = $1, updated_at = NOW() WHERE id = $2")
            .bind(&url)
            .bind(pack_id)
            .execute(&self.db)
            .await?;

        Ok(url)
    }

    /// Add a sticker to a pack (admin)
    pub async fn add_sticker(
        &self,
        pack_id: Uuid,
        emoji: &str,
        position: i32,
        data: Bytes,
        content_type: &str,
    ) -> AppResult<Sticker> {
        let sticker_id = Uuid::new_v4();
        let extension = get_extension_from_content_type(content_type);
        let key = format!("packs/{}/{}.{}", pack_id, sticker_id, extension);

        let url = self
            .minio
            .upload_file(self.minio.stickers_bucket(), &key, data, content_type)
            .await?;

        let sticker: Sticker = sqlx::query_as(
            r#"
            INSERT INTO stickers (id, pack_id, emoji, image_url, position)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            "#,
        )
        .bind(sticker_id)
        .bind(pack_id)
        .bind(emoji)
        .bind(&url)
        .bind(position)
        .fetch_one(&self.db)
        .await?;

        Ok(sticker)
    }

    /// Get a single sticker
    pub async fn get_sticker(&self, sticker_id: Uuid) -> AppResult<Sticker> {
        let sticker: Option<Sticker> = sqlx::query_as("SELECT * FROM stickers WHERE id = $1")
            .bind(sticker_id)
            .fetch_optional(&self.db)
            .await?;

        sticker.ok_or(AppError::StickerPackNotFound)
    }
}

fn get_extension_from_content_type(content_type: &str) -> &str {
    match content_type {
        "image/png" => "png",
        "image/jpeg" | "image/jpg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "application/json" => "json",
        _ => "bin",
    }
}
