use axum::{
    extract::{Multipart, Path, Query, State},
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    models::{Sticker, StickerPack, StickerPackWithStickers},
    services::{auth::Claims, stickers::StickersService},
    AppState,
};

use super::super::middleware::get_user_id;

#[derive(Debug, Deserialize)]
pub struct CatalogQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
    pub official: Option<bool>,
}

fn default_limit() -> i32 {
    20
}

pub async fn get_catalog(
    State(state): State<AppState>,
    Query(query): Query<CatalogQuery>,
) -> AppResult<Json<Vec<StickerPack>>> {
    let stickers_service = StickersService::new(state.db, state.minio);
    let packs = stickers_service
        .get_catalog(query.limit, query.offset, query.official)
        .await?;

    Ok(Json(packs))
}

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
}

pub async fn search_stickers(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> AppResult<Json<Vec<StickerPack>>> {
    if query.q.is_empty() {
        return Err(AppError::BadRequest("Search query required".to_string()));
    }

    let stickers_service = StickersService::new(state.db, state.minio);
    let packs = stickers_service.search_packs(&query.q, query.limit).await?;

    Ok(Json(packs))
}

pub async fn get_sticker_pack(
    State(state): State<AppState>,
    Path(pack_id): Path<Uuid>,
) -> AppResult<Json<StickerPackWithStickers>> {
    let stickers_service = StickersService::new(state.db, state.minio);
    let pack = stickers_service.get_pack(pack_id).await?;

    Ok(Json(pack))
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn download_sticker_pack(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(pack_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let stickers_service = StickersService::new(state.db, state.minio);
    stickers_service.download_pack(user_id, pack_id).await?;

    Ok(Json(MessageResponse {
        message: "Pack downloaded".to_string(),
    }))
}

pub async fn remove_sticker_pack(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(pack_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let stickers_service = StickersService::new(state.db, state.minio);
    stickers_service.remove_pack(user_id, pack_id).await?;

    Ok(Json(MessageResponse {
        message: "Pack removed".to_string(),
    }))
}

pub async fn get_user_sticker_packs(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<Vec<StickerPackWithStickers>>> {
    let user_id = get_user_id(&claims)?;

    let stickers_service = StickersService::new(state.db, state.minio);
    let packs = stickers_service.get_user_packs(user_id).await?;

    Ok(Json(packs))
}

#[derive(Debug, Deserialize)]
pub struct ReorderRequest {
    pub pack_ids: Vec<Uuid>,
}

pub async fn reorder_sticker_packs(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<ReorderRequest>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let stickers_service = StickersService::new(state.db, state.minio);
    stickers_service.reorder_packs(user_id, req.pack_ids).await?;

    Ok(Json(MessageResponse {
        message: "Packs reordered".to_string(),
    }))
}

// Admin endpoints

#[derive(Debug, Deserialize)]
pub struct CreatePackRequest {
    pub name: String,
    pub author: String,
    pub description: Option<String>,
    #[serde(default)]
    pub is_official: bool,
    #[serde(default)]
    pub is_animated: bool,
}

pub async fn create_sticker_pack(
    State(state): State<AppState>,
    Json(req): Json<CreatePackRequest>,
) -> AppResult<Json<StickerPack>> {
    let stickers_service = StickersService::new(state.db, state.minio);
    let pack = stickers_service
        .create_pack(
            &req.name,
            &req.author,
            req.description.as_deref(),
            req.is_official,
            req.is_animated,
        )
        .await?;

    Ok(Json(pack))
}

#[derive(Debug, Serialize)]
pub struct CoverResponse {
    pub cover_url: String,
}

pub async fn upload_pack_cover(
    State(state): State<AppState>,
    Path(pack_id): Path<Uuid>,
    mut multipart: Multipart,
) -> AppResult<Json<CoverResponse>> {
    while let Some(field) = multipart.next_field().await.map_err(|e| {
        AppError::BadRequest(format!("Failed to read multipart field: {}", e))
    })? {
        let name = field.name().unwrap_or("").to_string();
        if name != "cover" {
            continue;
        }

        let content_type = field
            .content_type()
            .unwrap_or("application/octet-stream")
            .to_string();
        let data = field
            .bytes()
            .await
            .map_err(|e| AppError::BadRequest(format!("Failed to read file: {}", e)))?;

        let stickers_service = StickersService::new(state.db, state.minio);
        let cover_url = stickers_service
            .upload_pack_cover(pack_id, data, &content_type)
            .await?;

        return Ok(Json(CoverResponse { cover_url }));
    }

    Err(AppError::BadRequest("Cover file required".to_string()))
}

pub async fn add_sticker(
    State(state): State<AppState>,
    Path(pack_id): Path<Uuid>,
    mut multipart: Multipart,
) -> AppResult<Json<Sticker>> {
    let mut emoji = String::new();
    let mut position = 0i32;
    let mut file_data = None;
    let mut content_type = String::from("application/octet-stream");

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        AppError::BadRequest(format!("Failed to read multipart field: {}", e))
    })? {
        let name = field.name().unwrap_or("").to_string();

        match name.as_str() {
            "emoji" => {
                emoji = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Failed to read emoji: {}", e)))?;
            }
            "position" => {
                let pos_str = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Failed to read position: {}", e)))?;
                position = pos_str.parse().unwrap_or(0);
            }
            "sticker" => {
                content_type = field
                    .content_type()
                    .unwrap_or("application/octet-stream")
                    .to_string();
                file_data = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|e| AppError::BadRequest(format!("Failed to read file: {}", e)))?,
                );
            }
            _ => {}
        }
    }

    let data = file_data.ok_or_else(|| AppError::BadRequest("Sticker file required".to_string()))?;

    let stickers_service = StickersService::new(state.db, state.minio);
    let sticker = stickers_service
        .add_sticker(pack_id, &emoji, position, data, &content_type)
        .await?;

    Ok(Json(sticker))
}
