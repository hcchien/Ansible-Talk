package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/ansible-talk/backend/internal/config"
)

// RedisClient wraps the redis client
type RedisClient struct {
	Client *redis.Client
}

// NewRedisClient creates a new Redis client
func NewRedisClient(cfg config.RedisConfig) (*RedisClient, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		Password: cfg.Password,
		DB:       cfg.DB,
	})

	// Verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to redis: %w", err)
	}

	return &RedisClient{Client: client}, nil
}

// Close closes the Redis client
func (r *RedisClient) Close() error {
	return r.Client.Close()
}

// Health checks Redis health
func (r *RedisClient) Health(ctx context.Context) error {
	return r.Client.Ping(ctx).Err()
}

// Session management keys
const (
	sessionKeyPrefix   = "session:"
	userSessionsPrefix = "user_sessions:"
	presenceKeyPrefix  = "presence:"
	otpKeyPrefix       = "otp:"
)

// SetSession stores a session token in Redis
func (r *RedisClient) SetSession(ctx context.Context, sessionID, userID string, ttl time.Duration) error {
	pipe := r.Client.Pipeline()

	// Store session
	pipe.Set(ctx, sessionKeyPrefix+sessionID, userID, ttl)

	// Add to user's sessions set
	pipe.SAdd(ctx, userSessionsPrefix+userID, sessionID)
	pipe.Expire(ctx, userSessionsPrefix+userID, ttl)

	_, err := pipe.Exec(ctx)
	return err
}

// GetSession retrieves a session from Redis
func (r *RedisClient) GetSession(ctx context.Context, sessionID string) (string, error) {
	return r.Client.Get(ctx, sessionKeyPrefix+sessionID).Result()
}

// DeleteSession removes a session from Redis
func (r *RedisClient) DeleteSession(ctx context.Context, sessionID, userID string) error {
	pipe := r.Client.Pipeline()
	pipe.Del(ctx, sessionKeyPrefix+sessionID)
	pipe.SRem(ctx, userSessionsPrefix+userID, sessionID)
	_, err := pipe.Exec(ctx)
	return err
}

// DeleteAllUserSessions removes all sessions for a user
func (r *RedisClient) DeleteAllUserSessions(ctx context.Context, userID string) error {
	// Get all session IDs for user
	sessionIDs, err := r.Client.SMembers(ctx, userSessionsPrefix+userID).Result()
	if err != nil {
		return err
	}

	if len(sessionIDs) == 0 {
		return nil
	}

	// Delete all sessions
	pipe := r.Client.Pipeline()
	for _, sessionID := range sessionIDs {
		pipe.Del(ctx, sessionKeyPrefix+sessionID)
	}
	pipe.Del(ctx, userSessionsPrefix+userID)

	_, err = pipe.Exec(ctx)
	return err
}

// SetUserPresence sets user online status
func (r *RedisClient) SetUserPresence(ctx context.Context, userID string, status string, ttl time.Duration) error {
	return r.Client.Set(ctx, presenceKeyPrefix+userID, status, ttl).Err()
}

// GetUserPresence gets user online status
func (r *RedisClient) GetUserPresence(ctx context.Context, userID string) (string, error) {
	result, err := r.Client.Get(ctx, presenceKeyPrefix+userID).Result()
	if err == redis.Nil {
		return "offline", nil
	}
	return result, err
}

// SetOTP stores an OTP code
func (r *RedisClient) SetOTP(ctx context.Context, target, code string, ttl time.Duration) error {
	return r.Client.Set(ctx, otpKeyPrefix+target, code, ttl).Err()
}

// GetOTP retrieves an OTP code
func (r *RedisClient) GetOTP(ctx context.Context, target string) (string, error) {
	return r.Client.Get(ctx, otpKeyPrefix+target).Result()
}

// DeleteOTP removes an OTP code
func (r *RedisClient) DeleteOTP(ctx context.Context, target string) error {
	return r.Client.Del(ctx, otpKeyPrefix+target).Err()
}

// PubSub for real-time messaging
const (
	messageChannel = "messages:"
)

// PublishMessage publishes a message to a user's channel
func (r *RedisClient) PublishMessage(ctx context.Context, userID string, message []byte) error {
	return r.Client.Publish(ctx, messageChannel+userID, message).Err()
}

// SubscribeMessages subscribes to a user's message channel
func (r *RedisClient) SubscribeMessages(ctx context.Context, userID string) *redis.PubSub {
	return r.Client.Subscribe(ctx, messageChannel+userID)
}
