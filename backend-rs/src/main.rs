use std::sync::Arc;

use axum::{routing::get, Router};
use sqlx::postgres::PgPoolOptions;
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod api;
mod config;
mod error;
mod models;
mod services;
mod storage;

use config::Config;
use storage::{minio::MinioClient, redis::RedisClient};

#[derive(Clone)]
pub struct AppState {
    pub db: sqlx::PgPool,
    pub redis: RedisClient,
    pub minio: MinioClient,
    pub config: Arc<Config>,
    pub ws_hub: Arc<api::websocket::WsHub>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "ansible_talk_backend=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Config::load();
    tracing::info!("Starting server in {} mode", config.server.environment);

    // Initialize database pool
    let db = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database_url())
        .await?;
    tracing::info!("Connected to PostgreSQL");

    // Run migrations
    sqlx::migrate!("./migrations").run(&db).await?;
    tracing::info!("Database migrations completed");

    // Initialize Redis
    let redis = RedisClient::new(&config.redis_url()).await?;
    tracing::info!("Connected to Redis");

    // Initialize MinIO
    let minio = MinioClient::new(&config.minio).await?;
    minio.ensure_buckets().await?;
    tracing::info!("Connected to MinIO");

    // Initialize WebSocket hub
    let ws_hub = Arc::new(api::websocket::WsHub::new(redis.clone()));

    // Spawn hub runner
    let hub_clone = ws_hub.clone();
    tokio::spawn(async move {
        hub_clone.run().await;
    });

    // Create app state
    let state = AppState {
        db,
        redis,
        minio,
        config: Arc::new(config.clone()),
        ws_hub,
    };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .nest("/api/v1", api::router::create_router(state.clone()))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let addr = format!("{}:{}", config.server.host, config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("Server listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}
