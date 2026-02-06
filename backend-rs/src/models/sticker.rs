use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct StickerPack {
    pub id: Uuid,
    pub name: String,
    pub author: String,
    pub description: Option<String>,
    pub cover_url: Option<String>,
    pub is_official: bool,
    pub is_animated: bool,
    pub price: i32,
    pub downloads: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Sticker {
    pub id: Uuid,
    pub pack_id: Uuid,
    pub emoji: String,
    pub image_url: String,
    pub position: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UserStickerPack {
    pub id: Uuid,
    pub user_id: Uuid,
    pub pack_id: Uuid,
    pub position: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StickerPackWithStickers {
    #[serde(flatten)]
    pub pack: StickerPack,
    pub stickers: Vec<Sticker>,
}
