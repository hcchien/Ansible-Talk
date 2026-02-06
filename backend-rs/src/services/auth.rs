use bcrypt::{hash, verify, DEFAULT_COST};
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use rand::Rng;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    config::Config,
    error::{AppError, AppResult},
    models::{Device, Otp, OtpType, Session, TokenPair, User, UserStatus},
    storage::redis::RedisClient,
};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,       // user_id
    pub device_id: String, // device_id
    pub iss: String,       // issuer
    pub exp: i64,          // expiry
    pub iat: i64,          // issued at
}

pub struct AuthService {
    db: PgPool,
    redis: RedisClient,
    config: Config,
}

impl AuthService {
    pub fn new(db: PgPool, redis: RedisClient, config: Config) -> Self {
        Self { db, redis, config }
    }

    // OTP Management
    pub async fn send_otp(&self, target: &str, otp_type: OtpType) -> AppResult<()> {
        let code = self.generate_otp();

        // Store OTP in database
        sqlx::query(
            r#"
            INSERT INTO otps (id, target, type, code, expires_at, attempts, verified)
            VALUES ($1, $2, $3, $4, $5, 0, false)
            ON CONFLICT (target, type)
            DO UPDATE SET code = $4, expires_at = $5, attempts = 0, verified = false
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(target)
        .bind(otp_type)
        .bind(&code)
        .bind(Utc::now() + Duration::seconds(self.config.otp.ttl.as_secs() as i64))
        .execute(&self.db)
        .await?;

        // Also cache in Redis for faster lookup
        self.redis
            .set_otp(target, &code, self.config.otp.ttl)
            .await?;

        // Send OTP via SMS or Email
        match otp_type {
            OtpType::Phone => self.send_sms(target, &code).await?,
            OtpType::Email => self.send_email(target, &code).await?,
        }

        Ok(())
    }

    pub async fn verify_otp(&self, target: &str, otp_type: OtpType, code: &str) -> AppResult<()> {
        // Try Redis first
        if let Some(cached_code) = self.redis.get_otp(target).await? {
            if cached_code == code {
                // Mark as verified in database
                sqlx::query("UPDATE otps SET verified = true WHERE target = $1 AND type = $2")
                    .bind(target)
                    .bind(otp_type)
                    .execute(&self.db)
                    .await?;

                self.redis.delete_otp(target).await?;
                return Ok(());
            }
        }

        // Fallback to database
        let otp: Option<Otp> = sqlx::query_as(
            "SELECT * FROM otps WHERE target = $1 AND type = $2 AND verified = false",
        )
        .bind(target)
        .bind(otp_type)
        .fetch_optional(&self.db)
        .await?;

        let otp = otp.ok_or(AppError::InvalidOtp)?;

        if otp.expires_at < Utc::now() {
            return Err(AppError::OtpExpired);
        }

        if otp.attempts >= self.config.otp.max_attempts as i32 {
            return Err(AppError::TooManyAttempts);
        }

        if otp.code != code {
            // Increment attempts
            sqlx::query("UPDATE otps SET attempts = attempts + 1 WHERE id = $1")
                .bind(otp.id)
                .execute(&self.db)
                .await?;
            return Err(AppError::InvalidOtp);
        }

        // Mark as verified
        sqlx::query("UPDATE otps SET verified = true WHERE id = $1")
            .bind(otp.id)
            .execute(&self.db)
            .await?;

        Ok(())
    }

    // User Registration
    pub async fn register(
        &self,
        phone: Option<&str>,
        email: Option<&str>,
        username: &str,
        display_name: &str,
        device_name: &str,
        platform: &str,
    ) -> AppResult<(User, TokenPair)> {
        // Check if OTP was verified
        let target = phone.or(email).ok_or(AppError::BadRequest(
            "Phone or email required".to_string(),
        ))?;
        let otp_type = if phone.is_some() {
            OtpType::Phone
        } else {
            OtpType::Email
        };

        let otp: Option<Otp> = sqlx::query_as(
            "SELECT * FROM otps WHERE target = $1 AND type = $2 AND verified = true",
        )
        .bind(target)
        .bind(otp_type)
        .fetch_optional(&self.db)
        .await?;

        if otp.is_none() {
            return Err(AppError::OtpNotVerified);
        }

        // Check if user already exists
        let existing: Option<User> =
            sqlx::query_as("SELECT * FROM users WHERE phone = $1 OR email = $2")
                .bind(phone)
                .bind(email)
                .fetch_optional(&self.db)
                .await?;

        if existing.is_some() {
            return Err(AppError::UserAlreadyExists);
        }

        // Create user in transaction
        let mut tx = self.db.begin().await?;

        let user_id = Uuid::new_v4();
        let user: User = sqlx::query_as(
            r#"
            INSERT INTO users (id, phone, email, username, display_name, status)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            "#,
        )
        .bind(user_id)
        .bind(phone)
        .bind(email)
        .bind(username)
        .bind(display_name)
        .bind(UserStatus::Online)
        .fetch_one(&mut *tx)
        .await?;

        // Create device
        let device_id = 1;
        let _device: Device = sqlx::query_as(
            r#"
            INSERT INTO devices (id, user_id, device_id, name, platform, last_active_at)
            VALUES ($1, $2, $3, $4, $5, NOW())
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(device_id)
        .bind(device_name)
        .bind(platform)
        .fetch_one(&mut *tx)
        .await?;

        // Generate tokens
        let tokens = self.generate_token_pair(&user_id.to_string(), &device_id.to_string())?;

        // Store session
        let token_hash = hash(&tokens.access_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;
        let refresh_hash = hash(&tokens.refresh_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;

        sqlx::query(
            r#"
            INSERT INTO sessions (id, user_id, device_id, token_hash, refresh_token_hash, expires_at, last_used_at)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(device_id)
        .bind(token_hash)
        .bind(refresh_hash)
        .bind(tokens.expires_at)
        .execute(&mut *tx)
        .await?;

        // Delete OTP
        sqlx::query("DELETE FROM otps WHERE target = $1 AND type = $2")
            .bind(target)
            .bind(otp_type)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;

        Ok((user, tokens))
    }

    // User Login
    pub async fn login(
        &self,
        target: &str,
        otp_type: OtpType,
        device_name: &str,
        platform: &str,
    ) -> AppResult<(User, TokenPair)> {
        // Check if OTP was verified
        let otp: Option<Otp> = sqlx::query_as(
            "SELECT * FROM otps WHERE target = $1 AND type = $2 AND verified = true",
        )
        .bind(target)
        .bind(otp_type)
        .fetch_optional(&self.db)
        .await?;

        if otp.is_none() {
            return Err(AppError::OtpNotVerified);
        }

        // Find user
        let user: User = match otp_type {
            OtpType::Phone => {
                sqlx::query_as("SELECT * FROM users WHERE phone = $1")
                    .bind(target)
                    .fetch_optional(&self.db)
                    .await?
            }
            OtpType::Email => {
                sqlx::query_as("SELECT * FROM users WHERE email = $1")
                    .bind(target)
                    .fetch_optional(&self.db)
                    .await?
            }
        }
        .ok_or(AppError::UserNotFound)?;

        // Get or create device
        let device: Device = sqlx::query_as(
            r#"
            SELECT * FROM devices WHERE user_id = $1 AND name = $2 AND platform = $3
            "#,
        )
        .bind(user.id)
        .bind(device_name)
        .bind(platform)
        .fetch_optional(&self.db)
        .await?
        .unwrap_or_else(|| Device {
            id: Uuid::new_v4(),
            user_id: user.id,
            device_id: 0, // Will be set below
            name: device_name.to_string(),
            platform: platform.to_string(),
            push_token: None,
            last_active_at: Utc::now(),
            created_at: Utc::now(),
        });

        let device_id = if device.device_id == 0 {
            // Get next device_id
            let max_device_id: Option<i32> = sqlx::query_scalar(
                "SELECT MAX(device_id) FROM devices WHERE user_id = $1",
            )
            .bind(user.id)
            .fetch_one(&self.db)
            .await?;

            let new_device_id = max_device_id.unwrap_or(0) + 1;

            sqlx::query(
                r#"
                INSERT INTO devices (id, user_id, device_id, name, platform, last_active_at)
                VALUES ($1, $2, $3, $4, $5, NOW())
                "#,
            )
            .bind(device.id)
            .bind(user.id)
            .bind(new_device_id)
            .bind(device_name)
            .bind(platform)
            .execute(&self.db)
            .await?;

            new_device_id
        } else {
            // Update last active
            sqlx::query("UPDATE devices SET last_active_at = NOW() WHERE id = $1")
                .bind(device.id)
                .execute(&self.db)
                .await?;
            device.device_id
        };

        // Generate tokens
        let tokens = self.generate_token_pair(&user.id.to_string(), &device_id.to_string())?;

        // Store session
        let token_hash = hash(&tokens.access_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;
        let refresh_hash = hash(&tokens.refresh_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;

        sqlx::query(
            r#"
            INSERT INTO sessions (id, user_id, device_id, token_hash, refresh_token_hash, expires_at, last_used_at)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            ON CONFLICT (user_id, device_id)
            DO UPDATE SET token_hash = $4, refresh_token_hash = $5, expires_at = $6, last_used_at = NOW()
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user.id)
        .bind(device_id)
        .bind(token_hash)
        .bind(refresh_hash)
        .bind(tokens.expires_at)
        .execute(&self.db)
        .await?;

        // Delete OTP
        sqlx::query("DELETE FROM otps WHERE target = $1 AND type = $2")
            .bind(target)
            .bind(otp_type)
            .execute(&self.db)
            .await?;

        // Update user status
        sqlx::query("UPDATE users SET status = $1, last_seen_at = NOW() WHERE id = $2")
            .bind(UserStatus::Online)
            .bind(user.id)
            .execute(&self.db)
            .await?;

        Ok((user, tokens))
    }

    // Token validation
    pub fn validate_token(&self, token: &str) -> AppResult<Claims> {
        let key = DecodingKey::from_secret(self.config.jwt.secret.as_bytes());
        let validation = Validation::default();

        let token_data = decode::<Claims>(token, &key, &validation)?;
        Ok(token_data.claims)
    }

    // Refresh token
    pub async fn refresh_token(&self, refresh_token: &str) -> AppResult<TokenPair> {
        let claims = self.validate_token(refresh_token)?;

        // Check session exists
        let session: Option<Session> = sqlx::query_as(
            "SELECT * FROM sessions WHERE user_id = $1 AND device_id = $2",
        )
        .bind(Uuid::parse_str(&claims.sub).map_err(|_| AppError::InvalidToken)?)
        .bind(claims.device_id.parse::<i32>().map_err(|_| AppError::InvalidToken)?)
        .fetch_optional(&self.db)
        .await?;

        let session = session.ok_or(AppError::InvalidToken)?;

        // Verify refresh token hash
        if !verify(refresh_token, &session.refresh_token_hash)
            .map_err(|e| anyhow::anyhow!("Verify error: {}", e))?
        {
            return Err(AppError::InvalidToken);
        }

        // Generate new tokens
        let tokens = self.generate_token_pair(&claims.sub, &claims.device_id)?;

        // Update session
        let token_hash = hash(&tokens.access_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;
        let refresh_hash = hash(&tokens.refresh_token, DEFAULT_COST)
            .map_err(|e| anyhow::anyhow!("Hash error: {}", e))?;

        sqlx::query(
            "UPDATE sessions SET token_hash = $1, refresh_token_hash = $2, expires_at = $3, last_used_at = NOW() WHERE id = $4",
        )
        .bind(token_hash)
        .bind(refresh_hash)
        .bind(tokens.expires_at)
        .bind(session.id)
        .execute(&self.db)
        .await?;

        Ok(tokens)
    }

    // Logout
    pub async fn logout(&self, user_id: Uuid, device_id: i32) -> AppResult<()> {
        sqlx::query("DELETE FROM sessions WHERE user_id = $1 AND device_id = $2")
            .bind(user_id)
            .bind(device_id)
            .execute(&self.db)
            .await?;

        // Update user status
        sqlx::query("UPDATE users SET status = $1, last_seen_at = NOW() WHERE id = $2")
            .bind(UserStatus::Offline)
            .bind(user_id)
            .execute(&self.db)
            .await?;

        Ok(())
    }

    // Logout all devices
    pub async fn logout_all(&self, user_id: Uuid) -> AppResult<()> {
        sqlx::query("DELETE FROM sessions WHERE user_id = $1")
            .bind(user_id)
            .execute(&self.db)
            .await?;

        self.redis.delete_all_user_sessions(&user_id.to_string()).await?;

        // Update user status
        sqlx::query("UPDATE users SET status = $1, last_seen_at = NOW() WHERE id = $2")
            .bind(UserStatus::Offline)
            .bind(user_id)
            .execute(&self.db)
            .await?;

        Ok(())
    }

    // Helper methods
    fn generate_otp(&self) -> String {
        let mut rng = rand::thread_rng();
        let max = 10_u32.pow(self.config.otp.length as u32);
        let code: u32 = rng.gen_range(0..max);
        format!("{:0>width$}", code, width = self.config.otp.length)
    }

    fn generate_token_pair(&self, user_id: &str, device_id: &str) -> AppResult<TokenPair> {
        let now = Utc::now();
        let access_exp = now + Duration::seconds(self.config.jwt.access_token_ttl.as_secs() as i64);
        let refresh_exp =
            now + Duration::seconds(self.config.jwt.refresh_token_ttl.as_secs() as i64);

        let access_claims = Claims {
            sub: user_id.to_string(),
            device_id: device_id.to_string(),
            iss: self.config.jwt.issuer.clone(),
            exp: access_exp.timestamp(),
            iat: now.timestamp(),
        };

        let refresh_claims = Claims {
            sub: user_id.to_string(),
            device_id: device_id.to_string(),
            iss: self.config.jwt.issuer.clone(),
            exp: refresh_exp.timestamp(),
            iat: now.timestamp(),
        };

        let key = EncodingKey::from_secret(self.config.jwt.secret.as_bytes());

        let access_token = encode(&Header::default(), &access_claims, &key)?;
        let refresh_token = encode(&Header::default(), &refresh_claims, &key)?;

        Ok(TokenPair {
            access_token,
            refresh_token,
            expires_at: access_exp,
        })
    }

    async fn send_sms(&self, phone: &str, code: &str) -> AppResult<()> {
        // In development, just log the code
        if self.config.server.environment == "development" {
            tracing::info!("SMS OTP to {}: {}", phone, code);
            return Ok(());
        }

        // TODO: Implement actual SMS sending (Twilio, etc.)
        tracing::warn!("SMS sending not implemented for production");
        Ok(())
    }

    async fn send_email(&self, email: &str, code: &str) -> AppResult<()> {
        // In development, just log the code
        if self.config.server.environment == "development" {
            tracing::info!("Email OTP to {}: {}", email, code);
            return Ok(());
        }

        // TODO: Implement actual email sending (SendGrid, etc.)
        tracing::warn!("Email sending not implemented for production");
        Ok(())
    }
}
