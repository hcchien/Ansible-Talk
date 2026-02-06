use axum::{
    extract::{Path, Query, State},
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::AppResult,
    models::{ContactWithUser, User},
    services::{auth::Claims, contacts::ContactsService},
    AppState,
};

use super::super::middleware::get_user_id;

#[derive(Debug, Deserialize)]
pub struct GetContactsQuery {
    #[serde(default)]
    pub include_blocked: bool,
}

pub async fn get_contacts(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Query(query): Query<GetContactsQuery>,
) -> AppResult<Json<Vec<ContactWithUser>>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let contacts = contacts_service
        .get_contacts(user_id, query.include_blocked)
        .await?;

    Ok(Json(contacts))
}

#[derive(Debug, Deserialize)]
pub struct AddContactRequest {
    pub contact_id: Uuid,
    pub nickname: Option<String>,
}

pub async fn add_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<AddContactRequest>,
) -> AppResult<Json<ContactWithUser>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let contact = contacts_service
        .add_contact(user_id, req.contact_id, req.nickname.as_deref())
        .await?;

    Ok(Json(contact))
}

pub async fn get_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<ContactWithUser>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let contact = contacts_service.get_contact(user_id, contact_id).await?;

    Ok(Json(contact))
}

#[derive(Debug, Deserialize)]
pub struct UpdateContactRequest {
    pub nickname: Option<String>,
    pub is_favorite: Option<bool>,
}

pub async fn update_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(contact_id): Path<Uuid>,
    Json(req): Json<UpdateContactRequest>,
) -> AppResult<Json<ContactWithUser>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let contact = contacts_service
        .update_contact(user_id, contact_id, req.nickname.as_deref(), req.is_favorite)
        .await?;

    Ok(Json(contact))
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}

pub async fn delete_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    contacts_service.delete_contact(user_id, contact_id).await?;

    Ok(Json(MessageResponse {
        message: "Contact deleted".to_string(),
    }))
}

pub async fn block_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    contacts_service.block_contact(user_id, contact_id).await?;

    Ok(Json(MessageResponse {
        message: "Contact blocked".to_string(),
    }))
}

pub async fn unblock_contact(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<MessageResponse>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    contacts_service.unblock_contact(user_id, contact_id).await?;

    Ok(Json(MessageResponse {
        message: "Contact unblocked".to_string(),
    }))
}

pub async fn get_blocked_contacts(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> AppResult<Json<Vec<ContactWithUser>>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let contacts = contacts_service.get_blocked_contacts(user_id).await?;

    Ok(Json(contacts))
}

#[derive(Debug, Deserialize)]
pub struct SyncContactsRequest {
    pub identifiers: Vec<String>,
}

pub async fn sync_contacts(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<SyncContactsRequest>,
) -> AppResult<Json<Vec<User>>> {
    let user_id = get_user_id(&claims)?;

    let contacts_service = ContactsService::new(state.db);
    let users = contacts_service
        .sync_contacts(user_id, req.identifiers)
        .await?;

    Ok(Json(users))
}
