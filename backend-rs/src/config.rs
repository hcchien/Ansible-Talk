use std::env;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct Config {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub minio: MinioConfig,
    pub jwt: JwtConfig,
    pub otp: OtpConfig,
}

#[derive(Debug, Clone)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub environment: String,
}

#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: String,
    pub database: String,
    pub ssl_mode: String,
    pub max_connections: u32,
}

#[derive(Debug, Clone)]
pub struct RedisConfig {
    pub host: String,
    pub port: u16,
    pub password: Option<String>,
    pub db: i64,
}

#[derive(Debug, Clone)]
pub struct MinioConfig {
    pub endpoint: String,
    pub access_key: String,
    pub secret_key: String,
    pub use_ssl: bool,
    pub region: String,
    pub stickers_bucket: String,
    pub avatars_bucket: String,
    pub attachments_bucket: String,
    pub public_url: Option<String>,
}

#[derive(Debug, Clone)]
pub struct JwtConfig {
    pub secret: String,
    pub access_token_ttl: Duration,
    pub refresh_token_ttl: Duration,
    pub issuer: String,
}

#[derive(Debug, Clone)]
pub struct OtpConfig {
    pub length: usize,
    pub ttl: Duration,
    pub max_attempts: u32,
}

impl Config {
    pub fn load() -> Self {
        dotenvy::dotenv().ok();

        Config {
            server: ServerConfig {
                host: env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: env::var("SERVER_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(8080),
                environment: env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
            },
            database: DatabaseConfig {
                host: env::var("DB_HOST").unwrap_or_else(|_| "localhost".to_string()),
                port: env::var("DB_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(5432),
                user: env::var("DB_USER").unwrap_or_else(|_| "postgres".to_string()),
                password: env::var("DB_PASSWORD").unwrap_or_else(|_| "postgres".to_string()),
                database: env::var("DB_NAME").unwrap_or_else(|_| "ansible_talk".to_string()),
                ssl_mode: env::var("DB_SSL_MODE").unwrap_or_else(|_| "disable".to_string()),
                max_connections: env::var("DB_MAX_CONNS")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(25),
            },
            redis: RedisConfig {
                host: env::var("REDIS_HOST").unwrap_or_else(|_| "localhost".to_string()),
                port: env::var("REDIS_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(6379),
                password: env::var("REDIS_PASSWORD").ok(),
                db: env::var("REDIS_DB")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(0),
            },
            minio: MinioConfig {
                endpoint: env::var("MINIO_ENDPOINT")
                    .unwrap_or_else(|_| "http://localhost:9000".to_string()),
                access_key: env::var("MINIO_ACCESS_KEY")
                    .unwrap_or_else(|_| "minioadmin".to_string()),
                secret_key: env::var("MINIO_SECRET_KEY")
                    .unwrap_or_else(|_| "minioadmin".to_string()),
                use_ssl: env::var("MINIO_USE_SSL")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(false),
                region: env::var("MINIO_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
                stickers_bucket: "stickers".to_string(),
                avatars_bucket: "avatars".to_string(),
                attachments_bucket: "attachments".to_string(),
                public_url: env::var("MINIO_PUBLIC_URL").ok(),
            },
            jwt: JwtConfig {
                secret: env::var("JWT_SECRET")
                    .unwrap_or_else(|_| "super-secret-jwt-key-change-in-production".to_string()),
                access_token_ttl: Duration::from_secs(
                    env::var("JWT_ACCESS_TOKEN_TTL")
                        .ok()
                        .and_then(|p| p.parse().ok())
                        .unwrap_or(15 * 60), // 15 minutes
                ),
                refresh_token_ttl: Duration::from_secs(
                    env::var("JWT_REFRESH_TOKEN_TTL")
                        .ok()
                        .and_then(|p| p.parse().ok())
                        .unwrap_or(7 * 24 * 60 * 60), // 7 days
                ),
                issuer: env::var("JWT_ISSUER").unwrap_or_else(|_| "ansible-talk".to_string()),
            },
            otp: OtpConfig {
                length: env::var("OTP_LENGTH")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(6),
                ttl: Duration::from_secs(
                    env::var("OTP_TTL")
                        .ok()
                        .and_then(|p| p.parse().ok())
                        .unwrap_or(5 * 60), // 5 minutes
                ),
                max_attempts: env::var("OTP_MAX_ATTEMPTS")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(3),
            },
        }
    }

    pub fn database_url(&self) -> String {
        format!(
            "postgres://{}:{}@{}:{}/{}?sslmode={}",
            self.database.user,
            self.database.password,
            self.database.host,
            self.database.port,
            self.database.database,
            self.database.ssl_mode
        )
    }

    pub fn redis_url(&self) -> String {
        match &self.redis.password {
            Some(password) => format!(
                "redis://:{}@{}:{}/{}",
                password, self.redis.host, self.redis.port, self.redis.db
            ),
            None => format!(
                "redis://{}:{}/{}",
                self.redis.host, self.redis.port, self.redis.db
            ),
        }
    }
}
