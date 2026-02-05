package config

import (
	"os"
	"strconv"
	"time"
)

// Config holds all configuration for the application
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	MinIO    MinIOConfig
	JWT      JWTConfig
	OTP      OTPConfig
	SMS      SMSConfig
	Email    EmailConfig
}

type ServerConfig struct {
	Host         string
	Port         int
	Environment  string
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
}

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	Database string
	SSLMode  string
	MaxConns int
}

type RedisConfig struct {
	Host     string
	Port     int
	Password string
	DB       int
}

type MinIOConfig struct {
	Endpoint        string
	AccessKeyID     string
	SecretAccessKey string
	UseSSL          bool
	StickersBucket  string
	AvatarsBucket   string
	AttachmentsBucket string
	PublicURL       string
}

type JWTConfig struct {
	Secret           string
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	Issuer           string
}

type OTPConfig struct {
	Length     int
	TTL        time.Duration
	MaxAttempts int
}

type SMSConfig struct {
	Provider   string // twilio, vonage, etc.
	AccountSID string
	AuthToken  string
	FromNumber string
}

type EmailConfig struct {
	Provider   string // sendgrid, ses, smtp
	APIKey     string
	FromEmail  string
	FromName   string
	SMTPHost   string
	SMTPPort   int
	SMTPUser   string
	SMTPPass   string
}

// Load loads configuration from environment variables
func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Host:         getEnv("SERVER_HOST", "0.0.0.0"),
			Port:         getEnvInt("SERVER_PORT", 8080),
			Environment:  getEnv("ENVIRONMENT", "development"),
			ReadTimeout:  getEnvDuration("SERVER_READ_TIMEOUT", 30*time.Second),
			WriteTimeout: getEnvDuration("SERVER_WRITE_TIMEOUT", 30*time.Second),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnvInt("DB_PORT", 5432),
			User:     getEnv("DB_USER", "ansible"),
			Password: getEnv("DB_PASSWORD", "ansible_secret"),
			Database: getEnv("DB_NAME", "ansible_talk"),
			SSLMode:  getEnv("DB_SSL_MODE", "disable"),
			MaxConns: getEnvInt("DB_MAX_CONNS", 25),
		},
		Redis: RedisConfig{
			Host:     getEnv("REDIS_HOST", "localhost"),
			Port:     getEnvInt("REDIS_PORT", 6379),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
		MinIO: MinIOConfig{
			Endpoint:        getEnv("MINIO_ENDPOINT", "localhost:9000"),
			AccessKeyID:     getEnv("MINIO_ACCESS_KEY", "minioadmin"),
			SecretAccessKey: getEnv("MINIO_SECRET_KEY", "minioadmin"),
			UseSSL:          getEnvBool("MINIO_USE_SSL", false),
			StickersBucket:  getEnv("MINIO_STICKERS_BUCKET", "stickers"),
			AvatarsBucket:   getEnv("MINIO_AVATARS_BUCKET", "avatars"),
			AttachmentsBucket: getEnv("MINIO_ATTACHMENTS_BUCKET", "attachments"),
			PublicURL:       getEnv("MINIO_PUBLIC_URL", "http://localhost:9000"),
		},
		JWT: JWTConfig{
			Secret:          getEnv("JWT_SECRET", "your-super-secret-key-change-in-production"),
			AccessTokenTTL:  getEnvDuration("JWT_ACCESS_TOKEN_TTL", 15*time.Minute),
			RefreshTokenTTL: getEnvDuration("JWT_REFRESH_TOKEN_TTL", 7*24*time.Hour),
			Issuer:          getEnv("JWT_ISSUER", "ansible-talk"),
		},
		OTP: OTPConfig{
			Length:      getEnvInt("OTP_LENGTH", 6),
			TTL:         getEnvDuration("OTP_TTL", 5*time.Minute),
			MaxAttempts: getEnvInt("OTP_MAX_ATTEMPTS", 3),
		},
		SMS: SMSConfig{
			Provider:   getEnv("SMS_PROVIDER", "twilio"),
			AccountSID: getEnv("TWILIO_ACCOUNT_SID", ""),
			AuthToken:  getEnv("TWILIO_AUTH_TOKEN", ""),
			FromNumber: getEnv("TWILIO_FROM_NUMBER", ""),
		},
		Email: EmailConfig{
			Provider:  getEnv("EMAIL_PROVIDER", "smtp"),
			APIKey:    getEnv("SENDGRID_API_KEY", ""),
			FromEmail: getEnv("EMAIL_FROM", "noreply@ansible-talk.com"),
			FromName:  getEnv("EMAIL_FROM_NAME", "Ansible Talk"),
			SMTPHost:  getEnv("SMTP_HOST", "localhost"),
			SMTPPort:  getEnvInt("SMTP_PORT", 587),
			SMTPUser:  getEnv("SMTP_USER", ""),
			SMTPPass:  getEnv("SMTP_PASS", ""),
		},
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolValue, err := strconv.ParseBool(value); err == nil {
			return boolValue
		}
	}
	return defaultValue
}

func getEnvDuration(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}
