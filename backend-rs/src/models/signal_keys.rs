use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SignalIdentityKey {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: i32,
    pub public_key: Vec<u8>,
    pub registration_id: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SignalSignedPreKey {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: i32,
    pub key_id: i32,
    pub public_key: Vec<u8>,
    pub signature: Vec<u8>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SignalPreKey {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: i32,
    pub key_id: i32,
    pub public_key: Vec<u8>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyBundle {
    pub user_id: Uuid,
    pub device_id: i32,
    pub registration_id: i32,
    pub identity_key: String, // Base64 encoded
    pub signed_pre_key: SignedPreKeyBundle,
    pub pre_key: Option<PreKeyBundle>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedPreKeyBundle {
    pub key_id: i32,
    pub public_key: String, // Base64 encoded
    pub signature: String,  // Base64 encoded
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKeyBundle {
    pub key_id: i32,
    pub public_key: String, // Base64 encoded
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterKeysRequest {
    pub device_id: i32,
    pub registration_id: i32,
    pub identity_key: String, // Base64 encoded
    pub signed_pre_key: SignedPreKeyBundle,
    pub pre_keys: Vec<PreKeyBundle>,
}
