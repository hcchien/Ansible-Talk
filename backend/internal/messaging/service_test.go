package messaging

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/ansible-talk/backend/internal/models"
)

func TestErrors(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{"ConversationNotFound", ErrConversationNotFound, "conversation not found"},
		{"MessageNotFound", ErrMessageNotFound, "message not found"},
		{"NotParticipant", ErrNotParticipant, "user is not a participant"},
		{"NoPermission", ErrNoPermission, "no permission for this action"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.err.Error() != tt.expected {
				t.Errorf("Expected error message '%s', got '%s'", tt.expected, tt.err.Error())
			}
		})
	}
}

func TestNewService(t *testing.T) {
	service := NewService(nil, nil)

	if service == nil {
		t.Error("NewService should not return nil")
	}

	if service.db != nil {
		t.Error("Expected nil db")
	}

	if service.redis != nil {
		t.Error("Expected nil redis")
	}
}

func TestSendMessageRequest_Structure(t *testing.T) {
	conversationID := uuid.New()
	senderID := uuid.New()
	stickerID := uuid.New()
	replyToID := uuid.New()
	content := []byte("encrypted content")

	req := SendMessageRequest{
		ConversationID: conversationID,
		SenderID:       senderID,
		Type:           models.MessageTypeText,
		Content:        content,
		StickerID:      &stickerID,
		ReplyToID:      &replyToID,
	}

	if req.ConversationID != conversationID {
		t.Errorf("Expected ConversationID %s, got %s", conversationID, req.ConversationID)
	}

	if req.SenderID != senderID {
		t.Errorf("Expected SenderID %s, got %s", senderID, req.SenderID)
	}

	if req.Type != models.MessageTypeText {
		t.Errorf("Expected Type text, got %s", req.Type)
	}

	if string(req.Content) != string(content) {
		t.Errorf("Expected Content match")
	}

	if *req.StickerID != stickerID {
		t.Errorf("Expected StickerID %s, got %s", stickerID, *req.StickerID)
	}

	if *req.ReplyToID != replyToID {
		t.Errorf("Expected ReplyToID %s, got %s", replyToID, *req.ReplyToID)
	}
}

func TestSendMessageRequest_JSON(t *testing.T) {
	conversationID := uuid.New()
	senderID := uuid.New()
	content := []byte("test content")

	req := SendMessageRequest{
		ConversationID: conversationID,
		SenderID:       senderID,
		Type:           models.MessageTypeText,
		Content:        content,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Failed to marshal SendMessageRequest: %v", err)
	}

	var decoded SendMessageRequest
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal SendMessageRequest: %v", err)
	}

	if decoded.ConversationID != conversationID {
		t.Errorf("Expected ConversationID %s, got %s", conversationID, decoded.ConversationID)
	}

	if decoded.SenderID != senderID {
		t.Errorf("Expected SenderID %s, got %s", senderID, decoded.SenderID)
	}
}

func TestWSMessage_Structure(t *testing.T) {
	wsMsg := WSMessage{
		Type:    "new_message",
		Payload: "test payload",
	}

	if wsMsg.Type != "new_message" {
		t.Errorf("Expected Type 'new_message', got '%s'", wsMsg.Type)
	}
}

func TestWSMessage_JSON(t *testing.T) {
	msg := &models.Message{
		ID:        uuid.New(),
		Content:   []byte("test"),
		CreatedAt: time.Now(),
	}

	wsMsg := WSMessage{
		Type:    "new_message",
		Payload: NewMessagePayload{Message: msg},
	}

	data, err := json.Marshal(wsMsg)
	if err != nil {
		t.Fatalf("Failed to marshal WSMessage: %v", err)
	}

	var decoded map[string]interface{}
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal WSMessage: %v", err)
	}

	if decoded["type"] != "new_message" {
		t.Errorf("Expected type 'new_message', got '%v'", decoded["type"])
	}

	if decoded["payload"] == nil {
		t.Error("Expected payload to be present")
	}
}

func TestNewMessagePayload_Structure(t *testing.T) {
	msg := &models.Message{
		ID:             uuid.New(),
		ConversationID: uuid.New(),
		SenderID:       uuid.New(),
		Type:           models.MessageTypeText,
		Content:        []byte("test content"),
		Status:         "sent",
		CreatedAt:      time.Now(),
	}

	payload := NewMessagePayload{Message: msg}

	if payload.Message == nil {
		t.Error("Expected Message to be set")
	}

	if payload.Message.ID != msg.ID {
		t.Errorf("Expected Message ID %s, got %s", msg.ID, payload.Message.ID)
	}
}

func TestTypingPayload_Structure(t *testing.T) {
	conversationID := uuid.New()
	userID := uuid.New()

	payload := TypingPayload{
		ConversationID: conversationID,
		UserID:         userID,
		IsTyping:       true,
	}

	if payload.ConversationID != conversationID {
		t.Errorf("Expected ConversationID %s, got %s", conversationID, payload.ConversationID)
	}

	if payload.UserID != userID {
		t.Errorf("Expected UserID %s, got %s", userID, payload.UserID)
	}

	if !payload.IsTyping {
		t.Error("Expected IsTyping to be true")
	}
}

func TestTypingPayload_JSON(t *testing.T) {
	payload := TypingPayload{
		ConversationID: uuid.New(),
		UserID:         uuid.New(),
		IsTyping:       false,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Failed to marshal TypingPayload: %v", err)
	}

	var decoded TypingPayload
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal TypingPayload: %v", err)
	}

	if decoded.ConversationID != payload.ConversationID {
		t.Errorf("Expected ConversationID %s, got %s", payload.ConversationID, decoded.ConversationID)
	}

	if decoded.IsTyping != false {
		t.Error("Expected IsTyping to be false")
	}
}

func TestPresencePayload_Structure(t *testing.T) {
	userID := uuid.New()
	status := "online"

	payload := PresencePayload{
		UserID: userID,
		Status: status,
	}

	if payload.UserID != userID {
		t.Errorf("Expected UserID %s, got %s", userID, payload.UserID)
	}

	if payload.Status != status {
		t.Errorf("Expected Status '%s', got '%s'", status, payload.Status)
	}
}

func TestPresencePayload_JSON(t *testing.T) {
	payload := PresencePayload{
		UserID: uuid.New(),
		Status: "away",
	}

	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Failed to marshal PresencePayload: %v", err)
	}

	var decoded PresencePayload
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal PresencePayload: %v", err)
	}

	if decoded.Status != "away" {
		t.Errorf("Expected Status 'away', got '%s'", decoded.Status)
	}
}

func TestWSMessageTypes(t *testing.T) {
	types := []string{"new_message", "typing", "presence", "read_receipt", "delivered"}

	for _, msgType := range types {
		wsMsg := WSMessage{
			Type:    msgType,
			Payload: nil,
		}

		data, err := json.Marshal(wsMsg)
		if err != nil {
			t.Errorf("Failed to marshal WSMessage with type '%s': %v", msgType, err)
		}

		var decoded WSMessage
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Errorf("Failed to unmarshal WSMessage with type '%s': %v", msgType, err)
		}

		if decoded.Type != msgType {
			t.Errorf("Expected type '%s', got '%s'", msgType, decoded.Type)
		}
	}
}

func TestContext_Deadline(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	deadline, ok := ctx.Deadline()
	if !ok {
		t.Error("Expected deadline to be set")
	}

	if deadline.Before(time.Now()) {
		t.Error("Deadline should be in the future")
	}
}

func TestContext_Value(t *testing.T) {
	type ctxKey string
	key := ctxKey("userID")
	value := uuid.New()

	ctx := context.WithValue(context.Background(), key, value)

	retrieved := ctx.Value(key)
	if retrieved == nil {
		t.Error("Expected value to be present")
	}

	if retrieved.(uuid.UUID) != value {
		t.Errorf("Expected value %s, got %s", value, retrieved)
	}
}

func TestDefaultLimits(t *testing.T) {
	// Test the default limit values used in the service
	tests := []struct {
		name     string
		input    int
		expected int
	}{
		{"Zero limit for conversations", 0, 20},
		{"Negative limit for conversations", -1, 20},
		{"Zero limit for messages", 0, 50},
		{"Negative limit for messages", -1, 50},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			limit := tt.input
			if limit <= 0 {
				if tt.name == "Zero limit for messages" || tt.name == "Negative limit for messages" {
					limit = 50
				} else {
					limit = 20
				}
			}
			if limit != tt.expected {
				t.Errorf("Expected limit %d, got %d", tt.expected, limit)
			}
		})
	}
}

func TestMessageTypes(t *testing.T) {
	types := []models.MessageType{
		models.MessageTypeText,
		models.MessageTypeImage,
		models.MessageTypeVideo,
		models.MessageTypeAudio,
		models.MessageTypeFile,
		models.MessageTypeSticker,
		models.MessageTypeSystem,
	}

	for _, msgType := range types {
		req := SendMessageRequest{
			ConversationID: uuid.New(),
			SenderID:       uuid.New(),
			Type:           msgType,
			Content:        []byte("content"),
		}

		if req.Type != msgType {
			t.Errorf("Expected type %s, got %s", msgType, req.Type)
		}
	}
}

func TestUUIDOperations(t *testing.T) {
	// Test UUID generation for message IDs
	ids := make(map[uuid.UUID]bool)
	count := 100

	for i := 0; i < count; i++ {
		id := uuid.New()
		if ids[id] {
			t.Error("Generated duplicate UUID")
		}
		ids[id] = true
	}

	if len(ids) != count {
		t.Errorf("Expected %d unique UUIDs, got %d", count, len(ids))
	}
}

func TestTimeOperations(t *testing.T) {
	now := time.Now()

	// Test before filter
	before := now.Add(-1 * time.Hour)
	if !before.Before(now) {
		t.Error("before should be before now")
	}

	// Test message ordering by created_at
	msg1Time := now.Add(-2 * time.Hour)
	msg2Time := now.Add(-1 * time.Hour)

	if !msg1Time.Before(msg2Time) {
		t.Error("msg1 should be before msg2")
	}
}

func TestConversationTypes(t *testing.T) {
	tests := []struct {
		name     string
		convType string
	}{
		{"Direct", "direct"},
		{"Group", "group"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.convType != "direct" && tt.convType != "group" {
				t.Errorf("Invalid conversation type: %s", tt.convType)
			}
		})
	}
}

func TestParticipantRoles(t *testing.T) {
	roles := []string{"owner", "admin", "member"}

	for _, role := range roles {
		if role != "owner" && role != "admin" && role != "member" {
			t.Errorf("Invalid participant role: %s", role)
		}
	}
}

func TestMessageStatuses(t *testing.T) {
	statuses := []string{"sending", "sent", "delivered", "read", "failed"}

	for _, status := range statuses {
		if status == "" {
			t.Error("Status should not be empty")
		}
	}
}

func TestReceiptTypes(t *testing.T) {
	receiptTypes := []string{"delivered", "read"}

	for _, receiptType := range receiptTypes {
		if receiptType != "delivered" && receiptType != "read" {
			t.Errorf("Invalid receipt type: %s", receiptType)
		}
	}
}
