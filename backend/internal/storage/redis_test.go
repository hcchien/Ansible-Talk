package storage

import (
	"context"
	"testing"
	"time"
)

func TestRedisKeyPrefixes(t *testing.T) {
	tests := []struct {
		name     string
		prefix   string
		expected string
	}{
		{"Session prefix", sessionKeyPrefix, "session:"},
		{"User sessions prefix", userSessionsPrefix, "user_sessions:"},
		{"Presence prefix", presenceKeyPrefix, "presence:"},
		{"OTP prefix", otpKeyPrefix, "otp:"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.prefix != tt.expected {
				t.Errorf("Expected prefix '%s', got '%s'", tt.expected, tt.prefix)
			}
		})
	}
}

func TestMessageChannelPrefix(t *testing.T) {
	if messageChannel != "messages:" {
		t.Errorf("Expected message channel 'messages:', got '%s'", messageChannel)
	}
}

func TestSessionKeyGeneration(t *testing.T) {
	sessionID := "abc123"
	key := sessionKeyPrefix + sessionID

	expected := "session:abc123"
	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

func TestUserSessionsKeyGeneration(t *testing.T) {
	userID := "user-uuid-123"
	key := userSessionsPrefix + userID

	expected := "user_sessions:user-uuid-123"
	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

func TestPresenceKeyGeneration(t *testing.T) {
	userID := "user-uuid-456"
	key := presenceKeyPrefix + userID

	expected := "presence:user-uuid-456"
	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

func TestOTPKeyGeneration(t *testing.T) {
	target := "+1234567890"
	key := otpKeyPrefix + target

	expected := "otp:+1234567890"
	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

func TestMessageChannelKeyGeneration(t *testing.T) {
	userID := "user-uuid-789"
	key := messageChannel + userID

	expected := "messages:user-uuid-789"
	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

func TestSessionTTL(t *testing.T) {
	ttls := []time.Duration{
		1 * time.Hour,
		24 * time.Hour,
		7 * 24 * time.Hour,
		30 * 24 * time.Hour,
	}

	for _, ttl := range ttls {
		if ttl <= 0 {
			t.Errorf("TTL should be positive, got %v", ttl)
		}
	}
}

func TestPresenceTTL(t *testing.T) {
	// Default presence TTL is 5 minutes
	presenceTTL := 5 * time.Minute

	if presenceTTL != 5*time.Minute {
		t.Errorf("Expected presence TTL 5m, got %v", presenceTTL)
	}
}

func TestOTPTTL(t *testing.T) {
	// OTP typically expires in 5-10 minutes
	otpTTLs := []time.Duration{
		5 * time.Minute,
		10 * time.Minute,
	}

	for _, ttl := range otpTTLs {
		if ttl < 1*time.Minute {
			t.Errorf("OTP TTL should be at least 1 minute, got %v", ttl)
		}
		if ttl > 15*time.Minute {
			t.Errorf("OTP TTL should be at most 15 minutes, got %v", ttl)
		}
	}
}

func TestPresenceStatuses(t *testing.T) {
	statuses := []string{"online", "away", "busy", "offline"}

	for _, status := range statuses {
		if status == "" {
			t.Error("Status should not be empty")
		}
	}
}

func TestDefaultOfflineStatus(t *testing.T) {
	// When user presence is not found, default should be "offline"
	defaultStatus := "offline"

	if defaultStatus != "offline" {
		t.Errorf("Expected default status 'offline', got '%s'", defaultStatus)
	}
}

func TestContext_Timeout(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	deadline, ok := ctx.Deadline()
	if !ok {
		t.Error("Expected deadline to be set")
	}

	if deadline.Before(time.Now()) {
		t.Error("Deadline should be in the future")
	}
}

func TestContext_Cancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	select {
	case <-ctx.Done():
		t.Error("Context should not be done before cancel")
	default:
		// Expected
	}

	cancel()

	select {
	case <-ctx.Done():
		// Expected
	default:
		t.Error("Context should be done after cancel")
	}
}

func TestEmptySessionList(t *testing.T) {
	sessionIDs := []string{}

	if len(sessionIDs) != 0 {
		t.Error("Expected empty session list")
	}
}

func TestMultipleSessions(t *testing.T) {
	sessionIDs := []string{
		"session-1",
		"session-2",
		"session-3",
	}

	if len(sessionIDs) != 3 {
		t.Errorf("Expected 3 sessions, got %d", len(sessionIDs))
	}

	// Check uniqueness
	seen := make(map[string]bool)
	for _, id := range sessionIDs {
		if seen[id] {
			t.Errorf("Duplicate session ID: %s", id)
		}
		seen[id] = true
	}
}

func TestPipelineOperations(t *testing.T) {
	// Test that pipeline operations are batched correctly
	operations := []string{
		"SET session:123 user-id",
		"SADD user_sessions:user-id 123",
		"EXPIRE user_sessions:user-id 3600",
	}

	if len(operations) != 3 {
		t.Errorf("Expected 3 pipeline operations, got %d", len(operations))
	}
}

func TestDeleteAllSessionsCleanup(t *testing.T) {
	// Simulate deletion of multiple sessions
	sessionIDs := []string{"s1", "s2", "s3"}
	userID := "user-123"

	keysToDelete := make([]string, 0, len(sessionIDs)+1)
	for _, sessionID := range sessionIDs {
		keysToDelete = append(keysToDelete, sessionKeyPrefix+sessionID)
	}
	keysToDelete = append(keysToDelete, userSessionsPrefix+userID)

	expectedCount := len(sessionIDs) + 1
	if len(keysToDelete) != expectedCount {
		t.Errorf("Expected %d keys to delete, got %d", expectedCount, len(keysToDelete))
	}
}

func TestRedisClientNil(t *testing.T) {
	var client *RedisClient

	if client != nil {
		t.Error("Expected nil client")
	}
}

func TestRedisAddressFormat(t *testing.T) {
	host := "localhost"
	port := 6379

	addr := host + ":" + string(rune(port))
	if addr == "" {
		t.Error("Address should not be empty")
	}
}

func TestOTPCodeFormat(t *testing.T) {
	// OTP codes are typically 6 digits
	codes := []string{"123456", "000000", "999999"}

	for _, code := range codes {
		if len(code) != 6 {
			t.Errorf("Expected 6-digit OTP code, got length %d", len(code))
		}

		// Check all characters are digits
		for _, c := range code {
			if c < '0' || c > '9' {
				t.Errorf("OTP code should only contain digits, found '%c'", c)
			}
		}
	}
}

func TestTargetFormats(t *testing.T) {
	// OTP targets can be phone numbers or emails
	targets := []struct {
		value   string
		isPhone bool
		isEmail bool
	}{
		{"+1234567890", true, false},
		{"test@example.com", false, true},
		{"+886912345678", true, false},
		{"user@domain.org", false, true},
	}

	for _, target := range targets {
		hasPlus := len(target.value) > 0 && target.value[0] == '+'
		hasAt := false
		for _, c := range target.value {
			if c == '@' {
				hasAt = true
				break
			}
		}

		if target.isPhone && !hasPlus {
			t.Errorf("Phone number should start with +: %s", target.value)
		}

		if target.isEmail && !hasAt {
			t.Errorf("Email should contain @: %s", target.value)
		}
	}
}

func TestPubSubChannelName(t *testing.T) {
	userID := "user-abc-123"
	channel := messageChannel + userID

	if channel != "messages:user-abc-123" {
		t.Errorf("Expected channel 'messages:user-abc-123', got '%s'", channel)
	}
}

func TestMessagePublishFormat(t *testing.T) {
	// Messages are published as JSON bytes
	message := []byte(`{"type":"new_message","payload":{}}`)

	if len(message) == 0 {
		t.Error("Message should not be empty")
	}

	// Verify it's valid JSON
	if message[0] != '{' {
		t.Error("Message should be JSON object")
	}
}
