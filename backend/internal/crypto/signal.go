package crypto

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/storage"
)

var (
	ErrNoPreKeysAvailable = errors.New("no pre-keys available for user")
	ErrIdentityKeyNotFound = errors.New("identity key not found")
)

// Service handles Signal protocol key management
type Service struct {
	db *storage.PostgresDB
}

// NewService creates a new crypto service
func NewService(db *storage.PostgresDB) *Service {
	return &Service{db: db}
}

// KeyBundle represents a user's public key bundle for session establishment
type KeyBundle struct {
	UserID          uuid.UUID `json:"user_id"`
	DeviceID        int       `json:"device_id"`
	RegistrationID  int       `json:"registration_id"`
	IdentityKey     []byte    `json:"identity_key"`
	SignedPreKey    SignedPreKey `json:"signed_pre_key"`
	PreKey          *PreKey   `json:"pre_key,omitempty"` // One-time pre-key (optional)
}

// SignedPreKey represents a signed pre-key
type SignedPreKey struct {
	KeyID     int    `json:"key_id"`
	PublicKey []byte `json:"public_key"`
	Signature []byte `json:"signature"`
}

// PreKey represents a one-time pre-key
type PreKey struct {
	KeyID     int    `json:"key_id"`
	PublicKey []byte `json:"public_key"`
}

// RegisterKeysRequest represents a request to register Signal keys
type RegisterKeysRequest struct {
	UserID          uuid.UUID `json:"user_id"`
	DeviceID        int       `json:"device_id"`
	RegistrationID  int       `json:"registration_id"`
	IdentityKey     []byte    `json:"identity_key"`
	SignedPreKey    SignedPreKey `json:"signed_pre_key"`
	PreKeys         []PreKey  `json:"pre_keys"`
}

// RegisterKeys registers a user's Signal protocol keys
func (s *Service) RegisterKeys(ctx context.Context, req RegisterKeysRequest) error {
	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Store identity key
	_, err = tx.Exec(ctx, `
		INSERT INTO signal_identity_keys (user_id, device_id, public_key, registration_id)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, device_id)
		DO UPDATE SET public_key = $3, registration_id = $4, updated_at = NOW()
	`, req.UserID, req.DeviceID, req.IdentityKey, req.RegistrationID)
	if err != nil {
		return fmt.Errorf("failed to store identity key: %w", err)
	}

	// Store signed pre-key
	_, err = tx.Exec(ctx, `
		INSERT INTO signal_signed_prekeys (user_id, device_id, key_id, public_key, signature)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, device_id, key_id)
		DO UPDATE SET public_key = $4, signature = $5
	`, req.UserID, req.DeviceID, req.SignedPreKey.KeyID, req.SignedPreKey.PublicKey, req.SignedPreKey.Signature)
	if err != nil {
		return fmt.Errorf("failed to store signed pre-key: %w", err)
	}

	// Store one-time pre-keys
	for _, preKey := range req.PreKeys {
		_, err = tx.Exec(ctx, `
			INSERT INTO signal_prekeys (user_id, device_id, key_id, public_key)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (user_id, device_id, key_id) DO NOTHING
		`, req.UserID, req.DeviceID, preKey.KeyID, preKey.PublicKey)
		if err != nil {
			return fmt.Errorf("failed to store pre-key: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// GetKeyBundle retrieves a user's key bundle for session establishment
func (s *Service) GetKeyBundle(ctx context.Context, userID uuid.UUID, deviceID int) (*KeyBundle, error) {
	bundle := &KeyBundle{
		UserID:   userID,
		DeviceID: deviceID,
	}

	// Get identity key
	var identity models.SignalIdentityKey
	err := s.db.Pool.QueryRow(ctx, `
		SELECT public_key, registration_id
		FROM signal_identity_keys
		WHERE user_id = $1 AND device_id = $2
	`, userID, deviceID).Scan(&identity.PublicKey, &identity.RegistrationID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrIdentityKeyNotFound
		}
		return nil, fmt.Errorf("failed to get identity key: %w", err)
	}
	bundle.IdentityKey = identity.PublicKey
	bundle.RegistrationID = identity.RegistrationID

	// Get signed pre-key (latest)
	err = s.db.Pool.QueryRow(ctx, `
		SELECT key_id, public_key, signature
		FROM signal_signed_prekeys
		WHERE user_id = $1 AND device_id = $2
		ORDER BY created_at DESC
		LIMIT 1
	`, userID, deviceID).Scan(&bundle.SignedPreKey.KeyID, &bundle.SignedPreKey.PublicKey, &bundle.SignedPreKey.Signature)
	if err != nil {
		return nil, fmt.Errorf("failed to get signed pre-key: %w", err)
	}

	// Get one-time pre-key (and delete it - one-time use)
	var preKey PreKey
	err = s.db.Pool.QueryRow(ctx, `
		DELETE FROM signal_prekeys
		WHERE id = (
			SELECT id FROM signal_prekeys
			WHERE user_id = $1 AND device_id = $2
			ORDER BY created_at ASC
			LIMIT 1
		)
		RETURNING key_id, public_key
	`, userID, deviceID).Scan(&preKey.KeyID, &preKey.PublicKey)
	if err == nil {
		bundle.PreKey = &preKey
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("failed to get pre-key: %w", err)
	}

	return bundle, nil
}

// GetPreKeyCount returns the number of available pre-keys for a user's device
func (s *Service) GetPreKeyCount(ctx context.Context, userID uuid.UUID, deviceID int) (int, error) {
	var count int
	err := s.db.Pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM signal_prekeys
		WHERE user_id = $1 AND device_id = $2
	`, userID, deviceID).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("failed to count pre-keys: %w", err)
	}
	return count, nil
}

// RefreshPreKeys allows uploading additional pre-keys
func (s *Service) RefreshPreKeys(ctx context.Context, userID uuid.UUID, deviceID int, preKeys []PreKey) error {
	for _, preKey := range preKeys {
		_, err := s.db.Pool.Exec(ctx, `
			INSERT INTO signal_prekeys (user_id, device_id, key_id, public_key)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (user_id, device_id, key_id) DO NOTHING
		`, userID, deviceID, preKey.KeyID, preKey.PublicKey)
		if err != nil {
			return fmt.Errorf("failed to store pre-key: %w", err)
		}
	}
	return nil
}

// UpdateSignedPreKey updates a user's signed pre-key (for key rotation)
func (s *Service) UpdateSignedPreKey(ctx context.Context, userID uuid.UUID, deviceID int, signedPreKey SignedPreKey) error {
	_, err := s.db.Pool.Exec(ctx, `
		INSERT INTO signal_signed_prekeys (user_id, device_id, key_id, public_key, signature)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, device_id, key_id)
		DO UPDATE SET public_key = $4, signature = $5, updated_at = NOW()
	`, userID, deviceID, signedPreKey.KeyID, signedPreKey.PublicKey, signedPreKey.Signature)
	if err != nil {
		return fmt.Errorf("failed to update signed pre-key: %w", err)
	}
	return nil
}

// GetUserDevices returns all devices for a user with their key info
func (s *Service) GetUserDevices(ctx context.Context, userID uuid.UUID) ([]int, error) {
	rows, err := s.db.Pool.Query(ctx, `
		SELECT device_id FROM signal_identity_keys WHERE user_id = $1
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user devices: %w", err)
	}
	defer rows.Close()

	var devices []int
	for rows.Next() {
		var deviceID int
		if err := rows.Scan(&deviceID); err != nil {
			return nil, fmt.Errorf("failed to scan device: %w", err)
		}
		devices = append(devices, deviceID)
	}

	return devices, nil
}

// GenerateRegistrationID generates a random registration ID for Signal protocol
func GenerateRegistrationID() (int, error) {
	b := make([]byte, 2)
	if _, err := rand.Read(b); err != nil {
		return 0, err
	}
	// Registration ID is 14 bits (0-16383)
	return int(b[0])<<8 | int(b[1])&0x3FFF, nil
}
