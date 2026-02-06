use axum::{
    extract::{Multipart, Query, State},
    Extension, Json,
};
use serde::{Deserialize, Serialize};

use crate::{
    error::{AppError, AppResult},
    models::User,
    services::{auth::Claims, contacts::ContactsService},
    AppState,
};

use super::super::middleware::get_user_id;

pub async fn get_current_user(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<User>> {
    let user_id = get_user_id(&claims)?;

    let user: Option<User> = sqlx::query_as(
        r#"
        SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at, created_at, updated_at
        FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;

    let user = user.ok_or(AppError::UserNotFound)?;
    Ok(Json(user))
}

#[derive(Debug, Deserialize)]
pub struct UpdateUserRequest {
    pub display_name: Option<String>,
    pub username: Option<String>,
    pub bio: Option<String>,
}

pub async fn update_current_user(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<UpdateUserRequest>,
) -> AppResult<Json<User>> {
    let user_id = get_user_id(&claims)?;

    if req.display_name.is_none() && req.username.is_none() && req.bio.is_none() {
        return Err(AppError::BadRequest("No fields to update".to_string()));
    }

    let user: User = sqlx::query_as(
        r#"
        UPDATE users
        SET display_name = COALESCE($1, display_name),
            username = COALESCE($2, username),
            bio = COALESCE($3, bio),
            updated_at = NOW()
        WHERE id = $4
        RETURNING *
        "#,
    )
    .bind(&req.display_name)
    .bind(&req.username)
    .bind(&req.bio)
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(user))
}

#[derive(Debug, Serialize)]
pub struct AvatarResponse {
    pub avatar_url: String,
}

pub async fn upload_avatar(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    mut multipart: Multipart,
) -> AppResult<Json<AvatarResponse>> {
    let user_id = get_user_id(&claims)?;

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        AppError::BadRequest(format!("Failed to read multipart field: {}", e))
    })? {
        let name = field.name().unwrap_or("").to_string();
        if name != "avatar" {
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

        let extension = match content_type.as_str() {
            "image/png" => "png",
            "image/jpeg" | "image/jpg" => "jpg",
            "image/gif" => "gif",
            "image/webp" => "webp",
            _ => "bin",
        };

        let key = format!("avatars/{}/avatar.{}", user_id, extension);
        let avatar_url = state
            .minio
            .upload_file(state.minio.avatars_bucket(), &key, data, &content_type)
            .await?;

        // Update user
        sqlx::query("UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2")
            .bind(&avatar_url)
            .bind(user_id)
            .execute(&state.db)
            .await?;

        return Ok(Json(AvatarResponse { avatar_url }));
    }

    Err(AppError::BadRequest("Avatar file required".to_string()))
}

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
}

fn default_limit() -> i32 {
    20
}

pub async fn search_users(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Query(query): Query<SearchQuery>,
) -> AppResult<Json<Vec<User>>> {
    let user_id = get_user_id(&claims)?;

    if query.q.is_empty() {
        return Err(AppError::BadRequest("Search query required".to_string()));
    }

    let contacts_service = ContactsService::new(state.db.clone());
    let mut users = contacts_service.search_users(&query.q, query.limit).await?;

    // Filter out current user
    users.retain(|u| u.id != user_id);

    Ok(Json(users))
}
