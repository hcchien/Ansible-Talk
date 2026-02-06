use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    models::{
        KeyBundle, PreKeyBundle, RegisterKeysRequest, SignedPreKeyBundle,
    },
};

pub struct CryptoService {
    db: PgPool,
}

impl CryptoService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Generate a registration ID (14-bit random number)
    pub fn generate_registration_id() -> i32 {
        let mut rng = rand::thread_rng();
        rng.gen_range(1..16381)
    }

    /// Register Signal protocol keys for a device
    pub async fn register_keys(&self, user_id: Uuid, req: RegisterKeysRequest) -> AppResult<()> {
        let mut tx = self.db.begin().await?;

        // Store identity key
        let identity_key = BASE64
            .decode(&req.identity_key)
            .map_err(|_| AppError::BadRequest("Invalid identity key encoding".to_string()))?;

        sqlx::query(
            r#"
            INSERT INTO signal_identity_keys (id, user_id, device_id, public_key, registration_id)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (user_id, device_id)
            DO UPDATE SET public_key = $4, registration_id = $5, updated_at = NOW()
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(req.device_id)
        .bind(&identity_key)
        .bind(req.registration_id)
        .execute(&mut *tx)
        .await?;

        // Store signed pre-key
        let signed_pre_key_public = BASE64
            .decode(&req.signed_pre_key.public_key)
            .map_err(|_| AppError::BadRequest("Invalid signed pre-key encoding".to_string()))?;
        let signed_pre_key_signature = BASE64
            .decode(&req.signed_pre_key.signature)
            .map_err(|_| AppError::BadRequest("Invalid signature encoding".to_string()))?;

        sqlx::query(
            r#"
            INSERT INTO signal_signed_prekeys (id, user_id, device_id, key_id, public_key, signature)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (user_id, device_id, key_id)
            DO UPDATE SET public_key = $5, signature = $6, updated_at = NOW()
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(req.device_id)
        .bind(req.signed_pre_key.key_id)
        .bind(&signed_pre_key_public)
        .bind(&signed_pre_key_signature)
        .execute(&mut *tx)
        .await?;

        // Store pre-keys
        for pre_key in &req.pre_keys {
            let pre_key_public = BASE64
                .decode(&pre_key.public_key)
                .map_err(|_| AppError::BadRequest("Invalid pre-key encoding".to_string()))?;

            sqlx::query(
                r#"
                INSERT INTO signal_prekeys (id, user_id, device_id, key_id, public_key)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (user_id, device_id, key_id) DO NOTHING
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(user_id)
            .bind(req.device_id)
            .bind(pre_key.key_id)
            .bind(&pre_key_public)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    /// Get key bundle for establishing a session
    pub async fn get_key_bundle(&self, user_id: Uuid, device_id: i32) -> AppResult<KeyBundle> {
        // Get identity key
        let identity: Option<(Vec<u8>, i32)> = sqlx::query_as(
            "SELECT public_key, registration_id FROM signal_identity_keys WHERE user_id = $1 AND device_id = $2",
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_optional(&self.db)
        .await?;

        let (identity_key, registration_id) = identity.ok_or(AppError::IdentityKeyNotFound)?;

        // Get signed pre-key
        let signed_pre_key: Option<(i32, Vec<u8>, Vec<u8>)> = sqlx::query_as(
            "SELECT key_id, public_key, signature FROM signal_signed_prekeys WHERE user_id = $1 AND device_id = $2 ORDER BY key_id DESC LIMIT 1",
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_optional(&self.db)
        .await?;

        let (signed_key_id, signed_public_key, signature) =
            signed_pre_key.ok_or(AppError::IdentityKeyNotFound)?;

        // Get and consume one pre-key (one-time use)
        let pre_key: Option<(Uuid, i32, Vec<u8>)> = sqlx::query_as(
            "SELECT id, key_id, public_key FROM signal_prekeys WHERE user_id = $1 AND device_id = $2 ORDER BY key_id ASC LIMIT 1",
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_optional(&self.db)
        .await?;

        let pre_key_bundle = if let Some((pre_key_id, key_id, public_key)) = pre_key {
            // Delete the pre-key (one-time use)
            sqlx::query("DELETE FROM signal_prekeys WHERE id = $1")
                .bind(pre_key_id)
                .execute(&self.db)
                .await?;

            Some(PreKeyBundle {
                key_id,
                public_key: BASE64.encode(&public_key),
            })
        } else {
            None
        };

        Ok(KeyBundle {
            user_id,
            device_id,
            registration_id,
            identity_key: BASE64.encode(&identity_key),
            signed_pre_key: SignedPreKeyBundle {
                key_id: signed_key_id,
                public_key: BASE64.encode(&signed_public_key),
                signature: BASE64.encode(&signature),
            },
            pre_key: pre_key_bundle,
        })
    }

    /// Get count of available pre-keys
    pub async fn get_pre_key_count(&self, user_id: Uuid, device_id: i32) -> AppResult<i64> {
        let count: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM signal_prekeys WHERE user_id = $1 AND device_id = $2",
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_one(&self.db)
        .await?;

        Ok(count.0)
    }

    /// Refresh pre-keys (upload new batch)
    pub async fn refresh_pre_keys(
        &self,
        user_id: Uuid,
        device_id: i32,
        pre_keys: Vec<PreKeyBundle>,
    ) -> AppResult<()> {
        for pre_key in pre_keys {
            let public_key = BASE64
                .decode(&pre_key.public_key)
                .map_err(|_| AppError::BadRequest("Invalid pre-key encoding".to_string()))?;

            sqlx::query(
                r#"
                INSERT INTO signal_prekeys (id, user_id, device_id, key_id, public_key)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (user_id, device_id, key_id) DO NOTHING
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(user_id)
            .bind(device_id)
            .bind(pre_key.key_id)
            .bind(&public_key)
            .execute(&self.db)
            .await?;
        }

        Ok(())
    }

    /// Update signed pre-key (key rotation)
    pub async fn update_signed_pre_key(
        &self,
        user_id: Uuid,
        device_id: i32,
        signed_pre_key: SignedPreKeyBundle,
    ) -> AppResult<()> {
        let public_key = BASE64
            .decode(&signed_pre_key.public_key)
            .map_err(|_| AppError::BadRequest("Invalid signed pre-key encoding".to_string()))?;
        let signature = BASE64
            .decode(&signed_pre_key.signature)
            .map_err(|_| AppError::BadRequest("Invalid signature encoding".to_string()))?;

        sqlx::query(
            r#"
            INSERT INTO signal_signed_prekeys (id, user_id, device_id, key_id, public_key, signature)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (user_id, device_id, key_id)
            DO UPDATE SET public_key = $5, signature = $6, updated_at = NOW()
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(device_id)
        .bind(signed_pre_key.key_id)
        .bind(&public_key)
        .bind(&signature)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Get all devices for a user
    pub async fn get_user_devices(&self, user_id: Uuid) -> AppResult<Vec<i32>> {
        let devices: Vec<(i32,)> = sqlx::query_as(
            "SELECT DISTINCT device_id FROM signal_identity_keys WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_all(&self.db)
        .await?;

        Ok(devices.into_iter().map(|(d,)| d).collect())
    }
}
