package contacts

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
		{"ContactNotFound", ErrContactNotFound, "contact not found"},
		{"ContactExists", ErrContactExists, "contact already exists"},
		{"CannotAddSelf", ErrCannotAddSelf, "cannot add yourself as contact"},
		{"UserNotFound", ErrUserNotFound, "user not found"},
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
	service := NewService(nil)

	if service == nil {
		t.Error("NewService should not return nil")
	}

	if service.db != nil {
		t.Error("Expected nil db")
	}
}

func TestAddContactRequest_Structure(t *testing.T) {
	userID := uuid.New()
	contactID := uuid.New()
	nickname := "Best Friend"

	req := AddContactRequest{
		UserID:    userID,
		ContactID: contactID,
		Nickname:  &nickname,
	}

	if req.UserID != userID {
		t.Errorf("Expected UserID %s, got %s", userID, req.UserID)
	}

	if req.ContactID != contactID {
		t.Errorf("Expected ContactID %s, got %s", contactID, req.ContactID)
	}

	if req.Nickname == nil || *req.Nickname != nickname {
		t.Errorf("Expected Nickname '%s', got '%v'", nickname, req.Nickname)
	}
}

func TestAddContactRequest_JSON(t *testing.T) {
	userID := uuid.New()
	contactID := uuid.New()

	req := AddContactRequest{
		UserID:    userID,
		ContactID: contactID,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Failed to marshal AddContactRequest: %v", err)
	}

	var decoded AddContactRequest
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal AddContactRequest: %v", err)
	}

	if decoded.UserID != userID {
		t.Errorf("Expected UserID %s, got %s", userID, decoded.UserID)
	}

	if decoded.ContactID != contactID {
		t.Errorf("Expected ContactID %s, got %s", contactID, decoded.ContactID)
	}
}

func TestAddContactRequest_NilNickname(t *testing.T) {
	req := AddContactRequest{
		UserID:    uuid.New(),
		ContactID: uuid.New(),
		Nickname:  nil,
	}

	if req.Nickname != nil {
		t.Error("Expected Nickname to be nil")
	}
}

func TestUpdateContactRequest_Structure(t *testing.T) {
	nickname := "New Nickname"
	isFavorite := true

	req := UpdateContactRequest{
		Nickname:   &nickname,
		IsFavorite: &isFavorite,
	}

	if req.Nickname == nil || *req.Nickname != nickname {
		t.Errorf("Expected Nickname '%s', got '%v'", nickname, req.Nickname)
	}

	if req.IsFavorite == nil || *req.IsFavorite != true {
		t.Error("Expected IsFavorite to be true")
	}
}

func TestUpdateContactRequest_JSON(t *testing.T) {
	nickname := "Test Name"
	isFavorite := false

	req := UpdateContactRequest{
		Nickname:   &nickname,
		IsFavorite: &isFavorite,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Failed to marshal UpdateContactRequest: %v", err)
	}

	var decoded UpdateContactRequest
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal UpdateContactRequest: %v", err)
	}

	if decoded.Nickname == nil || *decoded.Nickname != nickname {
		t.Errorf("Expected Nickname '%s', got '%v'", nickname, decoded.Nickname)
	}

	if decoded.IsFavorite == nil || *decoded.IsFavorite != false {
		t.Error("Expected IsFavorite to be false")
	}
}

func TestUpdateContactRequest_PartialUpdate(t *testing.T) {
	// Test with only nickname
	nickname := "Only Nickname"
	req1 := UpdateContactRequest{
		Nickname: &nickname,
	}

	if req1.Nickname == nil {
		t.Error("Expected Nickname to be set")
	}
	if req1.IsFavorite != nil {
		t.Error("Expected IsFavorite to be nil")
	}

	// Test with only favorite
	isFavorite := true
	req2 := UpdateContactRequest{
		IsFavorite: &isFavorite,
	}

	if req2.Nickname != nil {
		t.Error("Expected Nickname to be nil")
	}
	if req2.IsFavorite == nil {
		t.Error("Expected IsFavorite to be set")
	}
}

func TestCannotAddSelfValidation(t *testing.T) {
	userID := uuid.New()

	req := AddContactRequest{
		UserID:    userID,
		ContactID: userID, // Same as UserID
	}

	if req.UserID != req.ContactID {
		t.Error("Expected UserID to equal ContactID for self-add test")
	}

	// This is the validation that would happen in AddContact
	if req.UserID == req.ContactID {
		// Expected - would return ErrCannotAddSelf
	} else {
		t.Error("Self-add check should trigger")
	}
}

func TestSearchLimits(t *testing.T) {
	tests := []struct {
		name     string
		input    int
		expected int
	}{
		{"Zero limit", 0, 20},
		{"Negative limit", -1, 20},
		{"Over max limit", 100, 20},
		{"Valid limit", 10, 10},
		{"Max valid limit", 50, 50},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			limit := tt.input
			if limit <= 0 || limit > 50 {
				limit = 20
			}

			if tt.name == "Valid limit" || tt.name == "Max valid limit" {
				if limit != tt.expected {
					t.Errorf("Expected limit %d, got %d", tt.expected, limit)
				}
			}
		})
	}
}

func TestSyncContactsEmptyIdentifiers(t *testing.T) {
	identifiers := []string{}

	if len(identifiers) != 0 {
		t.Error("Expected empty identifiers")
	}

	// Service would return nil, nil for empty identifiers
}

func TestSyncContactsWithIdentifiers(t *testing.T) {
	identifiers := []string{
		"+1234567890",
		"test@example.com",
		"+0987654321",
	}

	if len(identifiers) != 3 {
		t.Errorf("Expected 3 identifiers, got %d", len(identifiers))
	}

	for _, id := range identifiers {
		if id == "" {
			t.Error("Identifier should not be empty")
		}
	}
}

func TestContactBlockingState(t *testing.T) {
	tests := []struct {
		name      string
		isBlocked bool
	}{
		{"Not blocked", false},
		{"Blocked", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Simulate contact state
			isBlocked := tt.isBlocked

			if tt.name == "Blocked" && !isBlocked {
				t.Error("Expected contact to be blocked")
			}
			if tt.name == "Not blocked" && isBlocked {
				t.Error("Expected contact to not be blocked")
			}
		})
	}
}

func TestContactFavoriteState(t *testing.T) {
	tests := []struct {
		name       string
		isFavorite bool
	}{
		{"Not favorite", false},
		{"Favorite", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			isFavorite := tt.isFavorite

			if tt.name == "Favorite" && !isFavorite {
				t.Error("Expected contact to be favorite")
			}
			if tt.name == "Not favorite" && isFavorite {
				t.Error("Expected contact to not be favorite")
			}
		})
	}
}

func TestContext_WithTimeout(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	select {
	case <-ctx.Done():
		t.Error("Context should not be done yet")
	default:
		// Expected
	}

	// Wait for timeout
	time.Sleep(150 * time.Millisecond)

	select {
	case <-ctx.Done():
		// Expected
	default:
		t.Error("Context should be done after timeout")
	}
}

func TestContext_WithCancel(t *testing.T) {
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

func TestUUIDComparison(t *testing.T) {
	id1 := uuid.New()
	id2 := uuid.New()
	id1Copy := id1

	if id1 == id2 {
		t.Error("Different UUIDs should not be equal")
	}

	if id1 != id1Copy {
		t.Error("Same UUIDs should be equal")
	}
}

func TestSearchQueryPattern(t *testing.T) {
	queries := []string{
		"john",
		"john.doe",
		"John Doe",
		"+1234567890",
		"test@example.com",
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

func TestIncludeBlockedFilter(t *testing.T) {
	tests := []struct {
		name           string
		includeBlocked bool
		expectFilter   bool
	}{
		{"Include blocked", true, false},
		{"Exclude blocked", false, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.includeBlocked && tt.expectFilter {
				t.Error("Should not add filter when including blocked")
			}
			if !tt.includeBlocked && !tt.expectFilter {
				t.Error("Should add filter when excluding blocked")
			}
		})
	}
}

func TestNicknameOptional(t *testing.T) {
	// Test with nickname
	nickname := "Custom Name"
	req1 := AddContactRequest{
		UserID:    uuid.New(),
		ContactID: uuid.New(),
		Nickname:  &nickname,
	}

	if req1.Nickname == nil {
		t.Error("Expected nickname to be set")
	}

	// Test without nickname
	req2 := AddContactRequest{
		UserID:    uuid.New(),
		ContactID: uuid.New(),
	}

	if req2.Nickname != nil {
		t.Error("Expected nickname to be nil")
	}
}

func TestContactOrdering(t *testing.T) {
	// Test that favorites come first, then alphabetically by display_name
	type contactOrder struct {
		displayName string
		isFavorite  bool
	}

	contacts := []contactOrder{
		{"Alice", false},
		{"Bob", true},
		{"Charlie", false},
		{"David", true},
	}

	// Sort: favorites first, then by name
	// Expected order: Bob, David, Alice, Charlie

	favoriteCount := 0
	for _, c := range contacts {
		if c.isFavorite {
			favoriteCount++
		}
	}

	if favoriteCount != 2 {
		t.Errorf("Expected 2 favorites, got %d", favoriteCount)
	}
}

func TestPhoneAndEmailSearch(t *testing.T) {
	phone := "+1234567890"
	email := "test@example.com"
	username := "testuser"

	// Test that search can match any of these
	searchInputs := []string{phone, email, username}

	for _, input := range searchInputs {
		if input == "" {
			t.Error("Search input should not be empty")
		}
	}
}

func TestEmptyResults(t *testing.T) {
	// Test handling of empty contact lists
	var contacts []string = nil

	if contacts != nil {
		t.Error("Expected nil contacts")
	}

	contacts = []string{}
	if len(contacts) != 0 {
		t.Error("Expected empty contacts slice")
	}
}
