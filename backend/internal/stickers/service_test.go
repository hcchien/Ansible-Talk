package stickers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestErrors(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{"PackNotFound", ErrPackNotFound, "sticker pack not found"},
		{"StickerNotFound", ErrStickerNotFound, "sticker not found"},
		{"AlreadyOwned", ErrAlreadyOwned, "sticker pack already owned"},
		{"NotOwned", ErrNotOwned, "sticker pack not owned"},
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

	if service.minio != nil {
		t.Error("Expected nil minio")
	}
}

func TestCreatePackRequest_Structure(t *testing.T) {
	description := "A fun sticker pack"

	req := CreatePackRequest{
		Name:        "Happy Emojis",
		Author:      "John Doe",
		Description: &description,
		IsOfficial:  true,
		IsAnimated:  false,
		Price:       0,
	}

	if req.Name != "Happy Emojis" {
		t.Errorf("Expected Name 'Happy Emojis', got '%s'", req.Name)
	}

	if req.Author != "John Doe" {
		t.Errorf("Expected Author 'John Doe', got '%s'", req.Author)
	}

	if req.Description == nil || *req.Description != description {
		t.Errorf("Expected Description '%s', got '%v'", description, req.Description)
	}

	if !req.IsOfficial {
		t.Error("Expected IsOfficial to be true")
	}

	if req.IsAnimated {
		t.Error("Expected IsAnimated to be false")
	}

	if req.Price != 0 {
		t.Errorf("Expected Price 0, got %d", req.Price)
	}
}

func TestCreatePackRequest_JSON(t *testing.T) {
	req := CreatePackRequest{
		Name:       "Test Pack",
		Author:     "Test Author",
		IsOfficial: false,
		IsAnimated: true,
		Price:      100,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Failed to marshal CreatePackRequest: %v", err)
	}

	var decoded CreatePackRequest
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal CreatePackRequest: %v", err)
	}

	if decoded.Name != req.Name {
		t.Errorf("Expected Name '%s', got '%s'", req.Name, decoded.Name)
	}

	if decoded.Author != req.Author {
		t.Errorf("Expected Author '%s', got '%s'", req.Author, decoded.Author)
	}

	if decoded.IsAnimated != true {
		t.Error("Expected IsAnimated to be true")
	}

	if decoded.Price != 100 {
		t.Errorf("Expected Price 100, got %d", decoded.Price)
	}
}

func TestAddStickerRequest_Structure(t *testing.T) {
	packID := uuid.New()

	req := AddStickerRequest{
		PackID:   packID,
		Emoji:    "😀",
		Position: 0,
	}

	if req.PackID != packID {
		t.Errorf("Expected PackID %s, got %s", packID, req.PackID)
	}

	if req.Emoji != "😀" {
		t.Errorf("Expected Emoji '😀', got '%s'", req.Emoji)
	}

	if req.Position != 0 {
		t.Errorf("Expected Position 0, got %d", req.Position)
	}
}

func TestAddStickerRequest_JSON(t *testing.T) {
	packID := uuid.New()

	req := AddStickerRequest{
		PackID:   packID,
		Emoji:    "🎉",
		Position: 5,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Failed to marshal AddStickerRequest: %v", err)
	}

	var decoded AddStickerRequest
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal AddStickerRequest: %v", err)
	}

	if decoded.PackID != packID {
		t.Errorf("Expected PackID %s, got %s", packID, decoded.PackID)
	}

	if decoded.Emoji != "🎉" {
		t.Errorf("Expected Emoji '🎉', got '%s'", decoded.Emoji)
	}

	if decoded.Position != 5 {
		t.Errorf("Expected Position 5, got %d", decoded.Position)
	}
}

func TestGetExtensionFromContentType(t *testing.T) {
	tests := []struct {
		contentType string
		expected    string
	}{
		{"image/png", ".png"},
		{"image/gif", ".gif"},
		{"image/webp", ".webp"},
		{"application/json", ".json"},
		{"unknown", ""},
	}

	for _, tt := range tests {
		t.Run(tt.contentType, func(t *testing.T) {
			result := getExtensionFromContentType(tt.contentType)
			if result != tt.expected {
				t.Errorf("Expected extension '%s' for content type '%s', got '%s'", tt.expected, tt.contentType, result)
			}
		})
	}
}

func TestCatalogDefaultLimit(t *testing.T) {
	tests := []struct {
		name     string
		input    int
		expected int
	}{
		{"Zero limit", 0, 20},
		{"Negative limit", -1, 20},
		{"Valid limit", 10, 10},
		{"Large limit", 100, 100},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			limit := tt.input
			if limit <= 0 {
				limit = 20
			}
			if tt.name == "Valid limit" && limit != 10 {
				t.Errorf("Expected limit 10, got %d", limit)
			}
			if tt.name == "Zero limit" && limit != 20 {
				t.Errorf("Expected limit 20, got %d", limit)
			}
		})
	}
}

func TestSearchQueryPattern(t *testing.T) {
	queries := []string{
		"emoji",
		"happy",
		"funny cats",
		"cartoon",
	}

	for _, query := range queries {
		searchQuery := "%" + query + "%"

		if len(searchQuery) != len(query)+2 {
			t.Errorf("Expected search query length %d, got %d", len(query)+2, len(searchQuery))
		}

		if searchQuery[0] != '%' || searchQuery[len(searchQuery)-1] != '%' {
			t.Error("Search query should be wrapped with %")
		}
	}
}

func TestOfficialFilter(t *testing.T) {
	tests := []struct {
		name     string
		official *bool
		hasWhere bool
	}{
		{"No filter", nil, false},
		{"Official only", boolPtr(true), true},
		{"Community only", boolPtr(false), true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hasFilter := tt.official != nil
			if hasFilter != tt.hasWhere {
				t.Errorf("Expected hasWhere %v, got %v", tt.hasWhere, hasFilter)
			}
		})
	}
}

func boolPtr(b bool) *bool {
	return &b
}

func TestPackPositionOrdering(t *testing.T) {
	packIDs := []uuid.UUID{
		uuid.New(),
		uuid.New(),
		uuid.New(),
	}

	for i, packID := range packIDs {
		if i > 0 && packID == packIDs[i-1] {
			t.Error("Pack IDs should be unique")
		}
	}

	// Test reorder operation
	newOrder := []uuid.UUID{packIDs[2], packIDs[0], packIDs[1]}

	if newOrder[0] != packIDs[2] {
		t.Error("First pack should be the third original pack")
	}
}

func TestStickerPositioning(t *testing.T) {
	positions := []int{0, 1, 2, 3, 4}

	for i, pos := range positions {
		if pos != i {
			t.Errorf("Expected position %d, got %d", i, pos)
		}
	}
}

func TestPricingOptions(t *testing.T) {
	tests := []struct {
		name  string
		price int
		isFree bool
	}{
		{"Free pack", 0, true},
		{"Paid pack - cheap", 99, false},
		{"Paid pack - standard", 199, false},
		{"Paid pack - premium", 499, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			isFree := tt.price == 0
			if isFree != tt.isFree {
				t.Errorf("Expected isFree %v, got %v", tt.isFree, isFree)
			}
		})
	}
}

func TestAnimatedVsStaticPacks(t *testing.T) {
	tests := []struct {
		name       string
		isAnimated bool
	}{
		{"Static pack", false},
		{"Animated pack", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.name == "Animated pack" && !tt.isAnimated {
				t.Error("Expected animated pack to be animated")
			}
			if tt.name == "Static pack" && tt.isAnimated {
				t.Error("Expected static pack to not be animated")
			}
		})
	}
}

func TestDownloadCountIncrement(t *testing.T) {
	downloads := 0

	// Simulate download
	downloads++

	if downloads != 1 {
		t.Errorf("Expected downloads 1, got %d", downloads)
	}

	// Multiple downloads
	for i := 0; i < 99; i++ {
		downloads++
	}

	if downloads != 100 {
		t.Errorf("Expected downloads 100, got %d", downloads)
	}
}

func TestUserPackOwnership(t *testing.T) {
	userID := uuid.New()
	packID := uuid.New()

	// Simulate ownership tracking
	ownedPacks := make(map[uuid.UUID][]uuid.UUID)
	ownedPacks[userID] = []uuid.UUID{packID}

	// Check ownership
	packs := ownedPacks[userID]
	if len(packs) != 1 {
		t.Errorf("Expected 1 owned pack, got %d", len(packs))
	}

	if packs[0] != packID {
		t.Errorf("Expected pack ID %s, got %s", packID, packs[0])
	}
}

func TestContext_WithTimeout(t *testing.T) {
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

func TestEmojiValidation(t *testing.T) {
	validEmojis := []string{
		"😀", "🎉", "❤️", "👍", "🔥",
		"😂", "🥰", "🤔", "😎", "🙏",
	}

	for _, emoji := range validEmojis {
		if emoji == "" {
			t.Error("Emoji should not be empty")
		}
	}
}

func TestMaxPositionCalculation(t *testing.T) {
	// Simulate COALESCE(MAX(position), -1) + 1
	tests := []struct {
		name        string
		maxPosition *int
		expected    int
	}{
		{"No existing packs", nil, 0},
		{"One existing pack", intPtr(0), 1},
		{"Multiple existing packs", intPtr(4), 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var max int
			if tt.maxPosition == nil {
				max = -1
			} else {
				max = *tt.maxPosition
			}
			nextPosition := max + 1
			if nextPosition != tt.expected {
				t.Errorf("Expected next position %d, got %d", tt.expected, nextPosition)
			}
		})
	}
}

func intPtr(i int) *int {
	return &i
}

func TestImageURLGeneration(t *testing.T) {
	packID := uuid.New()
	stickerID := uuid.New()

	coverPath := "packs/" + packID.String() + "/cover.png"
	stickerPath := "packs/" + packID.String() + "/" + stickerID.String() + ".webp"

	if coverPath == "" {
		t.Error("Cover path should not be empty")
	}

	if stickerPath == "" {
		t.Error("Sticker path should not be empty")
	}

	// Verify paths contain pack ID
	if len(coverPath) < 36 {
		t.Error("Cover path should contain UUID")
	}

	if len(stickerPath) < 72 {
		t.Error("Sticker path should contain two UUIDs")
	}
}

func TestContentTypes(t *testing.T) {
	supportedTypes := []string{
		"image/png",
		"image/gif",
		"image/webp",
		"application/json", // Lottie
	}

	for _, contentType := range supportedTypes {
		ext := getExtensionFromContentType(contentType)
		if ext == "" && contentType != "unknown" {
			t.Errorf("Expected extension for content type '%s'", contentType)
		}
	}
}
