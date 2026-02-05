package models

import (
	"time"

	"github.com/google/uuid"
)

// User represents a registered user
type User struct {
	ID           uuid.UUID  `json:"id" db:"id"`
	Phone        *string    `json:"phone,omitempty" db:"phone"`
	Email        *string    `json:"email,omitempty" db:"email"`
	Username     string     `json:"username" db:"username"`
	DisplayName  string     `json:"display_name" db:"display_name"`
	AvatarURL    *string    `json:"avatar_url,omitempty" db:"avatar_url"`
	Bio          *string    `json:"bio,omitempty" db:"bio"`
	Status       UserStatus `json:"status" db:"status"`
	LastSeenAt   *time.Time `json:"last_seen_at,omitempty" db:"last_seen_at"`
	CreatedAt    time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at" db:"updated_at"`
}

type UserStatus string

const (
	UserStatusOnline  UserStatus = "online"
	UserStatusOffline UserStatus = "offline"
	UserStatusAway    UserStatus = "away"
)

// Device represents a user's device for multi-device support
type Device struct {
	ID              uuid.UUID `json:"id" db:"id"`
	UserID          uuid.UUID `json:"user_id" db:"user_id"`
	DeviceID        int       `json:"device_id" db:"device_id"` // Signal device ID
	Name            string    `json:"name" db:"name"`
	Platform        string    `json:"platform" db:"platform"` // ios, android, web, desktop
	PushToken       *string   `json:"-" db:"push_token"`
	LastActiveAt    time.Time `json:"last_active_at" db:"last_active_at"`
	CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

// Contact represents a user's contact
type Contact struct {
	ID          uuid.UUID     `json:"id" db:"id"`
	UserID      uuid.UUID     `json:"user_id" db:"user_id"`
	ContactID   uuid.UUID     `json:"contact_id" db:"contact_id"`
	Nickname    *string       `json:"nickname,omitempty" db:"nickname"`
	IsBlocked   bool          `json:"is_blocked" db:"is_blocked"`
	IsFavorite  bool          `json:"is_favorite" db:"is_favorite"`
	CreatedAt   time.Time     `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time     `json:"updated_at" db:"updated_at"`

	// Populated from join
	Contact     *User         `json:"contact,omitempty" db:"-"`
}

// Conversation represents a chat conversation (1:1 or group)
type Conversation struct {
	ID              uuid.UUID        `json:"id" db:"id"`
	Type            ConversationType `json:"type" db:"type"`
	Name            *string          `json:"name,omitempty" db:"name"`       // For groups
	AvatarURL       *string          `json:"avatar_url,omitempty" db:"avatar_url"` // For groups
	CreatedBy       uuid.UUID        `json:"created_by" db:"created_by"`
	LastMessageAt   *time.Time       `json:"last_message_at,omitempty" db:"last_message_at"`
	CreatedAt       time.Time        `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time        `json:"updated_at" db:"updated_at"`

	// Populated from joins
	Participants    []Participant    `json:"participants,omitempty" db:"-"`
	LastMessage     *Message         `json:"last_message,omitempty" db:"-"`
}

type ConversationType string

const (
	ConversationTypeDirect ConversationType = "direct"
	ConversationTypeGroup  ConversationType = "group"
)

// Participant represents a user in a conversation
type Participant struct {
	ID             uuid.UUID       `json:"id" db:"id"`
	ConversationID uuid.UUID       `json:"conversation_id" db:"conversation_id"`
	UserID         uuid.UUID       `json:"user_id" db:"user_id"`
	Role           ParticipantRole `json:"role" db:"role"`
	JoinedAt       time.Time       `json:"joined_at" db:"joined_at"`
	LeftAt         *time.Time      `json:"left_at,omitempty" db:"left_at"`
	MutedUntil     *time.Time      `json:"muted_until,omitempty" db:"muted_until"`

	// Populated from join
	User           *User           `json:"user,omitempty" db:"-"`
}

type ParticipantRole string

const (
	ParticipantRoleOwner  ParticipantRole = "owner"
	ParticipantRoleAdmin  ParticipantRole = "admin"
	ParticipantRoleMember ParticipantRole = "member"
)

// Message represents an encrypted message
type Message struct {
	ID              uuid.UUID     `json:"id" db:"id"`
	ConversationID  uuid.UUID     `json:"conversation_id" db:"conversation_id"`
	SenderID        uuid.UUID     `json:"sender_id" db:"sender_id"`
	Type            MessageType   `json:"type" db:"type"`
	// Encrypted content - decrypted on client side
	Content         []byte        `json:"content" db:"content"`
	// For stickers, store sticker ID in plaintext for preview
	StickerID       *uuid.UUID    `json:"sticker_id,omitempty" db:"sticker_id"`
	ReplyToID       *uuid.UUID    `json:"reply_to_id,omitempty" db:"reply_to_id"`
	Status          MessageStatus `json:"status" db:"status"`
	CreatedAt       time.Time     `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time     `json:"updated_at" db:"updated_at"`
	DeletedAt       *time.Time    `json:"deleted_at,omitempty" db:"deleted_at"`

	// Populated from joins
	Sender          *User         `json:"sender,omitempty" db:"-"`
	ReplyTo         *Message      `json:"reply_to,omitempty" db:"-"`
	Receipts        []Receipt     `json:"receipts,omitempty" db:"-"`
}

type MessageType string

const (
	MessageTypeText    MessageType = "text"
	MessageTypeImage   MessageType = "image"
	MessageTypeVideo   MessageType = "video"
	MessageTypeAudio   MessageType = "audio"
	MessageTypeFile    MessageType = "file"
	MessageTypeSticker MessageType = "sticker"
	MessageTypeSystem  MessageType = "system"
)

type MessageStatus string

const (
	MessageStatusSending   MessageStatus = "sending"
	MessageStatusSent      MessageStatus = "sent"
	MessageStatusDelivered MessageStatus = "delivered"
	MessageStatusRead      MessageStatus = "read"
	MessageStatusFailed    MessageStatus = "failed"
)

// Receipt represents message delivery/read receipts
type Receipt struct {
	ID        uuid.UUID   `json:"id" db:"id"`
	MessageID uuid.UUID   `json:"message_id" db:"message_id"`
	UserID    uuid.UUID   `json:"user_id" db:"user_id"`
	Type      ReceiptType `json:"type" db:"type"`
	CreatedAt time.Time   `json:"created_at" db:"created_at"`
}

type ReceiptType string

const (
	ReceiptTypeDelivered ReceiptType = "delivered"
	ReceiptTypeRead      ReceiptType = "read"
)

// StickerPack represents a sticker pack
type StickerPack struct {
	ID          uuid.UUID `json:"id" db:"id"`
	Name        string    `json:"name" db:"name"`
	Author      string    `json:"author" db:"author"`
	Description *string   `json:"description,omitempty" db:"description"`
	CoverURL    string    `json:"cover_url" db:"cover_url"`
	IsOfficial  bool      `json:"is_official" db:"is_official"`
	IsAnimated  bool      `json:"is_animated" db:"is_animated"`
	Price       int       `json:"price" db:"price"` // 0 = free
	Downloads   int       `json:"downloads" db:"downloads"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time `json:"updated_at" db:"updated_at"`

	// Populated from joins
	Stickers    []Sticker `json:"stickers,omitempty" db:"-"`
}

// Sticker represents a single sticker in a pack
type Sticker struct {
	ID        uuid.UUID `json:"id" db:"id"`
	PackID    uuid.UUID `json:"pack_id" db:"pack_id"`
	Emoji     string    `json:"emoji" db:"emoji"` // Associated emoji
	ImageURL  string    `json:"image_url" db:"image_url"`
	Position  int       `json:"position" db:"position"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

// UserStickerPack represents a user's downloaded sticker pack
type UserStickerPack struct {
	ID        uuid.UUID `json:"id" db:"id"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	PackID    uuid.UUID `json:"pack_id" db:"pack_id"`
	Position  int       `json:"position" db:"position"` // Order in user's collection
	CreatedAt time.Time `json:"created_at" db:"created_at"`

	// Populated from join
	Pack      *StickerPack `json:"pack,omitempty" db:"-"`
}

// SignalPreKey represents a Signal protocol pre-key
type SignalPreKey struct {
	ID        uuid.UUID `json:"id" db:"id"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	DeviceID  int       `json:"device_id" db:"device_id"`
	KeyID     int       `json:"key_id" db:"key_id"`
	PublicKey []byte    `json:"public_key" db:"public_key"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

// SignalSignedPreKey represents a Signal protocol signed pre-key
type SignalSignedPreKey struct {
	ID         uuid.UUID `json:"id" db:"id"`
	UserID     uuid.UUID `json:"user_id" db:"user_id"`
	DeviceID   int       `json:"device_id" db:"device_id"`
	KeyID      int       `json:"key_id" db:"key_id"`
	PublicKey  []byte    `json:"public_key" db:"public_key"`
	Signature  []byte    `json:"signature" db:"signature"`
	CreatedAt  time.Time `json:"created_at" db:"created_at"`
}

// SignalIdentityKey represents a Signal protocol identity key
type SignalIdentityKey struct {
	ID           uuid.UUID `json:"id" db:"id"`
	UserID       uuid.UUID `json:"user_id" db:"user_id"`
	DeviceID     int       `json:"device_id" db:"device_id"`
	PublicKey    []byte    `json:"public_key" db:"public_key"`
	RegistrationID int     `json:"registration_id" db:"registration_id"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time `json:"updated_at" db:"updated_at"`
}

// OTP represents a one-time password for verification
type OTP struct {
	ID        uuid.UUID `json:"id" db:"id"`
	Target    string    `json:"target" db:"target"` // phone or email
	Type      OTPType   `json:"type" db:"type"`
	Code      string    `json:"-" db:"code"` // Never expose
	ExpiresAt time.Time `json:"expires_at" db:"expires_at"`
	Attempts  int       `json:"attempts" db:"attempts"`
	Verified  bool      `json:"verified" db:"verified"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type OTPType string

const (
	OTPTypePhone OTPType = "phone"
	OTPTypeEmail OTPType = "email"
)

// Session represents an authenticated session
type Session struct {
	ID           uuid.UUID `json:"id" db:"id"`
	UserID       uuid.UUID `json:"user_id" db:"user_id"`
	DeviceID     uuid.UUID `json:"device_id" db:"device_id"`
	Token        string    `json:"-" db:"token"` // Hashed token
	RefreshToken string    `json:"-" db:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at" db:"expires_at"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
	LastUsedAt   time.Time `json:"last_used_at" db:"last_used_at"`
}
