package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/ansible-talk/backend/internal/config"
	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/storage"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserNotFound       = errors.New("user not found")
	ErrUserAlreadyExists  = errors.New("user already exists")
	ErrInvalidOTP         = errors.New("invalid or expired OTP")
	ErrTooManyAttempts    = errors.New("too many verification attempts")
	ErrOTPExpired         = errors.New("OTP has expired")
	ErrSessionExpired     = errors.New("session has expired")
	ErrInvalidToken       = errors.New("invalid token")
)

// Service handles authentication operations
type Service struct {
	db     *storage.PostgresDB
	redis  *storage.RedisClient
	config *config.Config
}

// NewService creates a new auth service
func NewService(db *storage.PostgresDB, redis *storage.RedisClient, cfg *config.Config) *Service {
	return &Service{
		db:     db,
		redis:  redis,
		config: cfg,
	}
}

// Claims represents JWT claims
type Claims struct {
	UserID   string `json:"user_id"`
	DeviceID string `json:"device_id"`
	jwt.RegisteredClaims
}

// TokenPair represents access and refresh tokens
type TokenPair struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

// SendOTP generates and sends an OTP to the target (phone or email)
func (s *Service) SendOTP(ctx context.Context, target string, otpType models.OTPType) error {
	// Generate OTP code
	code, err := generateOTP(s.config.OTP.Length)
	if err != nil {
		return fmt.Errorf("failed to generate OTP: %w", err)
	}

	expiresAt := time.Now().Add(s.config.OTP.TTL)

	// Store OTP in database
	_, err = s.db.Pool.Exec(ctx, `
		INSERT INTO otps (target, type, code, expires_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (target, type)
		DO UPDATE SET code = $3, expires_at = $4, attempts = 0, verified = FALSE
	`, target, otpType, code, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to store OTP: %w", err)
	}

	// Also store in Redis for faster lookups
	err = s.redis.SetOTP(ctx, string(otpType)+":"+target, code, s.config.OTP.TTL)
	if err != nil {
		return fmt.Errorf("failed to cache OTP: %w", err)
	}

	// Send OTP via SMS or Email
	if otpType == models.OTPTypePhone {
		if err := s.sendSMS(target, code); err != nil {
			return fmt.Errorf("failed to send SMS: %w", err)
		}
	} else {
		if err := s.sendEmail(target, code); err != nil {
			return fmt.Errorf("failed to send email: %w", err)
		}
	}

	return nil
}

// VerifyOTP verifies an OTP code
func (s *Service) VerifyOTP(ctx context.Context, target string, otpType models.OTPType, code string) error {
	var otp models.OTP
	err := s.db.Pool.QueryRow(ctx, `
		SELECT id, target, type, code, expires_at, attempts, verified
		FROM otps
		WHERE target = $1 AND type = $2
		ORDER BY created_at DESC
		LIMIT 1
	`, target, otpType).Scan(&otp.ID, &otp.Target, &otp.Type, &otp.Code, &otp.ExpiresAt, &otp.Attempts, &otp.Verified)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidOTP
		}
		return fmt.Errorf("failed to get OTP: %w", err)
	}

	if otp.Verified {
		return ErrInvalidOTP
	}

	if time.Now().After(otp.ExpiresAt) {
		return ErrOTPExpired
	}

	if otp.Attempts >= s.config.OTP.MaxAttempts {
		return ErrTooManyAttempts
	}

	// Increment attempts
	_, err = s.db.Pool.Exec(ctx, `
		UPDATE otps SET attempts = attempts + 1 WHERE id = $1
	`, otp.ID)
	if err != nil {
		return fmt.Errorf("failed to update attempts: %w", err)
	}

	if otp.Code != code {
		return ErrInvalidOTP
	}

	// Mark as verified
	_, err = s.db.Pool.Exec(ctx, `
		UPDATE otps SET verified = TRUE WHERE id = $1
	`, otp.ID)
	if err != nil {
		return fmt.Errorf("failed to mark OTP as verified: %w", err)
	}

	// Clean up Redis
	_ = s.redis.DeleteOTP(ctx, string(otpType)+":"+target)

	return nil
}

// RegisterRequest represents a registration request
type RegisterRequest struct {
	Phone       *string `json:"phone,omitempty"`
	Email       *string `json:"email,omitempty"`
	Username    string  `json:"username"`
	DisplayName string  `json:"display_name"`
	DeviceName  string  `json:"device_name"`
	Platform    string  `json:"platform"`
}

// Register creates a new user account
func (s *Service) Register(ctx context.Context, req RegisterRequest) (*models.User, *TokenPair, error) {
	// Check if user already exists
	var existingID uuid.UUID
	err := s.db.Pool.QueryRow(ctx, `
		SELECT id FROM users WHERE phone = $1 OR email = $2 OR username = $3
	`, req.Phone, req.Email, req.Username).Scan(&existingID)

	if err == nil {
		return nil, nil, ErrUserAlreadyExists
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, nil, fmt.Errorf("failed to check existing user: %w", err)
	}

	// Start transaction
	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Create user
	var user models.User
	err = tx.QueryRow(ctx, `
		INSERT INTO users (phone, email, username, display_name, status)
		VALUES ($1, $2, $3, $4, 'online')
		RETURNING id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at, created_at, updated_at
	`, req.Phone, req.Email, req.Username, req.DisplayName).Scan(
		&user.ID, &user.Phone, &user.Email, &user.Username, &user.DisplayName,
		&user.AvatarURL, &user.Bio, &user.Status, &user.LastSeenAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create user: %w", err)
	}

	// Create device
	var device models.Device
	err = tx.QueryRow(ctx, `
		INSERT INTO devices (user_id, device_id, name, platform)
		VALUES ($1, 1, $2, $3)
		RETURNING id, user_id, device_id, name, platform, last_active_at, created_at
	`, user.ID, req.DeviceName, req.Platform).Scan(
		&device.ID, &device.UserID, &device.DeviceID, &device.Name, &device.Platform,
		&device.LastActiveAt, &device.CreatedAt,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create device: %w", err)
	}

	// Generate tokens
	tokens, err := s.generateTokenPair(user.ID.String(), device.ID.String())
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate tokens: %w", err)
	}

	// Store session
	tokenHash, err := hashToken(tokens.AccessToken)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to hash token: %w", err)
	}
	refreshHash, err := hashToken(tokens.RefreshToken)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to hash refresh token: %w", err)
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO sessions (user_id, device_id, token_hash, refresh_token_hash, expires_at)
		VALUES ($1, $2, $3, $4, $5)
	`, user.ID, device.ID, tokenHash, refreshHash, tokens.ExpiresAt)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create session: %w", err)
	}

	// Commit transaction
	if err := tx.Commit(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Cache session in Redis
	_ = s.redis.SetSession(ctx, user.ID.String(), device.ID.String(), s.config.JWT.AccessTokenTTL)

	return &user, tokens, nil
}

// Login authenticates a user with verified OTP
func (s *Service) Login(ctx context.Context, target string, otpType models.OTPType, deviceName, platform string) (*models.User, *TokenPair, error) {
	// Find user
	var user models.User
	var query string
	if otpType == models.OTPTypePhone {
		query = `SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at, created_at, updated_at FROM users WHERE phone = $1`
	} else {
		query = `SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at, created_at, updated_at FROM users WHERE email = $1`
	}

	err := s.db.Pool.QueryRow(ctx, query, target).Scan(
		&user.ID, &user.Phone, &user.Email, &user.Username, &user.DisplayName,
		&user.AvatarURL, &user.Bio, &user.Status, &user.LastSeenAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil, ErrUserNotFound
		}
		return nil, nil, fmt.Errorf("failed to find user: %w", err)
	}

	// Get or create device
	var device models.Device
	err = s.db.Pool.QueryRow(ctx, `
		SELECT id, user_id, device_id, name, platform, last_active_at, created_at
		FROM devices
		WHERE user_id = $1 AND name = $2 AND platform = $3
	`, user.ID, deviceName, platform).Scan(
		&device.ID, &device.UserID, &device.DeviceID, &device.Name, &device.Platform,
		&device.LastActiveAt, &device.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		// Get next device ID
		var maxDeviceID int
		s.db.Pool.QueryRow(ctx, `SELECT COALESCE(MAX(device_id), 0) FROM devices WHERE user_id = $1`, user.ID).Scan(&maxDeviceID)

		err = s.db.Pool.QueryRow(ctx, `
			INSERT INTO devices (user_id, device_id, name, platform)
			VALUES ($1, $2, $3, $4)
			RETURNING id, user_id, device_id, name, platform, last_active_at, created_at
		`, user.ID, maxDeviceID+1, deviceName, platform).Scan(
			&device.ID, &device.UserID, &device.DeviceID, &device.Name, &device.Platform,
			&device.LastActiveAt, &device.CreatedAt,
		)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to create device: %w", err)
		}
	} else if err != nil {
		return nil, nil, fmt.Errorf("failed to get device: %w", err)
	}

	// Generate tokens
	tokens, err := s.generateTokenPair(user.ID.String(), device.ID.String())
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate tokens: %w", err)
	}

	// Store session
	tokenHash, _ := hashToken(tokens.AccessToken)
	refreshHash, _ := hashToken(tokens.RefreshToken)

	_, err = s.db.Pool.Exec(ctx, `
		INSERT INTO sessions (user_id, device_id, token_hash, refresh_token_hash, expires_at)
		VALUES ($1, $2, $3, $4, $5)
	`, user.ID, device.ID, tokenHash, refreshHash, tokens.ExpiresAt)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create session: %w", err)
	}

	// Update user status
	_, _ = s.db.Pool.Exec(ctx, `UPDATE users SET status = 'online', last_seen_at = NOW() WHERE id = $1`, user.ID)

	// Cache session
	_ = s.redis.SetSession(ctx, user.ID.String(), device.ID.String(), s.config.JWT.AccessTokenTTL)

	return &user, tokens, nil
}

// ValidateToken validates an access token and returns the claims
func (s *Service) ValidateToken(ctx context.Context, tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(s.config.JWT.Secret), nil
	})

	if err != nil {
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

// RefreshToken refreshes an access token using a refresh token
func (s *Service) RefreshToken(ctx context.Context, refreshToken string) (*TokenPair, error) {
	claims, err := s.ValidateToken(ctx, refreshToken)
	if err != nil {
		return nil, err
	}

	// Generate new token pair
	tokens, err := s.generateTokenPair(claims.UserID, claims.DeviceID)
	if err != nil {
		return nil, err
	}

	// Update session
	tokenHash, _ := hashToken(tokens.AccessToken)
	refreshHash, _ := hashToken(tokens.RefreshToken)

	_, err = s.db.Pool.Exec(ctx, `
		UPDATE sessions
		SET token_hash = $1, refresh_token_hash = $2, expires_at = $3, last_used_at = NOW()
		WHERE user_id = $4 AND device_id = $5
	`, tokenHash, refreshHash, tokens.ExpiresAt, claims.UserID, claims.DeviceID)
	if err != nil {
		return nil, fmt.Errorf("failed to update session: %w", err)
	}

	return tokens, nil
}

// Logout invalidates a session
func (s *Service) Logout(ctx context.Context, userID, deviceID string) error {
	_, err := s.db.Pool.Exec(ctx, `
		DELETE FROM sessions WHERE user_id = $1 AND device_id = $2
	`, userID, deviceID)
	if err != nil {
		return fmt.Errorf("failed to delete session: %w", err)
	}

	// Remove from Redis
	_ = s.redis.DeleteSession(ctx, userID, deviceID)

	// Update user status
	_, _ = s.db.Pool.Exec(ctx, `UPDATE users SET status = 'offline', last_seen_at = NOW() WHERE id = $1`, userID)

	return nil
}

// LogoutAll invalidates all sessions for a user
func (s *Service) LogoutAll(ctx context.Context, userID string) error {
	_, err := s.db.Pool.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, userID)
	if err != nil {
		return fmt.Errorf("failed to delete sessions: %w", err)
	}

	_ = s.redis.DeleteAllUserSessions(ctx, userID)

	return nil
}

// Helper functions

func (s *Service) generateTokenPair(userID, deviceID string) (*TokenPair, error) {
	now := time.Now()
	accessExpiry := now.Add(s.config.JWT.AccessTokenTTL)
	refreshExpiry := now.Add(s.config.JWT.RefreshTokenTTL)

	accessClaims := Claims{
		UserID:   userID,
		DeviceID: deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(accessExpiry),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    s.config.JWT.Issuer,
		},
	}

	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessTokenString, err := accessToken.SignedString([]byte(s.config.JWT.Secret))
	if err != nil {
		return nil, err
	}

	refreshClaims := Claims{
		UserID:   userID,
		DeviceID: deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(refreshExpiry),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    s.config.JWT.Issuer,
		},
	}

	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString([]byte(s.config.JWT.Secret))
	if err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessTokenString,
		RefreshToken: refreshTokenString,
		ExpiresAt:    accessExpiry,
	}, nil
}

func generateOTP(length int) (string, error) {
	const digits = "0123456789"
	result := make([]byte, length)
	for i := range result {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return "", err
		}
		result[i] = digits[n.Int64()]
	}
	return string(result), nil
}

func hashToken(token string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// sendSMS sends an OTP via SMS (placeholder - implement with actual provider)
func (s *Service) sendSMS(phone, code string) error {
	// In development, just log the code
	if s.config.Server.Environment == "development" {
		fmt.Printf("[DEV] SMS OTP for %s: %s\n", phone, code)
		return nil
	}

	// TODO: Implement actual SMS sending with Twilio or other provider
	// Example with Twilio:
	// client := twilio.NewRestClient()
	// params := &openapi.CreateMessageParams{}
	// params.SetTo(phone)
	// params.SetFrom(s.config.SMS.FromNumber)
	// params.SetBody(fmt.Sprintf("Your Ansible Talk verification code is: %s", code))
	// _, err := client.Api.CreateMessage(params)
	// return err

	return nil
}

// sendEmail sends an OTP via email (placeholder - implement with actual provider)
func (s *Service) sendEmail(email, code string) error {
	// In development, just log the code
	if s.config.Server.Environment == "development" {
		fmt.Printf("[DEV] Email OTP for %s: %s\n", email, code)
		return nil
	}

	// TODO: Implement actual email sending with SendGrid or SMTP
	// Example with SendGrid:
	// from := mail.NewEmail(s.config.Email.FromName, s.config.Email.FromEmail)
	// to := mail.NewEmail("", email)
	// subject := "Your Ansible Talk Verification Code"
	// plainTextContent := fmt.Sprintf("Your verification code is: %s", code)
	// htmlContent := fmt.Sprintf("<p>Your verification code is: <strong>%s</strong></p>", code)
	// message := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)
	// client := sendgrid.NewSendClient(s.config.Email.APIKey)
	// _, err := client.Send(message)
	// return err

	return nil
}
