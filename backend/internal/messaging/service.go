package messaging

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/storage"
)

var (
	ErrConversationNotFound = errors.New("conversation not found")
	ErrMessageNotFound      = errors.New("message not found")
	ErrNotParticipant       = errors.New("user is not a participant")
	ErrNoPermission         = errors.New("no permission for this action")
)

// Service handles messaging operations
type Service struct {
	db    *storage.PostgresDB
	redis *storage.RedisClient
}

// NewService creates a new messaging service
func NewService(db *storage.PostgresDB, redis *storage.RedisClient) *Service {
	return &Service{
		db:    db,
		redis: redis,
	}
}

// CreateDirectConversation creates or gets a direct conversation between two users
func (s *Service) CreateDirectConversation(ctx context.Context, userID1, userID2 uuid.UUID) (*models.Conversation, error) {
	// Check if conversation already exists
	var conversationID uuid.UUID
	err := s.db.Pool.QueryRow(ctx, `
		SELECT c.id FROM conversations c
		JOIN participants p1 ON c.id = p1.conversation_id AND p1.user_id = $1
		JOIN participants p2 ON c.id = p2.conversation_id AND p2.user_id = $2
		WHERE c.type = 'direct'
	`, userID1, userID2).Scan(&conversationID)

	if err == nil {
		return s.GetConversation(ctx, conversationID, userID1)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("failed to check existing conversation: %w", err)
	}

	// Create new conversation
	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var conv models.Conversation
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, created_by)
		VALUES ('direct', $1)
		RETURNING id, type, name, avatar_url, created_by, last_message_at, created_at, updated_at
	`, userID1).Scan(
		&conv.ID, &conv.Type, &conv.Name, &conv.AvatarURL, &conv.CreatedBy,
		&conv.LastMessageAt, &conv.CreatedAt, &conv.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create conversation: %w", err)
	}

	// Add participants
	for _, userID := range []uuid.UUID{userID1, userID2} {
		_, err = tx.Exec(ctx, `
			INSERT INTO participants (conversation_id, user_id, role)
			VALUES ($1, $2, 'member')
		`, conv.ID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to add participant: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return s.GetConversation(ctx, conv.ID, userID1)
}

// CreateGroupConversation creates a new group conversation
func (s *Service) CreateGroupConversation(ctx context.Context, creatorID uuid.UUID, name string, memberIDs []uuid.UUID) (*models.Conversation, error) {
	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var conv models.Conversation
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, name, created_by)
		VALUES ('group', $1, $2)
		RETURNING id, type, name, avatar_url, created_by, last_message_at, created_at, updated_at
	`, name, creatorID).Scan(
		&conv.ID, &conv.Type, &conv.Name, &conv.AvatarURL, &conv.CreatedBy,
		&conv.LastMessageAt, &conv.CreatedAt, &conv.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create conversation: %w", err)
	}

	// Add creator as owner
	_, err = tx.Exec(ctx, `
		INSERT INTO participants (conversation_id, user_id, role)
		VALUES ($1, $2, 'owner')
	`, conv.ID, creatorID)
	if err != nil {
		return nil, fmt.Errorf("failed to add creator: %w", err)
	}

	// Add other members
	for _, memberID := range memberIDs {
		if memberID != creatorID {
			_, err = tx.Exec(ctx, `
				INSERT INTO participants (conversation_id, user_id, role)
				VALUES ($1, $2, 'member')
			`, conv.ID, memberID)
			if err != nil {
				return nil, fmt.Errorf("failed to add member: %w", err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return s.GetConversation(ctx, conv.ID, creatorID)
}

// GetConversation retrieves a conversation with participants
func (s *Service) GetConversation(ctx context.Context, conversationID, userID uuid.UUID) (*models.Conversation, error) {
	var conv models.Conversation
	err := s.db.Pool.QueryRow(ctx, `
		SELECT c.id, c.type, c.name, c.avatar_url, c.created_by, c.last_message_at, c.created_at, c.updated_at
		FROM conversations c
		JOIN participants p ON c.id = p.conversation_id
		WHERE c.id = $1 AND p.user_id = $2 AND p.left_at IS NULL
	`, conversationID, userID).Scan(
		&conv.ID, &conv.Type, &conv.Name, &conv.AvatarURL, &conv.CreatedBy,
		&conv.LastMessageAt, &conv.CreatedAt, &conv.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrConversationNotFound
		}
		return nil, fmt.Errorf("failed to get conversation: %w", err)
	}

	// Get participants
	rows, err := s.db.Pool.Query(ctx, `
		SELECT p.id, p.conversation_id, p.user_id, p.role, p.joined_at, p.left_at, p.muted_until,
		       u.id, u.username, u.display_name, u.avatar_url, u.status, u.last_seen_at
		FROM participants p
		JOIN users u ON p.user_id = u.id
		WHERE p.conversation_id = $1 AND p.left_at IS NULL
	`, conversationID)
	if err != nil {
		return nil, fmt.Errorf("failed to get participants: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var p models.Participant
		p.User = &models.User{}
		err := rows.Scan(
			&p.ID, &p.ConversationID, &p.UserID, &p.Role, &p.JoinedAt, &p.LeftAt, &p.MutedUntil,
			&p.User.ID, &p.User.Username, &p.User.DisplayName, &p.User.AvatarURL,
			&p.User.Status, &p.User.LastSeenAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan participant: %w", err)
		}
		conv.Participants = append(conv.Participants, p)
	}

	return &conv, nil
}

// GetUserConversations retrieves all conversations for a user
func (s *Service) GetUserConversations(ctx context.Context, userID uuid.UUID, limit, offset int) ([]models.Conversation, error) {
	if limit <= 0 {
		limit = 20
	}

	rows, err := s.db.Pool.Query(ctx, `
		SELECT c.id, c.type, c.name, c.avatar_url, c.created_by, c.last_message_at, c.created_at, c.updated_at
		FROM conversations c
		JOIN participants p ON c.id = p.conversation_id
		WHERE p.user_id = $1 AND p.left_at IS NULL
		ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to get conversations: %w", err)
	}
	defer rows.Close()

	var conversations []models.Conversation
	for rows.Next() {
		var conv models.Conversation
		err := rows.Scan(
			&conv.ID, &conv.Type, &conv.Name, &conv.AvatarURL, &conv.CreatedBy,
			&conv.LastMessageAt, &conv.CreatedAt, &conv.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan conversation: %w", err)
		}
		conversations = append(conversations, conv)
	}

	// Fetch participants for each conversation
	for i := range conversations {
		conv, err := s.GetConversation(ctx, conversations[i].ID, userID)
		if err == nil {
			conversations[i].Participants = conv.Participants
		}
	}

	return conversations, nil
}

// SendMessageRequest represents a request to send a message
type SendMessageRequest struct {
	ConversationID uuid.UUID         `json:"conversation_id"`
	SenderID       uuid.UUID         `json:"sender_id"`
	Type           models.MessageType `json:"type"`
	Content        []byte            `json:"content"` // Encrypted content
	StickerID      *uuid.UUID        `json:"sticker_id,omitempty"`
	ReplyToID      *uuid.UUID        `json:"reply_to_id,omitempty"`
}

// SendMessage sends a message to a conversation
func (s *Service) SendMessage(ctx context.Context, req SendMessageRequest) (*models.Message, error) {
	// Verify sender is a participant
	var isParticipant bool
	err := s.db.Pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM participants
			WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
		)
	`, req.ConversationID, req.SenderID).Scan(&isParticipant)
	if err != nil {
		return nil, fmt.Errorf("failed to verify participant: %w", err)
	}
	if !isParticipant {
		return nil, ErrNotParticipant
	}

	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Create message
	var msg models.Message
	err = tx.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, content, sticker_id, reply_to_id, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'sent')
		RETURNING id, conversation_id, sender_id, type, content, sticker_id, reply_to_id, status, created_at, updated_at
	`, req.ConversationID, req.SenderID, req.Type, req.Content, req.StickerID, req.ReplyToID).Scan(
		&msg.ID, &msg.ConversationID, &msg.SenderID, &msg.Type, &msg.Content,
		&msg.StickerID, &msg.ReplyToID, &msg.Status, &msg.CreatedAt, &msg.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create message: %w", err)
	}

	// Update conversation's last message time
	_, err = tx.Exec(ctx, `
		UPDATE conversations SET last_message_at = $1 WHERE id = $2
	`, msg.CreatedAt, req.ConversationID)
	if err != nil {
		return nil, fmt.Errorf("failed to update conversation: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Get sender info
	msg.Sender = &models.User{}
	_ = s.db.Pool.QueryRow(ctx, `
		SELECT id, username, display_name, avatar_url FROM users WHERE id = $1
	`, req.SenderID).Scan(&msg.Sender.ID, &msg.Sender.Username, &msg.Sender.DisplayName, &msg.Sender.AvatarURL)

	// Notify other participants via Redis pub/sub
	s.notifyParticipants(ctx, req.ConversationID, req.SenderID, &msg)

	return &msg, nil
}

// GetMessages retrieves messages from a conversation
func (s *Service) GetMessages(ctx context.Context, conversationID, userID uuid.UUID, limit, offset int, before *time.Time) ([]models.Message, error) {
	// Verify user is a participant
	var isParticipant bool
	err := s.db.Pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM participants
			WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
		)
	`, conversationID, userID).Scan(&isParticipant)
	if err != nil {
		return nil, fmt.Errorf("failed to verify participant: %w", err)
	}
	if !isParticipant {
		return nil, ErrNotParticipant
	}

	if limit <= 0 {
		limit = 50
	}

	query := `
		SELECT m.id, m.conversation_id, m.sender_id, m.type, m.content, m.sticker_id, m.reply_to_id,
		       m.status, m.created_at, m.updated_at, m.deleted_at,
		       u.id, u.username, u.display_name, u.avatar_url
		FROM messages m
		JOIN users u ON m.sender_id = u.id
		WHERE m.conversation_id = $1 AND m.deleted_at IS NULL
	`
	args := []interface{}{conversationID}

	if before != nil {
		query += " AND m.created_at < $2"
		args = append(args, before)
	}

	query += fmt.Sprintf(" ORDER BY m.created_at DESC LIMIT %d OFFSET %d", limit, offset)

	rows, err := s.db.Pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get messages: %w", err)
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var msg models.Message
		msg.Sender = &models.User{}
		err := rows.Scan(
			&msg.ID, &msg.ConversationID, &msg.SenderID, &msg.Type, &msg.Content,
			&msg.StickerID, &msg.ReplyToID, &msg.Status, &msg.CreatedAt, &msg.UpdatedAt, &msg.DeletedAt,
			&msg.Sender.ID, &msg.Sender.Username, &msg.Sender.DisplayName, &msg.Sender.AvatarURL,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan message: %w", err)
		}
		messages = append(messages, msg)
	}

	return messages, nil
}

// MarkAsDelivered marks a message as delivered
func (s *Service) MarkAsDelivered(ctx context.Context, messageID, userID uuid.UUID) error {
	_, err := s.db.Pool.Exec(ctx, `
		INSERT INTO receipts (message_id, user_id, type)
		VALUES ($1, $2, 'delivered')
		ON CONFLICT (message_id, user_id, type) DO NOTHING
	`, messageID, userID)
	return err
}

// MarkAsRead marks a message as read
func (s *Service) MarkAsRead(ctx context.Context, messageID, userID uuid.UUID) error {
	_, err := s.db.Pool.Exec(ctx, `
		INSERT INTO receipts (message_id, user_id, type)
		VALUES ($1, $2, 'read')
		ON CONFLICT (message_id, user_id, type) DO NOTHING
	`, messageID, userID)
	return err
}

// DeleteMessage soft-deletes a message
func (s *Service) DeleteMessage(ctx context.Context, messageID, userID uuid.UUID) error {
	result, err := s.db.Pool.Exec(ctx, `
		UPDATE messages SET deleted_at = NOW()
		WHERE id = $1 AND sender_id = $2 AND deleted_at IS NULL
	`, messageID, userID)
	if err != nil {
		return fmt.Errorf("failed to delete message: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrMessageNotFound
	}

	return nil
}

// WebSocket message types
type WSMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

type NewMessagePayload struct {
	Message *models.Message `json:"message"`
}

type TypingPayload struct {
	ConversationID uuid.UUID `json:"conversation_id"`
	UserID         uuid.UUID `json:"user_id"`
	IsTyping       bool      `json:"is_typing"`
}

type PresencePayload struct {
	UserID uuid.UUID `json:"user_id"`
	Status string    `json:"status"`
}

// notifyParticipants sends a message notification to all participants except sender
func (s *Service) notifyParticipants(ctx context.Context, conversationID, senderID uuid.UUID, msg *models.Message) {
	// Get all participant IDs except sender
	rows, err := s.db.Pool.Query(ctx, `
		SELECT user_id FROM participants
		WHERE conversation_id = $1 AND user_id != $2 AND left_at IS NULL
	`, conversationID, senderID)
	if err != nil {
		return
	}
	defer rows.Close()

	wsMsg := WSMessage{
		Type:    "new_message",
		Payload: NewMessagePayload{Message: msg},
	}
	msgBytes, _ := json.Marshal(wsMsg)

	for rows.Next() {
		var userID uuid.UUID
		if err := rows.Scan(&userID); err != nil {
			continue
		}
		// Publish to user's Redis channel
		_ = s.redis.PublishMessage(ctx, userID.String(), msgBytes)
	}
}

// BroadcastTyping broadcasts typing indicator
func (s *Service) BroadcastTyping(ctx context.Context, conversationID, userID uuid.UUID, isTyping bool) error {
	// Get all participant IDs except the typing user
	rows, err := s.db.Pool.Query(ctx, `
		SELECT user_id FROM participants
		WHERE conversation_id = $1 AND user_id != $2 AND left_at IS NULL
	`, conversationID, userID)
	if err != nil {
		return err
	}
	defer rows.Close()

	wsMsg := WSMessage{
		Type: "typing",
		Payload: TypingPayload{
			ConversationID: conversationID,
			UserID:         userID,
			IsTyping:       isTyping,
		},
	}
	msgBytes, _ := json.Marshal(wsMsg)

	for rows.Next() {
		var participantID uuid.UUID
		if err := rows.Scan(&participantID); err != nil {
			continue
		}
		_ = s.redis.PublishMessage(ctx, participantID.String(), msgBytes)
	}

	return nil
}

// UpdatePresence updates user presence status
func (s *Service) UpdatePresence(ctx context.Context, userID uuid.UUID, status string) error {
	// Update in database
	_, err := s.db.Pool.Exec(ctx, `
		UPDATE users SET status = $1, last_seen_at = NOW() WHERE id = $2
	`, status, userID)
	if err != nil {
		return err
	}

	// Update in Redis with TTL
	_ = s.redis.SetUserPresence(ctx, userID.String(), status, 5*time.Minute)

	return nil
}
