use axum::{
    middleware,
    routing::{delete, get, post, put},
    Router,
};

use super::{handlers, middleware::auth_middleware, websocket::handle_websocket};
use crate::AppState;

pub fn create_router(state: AppState) -> Router<AppState> {
    // Public auth routes
    let auth_routes = Router::new()
        .route("/otp/send", post(handlers::auth::send_otp))
        .route("/otp/verify", post(handlers::auth::verify_otp))
        .route("/register", post(handlers::auth::register))
        .route("/login", post(handlers::auth::login))
        .route("/refresh", post(handlers::auth::refresh_token));

    // Protected auth routes
    let auth_protected = Router::new()
        .route("/logout", post(handlers::auth::logout))
        .route("/logout-all", post(handlers::auth::logout_all))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // User routes (protected)
    let user_routes = Router::new()
        .route("/me", get(handlers::users::get_current_user))
        .route("/me", put(handlers::users::update_current_user))
        .route("/me/avatar", post(handlers::users::upload_avatar))
        .route("/search", get(handlers::users::search_users))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Device routes (protected)
    let device_routes = Router::new()
        .route("/", get(handlers::devices::get_devices))
        .route("/:id", delete(handlers::devices::remove_device))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Key routes (protected)
    let key_routes = Router::new()
        .route("/register", post(handlers::keys::register_keys))
        .route("/bundle/:user_id/:device_id", get(handlers::keys::get_key_bundle))
        .route("/count", get(handlers::keys::get_pre_key_count))
        .route("/prekeys", post(handlers::keys::refresh_pre_keys))
        .route("/signed-prekey", put(handlers::keys::update_signed_pre_key))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Contact routes (protected)
    let contact_routes = Router::new()
        .route("/", get(handlers::contacts::get_contacts))
        .route("/", post(handlers::contacts::add_contact))
        .route("/:id", get(handlers::contacts::get_contact))
        .route("/:id", put(handlers::contacts::update_contact))
        .route("/:id", delete(handlers::contacts::delete_contact))
        .route("/:id/block", post(handlers::contacts::block_contact))
        .route("/:id/unblock", post(handlers::contacts::unblock_contact))
        .route("/blocked", get(handlers::contacts::get_blocked_contacts))
        .route("/sync", post(handlers::contacts::sync_contacts))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Conversation routes (protected)
    let conversation_routes = Router::new()
        .route("/", get(handlers::conversations::get_conversations))
        .route("/direct", post(handlers::conversations::create_direct_conversation))
        .route("/group", post(handlers::conversations::create_group_conversation))
        .route("/:id", get(handlers::conversations::get_conversation))
        .route("/:id/messages", get(handlers::conversations::get_messages))
        .route("/:id/messages", post(handlers::conversations::send_message))
        .route("/:id/typing", post(handlers::conversations::send_typing))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Message routes (protected)
    let message_routes = Router::new()
        .route("/:id/delivered", post(handlers::messages::mark_delivered))
        .route("/:id/read", post(handlers::messages::mark_read))
        .route("/:id", delete(handlers::messages::delete_message))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Sticker routes (public catalog, protected for user actions)
    let sticker_public_routes = Router::new()
        .route("/catalog", get(handlers::stickers::get_catalog))
        .route("/search", get(handlers::stickers::search_stickers))
        .route("/packs/:id", get(handlers::stickers::get_sticker_pack));

    let sticker_protected_routes = Router::new()
        .route("/packs/:id/download", post(handlers::stickers::download_sticker_pack))
        .route("/packs/:id", delete(handlers::stickers::remove_sticker_pack))
        .route("/my-packs", get(handlers::stickers::get_user_sticker_packs))
        .route("/my-packs/reorder", put(handlers::stickers::reorder_sticker_packs))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Admin sticker routes (protected - would need admin check in production)
    let admin_sticker_routes = Router::new()
        .route("/packs", post(handlers::stickers::create_sticker_pack))
        .route("/packs/:id/cover", post(handlers::stickers::upload_pack_cover))
        .route("/packs/:id/stickers", post(handlers::stickers::add_sticker))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // WebSocket route (protected)
    let ws_route = Router::new()
        .route("/ws", get(handle_websocket))
        .layer(middleware::from_fn_with_state(state.clone(), auth_middleware));

    // Combine all routes
    Router::new()
        .nest("/auth", auth_routes.merge(auth_protected))
        .nest("/users", user_routes)
        .nest("/devices", device_routes)
        .nest("/keys", key_routes)
        .nest("/contacts", contact_routes)
        .nest("/conversations", conversation_routes)
        .nest("/messages", message_routes)
        .nest("/stickers", sticker_public_routes.merge(sticker_protected_routes))
        .nest("/admin/stickers", admin_sticker_routes)
        .merge(ws_route)
        .with_state(state)
}
