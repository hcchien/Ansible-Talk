use axum::{
    extract::{Request, State},
    http::header::AUTHORIZATION,
    middleware::Next,
    response::Response,
};
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    services::auth::Claims,
    AppState,
};

/// Authentication middleware
pub async fn auth_middleware(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let token = request
        .headers()
        .get(AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or(AppError::Unauthorized)?;

    let auth_service = crate::services::auth::AuthService::new(
        state.db.clone(),
        state.redis.clone(),
        (*state.config).clone(),
    );

    let claims = auth_service.validate_token(token)?;

    // Insert claims into request extensions
    request.extensions_mut().insert(claims);

    Ok(next.run(request).await)
}

/// Extract user_id from request extensions
pub fn get_user_id(claims: &Claims) -> AppResult<Uuid> {
    Uuid::parse_str(&claims.sub).map_err(|_| AppError::InvalidToken)
}

/// Extract device_id from request extensions
pub fn get_device_id(claims: &Claims) -> AppResult<i32> {
    claims
        .device_id
        .parse()
        .map_err(|_| AppError::InvalidToken)
}
