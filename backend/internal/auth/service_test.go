package auth

import (
	"context"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestGenerateOTP(t *testing.T) {
	tests := []struct {
		name   string
		length int
	}{
		{"6 digit OTP", 6},
		{"4 digit OTP", 4},
		{"8 digit OTP", 8},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			otp, err := generateOTP(tt.length)
			if err != nil {
				t.Fatalf("generateOTP failed: %v", err)
			}

			if len(otp) != tt.length {
				t.Errorf("Expected OTP length %d, got %d", tt.length, len(otp))
			}

			// Verify all characters are digits
			for _, c := range otp {
				if c < '0' || c > '9' {
					t.Errorf("OTP contains non-digit character: %c", c)
				}
			}
		})
	}
}

func TestGenerateOTP_Uniqueness(t *testing.T) {
	otps := make(map[string]bool)
	iterations := 100

	for i := 0; i < iterations; i++ {
		otp, err := generateOTP(6)
		if err != nil {
			t.Fatalf("generateOTP failed: %v", err)
		}
		otps[otp] = true
	}

	// With 6 digits, we should have high uniqueness
	// Allow for some collisions but expect at least 90% unique
	if len(otps) < iterations*90/100 {
		t.Errorf("Expected at least %d unique OTPs, got %d", iterations*90/100, len(otps))
	}
}

func TestHashToken(t *testing.T) {
	token := "test-token-12345"

	hash, err := hashToken(token)
	if err != nil {
		t.Fatalf("hashToken failed: %v", err)
	}

	if hash == "" {
		t.Error("Expected non-empty hash")
	}

	if hash == token {
		t.Error("Hash should not equal original token")
	}

	// Hash should be bcrypt format
	if len(hash) < 60 {
		t.Error("Bcrypt hash should be at least 60 characters")
	}
}

func TestHashToken_DifferentTokens(t *testing.T) {
	token1 := "token-1"
	token2 := "token-2"

	hash1, _ := hashToken(token1)
	hash2, _ := hashToken(token2)

	if hash1 == hash2 {
		t.Error("Different tokens should produce different hashes")
	}
}

func TestClaims_Structure(t *testing.T) {
	claims := Claims{
		UserID:   "user-123",
		DeviceID: "device-456",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "ansible-talk",
		},
	}

	if claims.UserID != "user-123" {
		t.Errorf("Expected UserID 'user-123', got '%s'", claims.UserID)
	}

	if claims.DeviceID != "device-456" {
		t.Errorf("Expected DeviceID 'device-456', got '%s'", claims.DeviceID)
	}
}

func TestTokenPair_Structure(t *testing.T) {
	expiresAt := time.Now().Add(15 * time.Minute)
	pair := TokenPair{
		AccessToken:  "access-token-xyz",
		RefreshToken: "refresh-token-abc",
		ExpiresAt:    expiresAt,
	}

	if pair.AccessToken != "access-token-xyz" {
		t.Errorf("Expected AccessToken 'access-token-xyz', got '%s'", pair.AccessToken)
	}

	if pair.RefreshToken != "refresh-token-abc" {
		t.Errorf("Expected RefreshToken 'refresh-token-abc', got '%s'", pair.RefreshToken)
	}

	if !pair.ExpiresAt.Equal(expiresAt) {
		t.Errorf("Expected ExpiresAt %v, got %v", expiresAt, pair.ExpiresAt)
	}
}

func TestRegisterRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request RegisterRequest
		wantErr bool
	}{
		{
			name: "valid with phone",
			request: RegisterRequest{
				Phone:       strPtr("+1234567890"),
				Username:    "testuser",
				DisplayName: "Test User",
				DeviceName:  "iPhone 15",
				Platform:    "ios",
			},
			wantErr: false,
		},
		{
			name: "valid with email",
			request: RegisterRequest{
				Email:       strPtr("test@example.com"),
				Username:    "testuser",
				DisplayName: "Test User",
				DeviceName:  "Pixel 8",
				Platform:    "android",
			},
			wantErr: false,
		},
		{
			name: "valid with both phone and email",
			request: RegisterRequest{
				Phone:       strPtr("+1234567890"),
				Email:       strPtr("test@example.com"),
				Username:    "testuser",
				DisplayName: "Test User",
				DeviceName:  "iPhone 15",
				Platform:    "ios",
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test that the request structure is valid
			hasContact := tt.request.Phone != nil || tt.request.Email != nil
			if !hasContact && !tt.wantErr {
				t.Error("Expected phone or email for valid request")
			}
		})
	}
}

func TestErrors(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{"InvalidCredentials", ErrInvalidCredentials, "invalid credentials"},
		{"UserNotFound", ErrUserNotFound, "user not found"},
		{"UserAlreadyExists", ErrUserAlreadyExists, "user already exists"},
		{"InvalidOTP", ErrInvalidOTP, "invalid or expired OTP"},
		{"TooManyAttempts", ErrTooManyAttempts, "too many verification attempts"},
		{"OTPExpired", ErrOTPExpired, "OTP has expired"},
		{"SessionExpired", ErrSessionExpired, "session has expired"},
		{"InvalidToken", ErrInvalidToken, "invalid token"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.err.Error() != tt.expected {
				t.Errorf("Expected error message '%s', got '%s'", tt.expected, tt.err.Error())
			}
		})
	}
}

func TestJWT_SignAndVerify(t *testing.T) {
	secret := []byte("test-secret-key")
	userID := "550e8400-e29b-41d4-a716-446655440000"
	deviceID := "device-123"

	// Create claims
	claims := Claims{
		UserID:   userID,
		DeviceID: deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "ansible-talk",
		},
	}

	// Sign token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(secret)
	if err != nil {
		t.Fatalf("Failed to sign token: %v", err)
	}

	// Verify token
	parsedToken, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return secret, nil
	})
	if err != nil {
		t.Fatalf("Failed to parse token: %v", err)
	}

	parsedClaims, ok := parsedToken.Claims.(*Claims)
	if !ok {
		t.Fatal("Failed to cast claims")
	}

	if parsedClaims.UserID != userID {
		t.Errorf("Expected UserID '%s', got '%s'", userID, parsedClaims.UserID)
	}

	if parsedClaims.DeviceID != deviceID {
		t.Errorf("Expected DeviceID '%s', got '%s'", deviceID, parsedClaims.DeviceID)
	}
}

func TestJWT_ExpiredToken(t *testing.T) {
	secret := []byte("test-secret-key")

	// Create expired claims
	claims := Claims{
		UserID:   "user-123",
		DeviceID: "device-123",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-time.Hour)), // Expired
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
			Issuer:    "ansible-talk",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString(secret)

	// Try to verify expired token
	_, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return secret, nil
	})

	if err == nil {
		t.Error("Expected error for expired token")
	}
}

func TestJWT_InvalidSignature(t *testing.T) {
	secret1 := []byte("secret-1")
	secret2 := []byte("secret-2")

	claims := Claims{
		UserID:   "user-123",
		DeviceID: "device-123",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "ansible-talk",
		},
	}

	// Sign with secret1
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString(secret1)

	// Try to verify with secret2
	_, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return secret2, nil
	})

	if err == nil {
		t.Error("Expected error for invalid signature")
	}
}

func TestService_NewService(t *testing.T) {
	// Test that NewService creates a service with proper nil handling
	service := NewService(nil, nil, nil)

	if service == nil {
		t.Error("NewService should not return nil")
	}

	if service.db != nil {
		t.Error("Expected nil db")
	}

	if service.redis != nil {
		t.Error("Expected nil redis")
	}

	if service.config != nil {
		t.Error("Expected nil config")
	}
}

// Mock context for testing
func TestContext_Timeout(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	// Simulate work
	time.Sleep(50 * time.Millisecond)

	select {
	case <-ctx.Done():
		t.Error("Context should not be done yet")
	default:
		// Expected - context still valid
	}
}

func TestContext_Cancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	// Cancel immediately
	cancel()

	select {
	case <-ctx.Done():
		// Expected - context is cancelled
	default:
		t.Error("Context should be done after cancellation")
	}
}

// Helper function
func strPtr(s string) *string {
	return &s
}
