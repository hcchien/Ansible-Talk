package contacts

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/storage"
)

var (
	ErrContactNotFound   = errors.New("contact not found")
	ErrContactExists     = errors.New("contact already exists")
	ErrCannotAddSelf     = errors.New("cannot add yourself as contact")
	ErrUserNotFound      = errors.New("user not found")
)

// Service handles contact operations
type Service struct {
	db *storage.PostgresDB
}

// NewService creates a new contacts service
func NewService(db *storage.PostgresDB) *Service {
	return &Service{db: db}
}

// AddContactRequest represents a request to add a contact
type AddContactRequest struct {
	UserID    uuid.UUID `json:"user_id"`
	ContactID uuid.UUID `json:"contact_id"`
	Nickname  *string   `json:"nickname,omitempty"`
}

// AddContact adds a new contact for a user
func (s *Service) AddContact(ctx context.Context, req AddContactRequest) (*models.Contact, error) {
	if req.UserID == req.ContactID {
		return nil, ErrCannotAddSelf
	}

	// Verify contact user exists
	var exists bool
	err := s.db.Pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, req.ContactID).Scan(&exists)
	if err != nil {
		return nil, fmt.Errorf("failed to check user existence: %w", err)
	}
	if !exists {
		return nil, ErrUserNotFound
	}

	// Create contact
	var contact models.Contact
	err = s.db.Pool.QueryRow(ctx, `
		INSERT INTO contacts (user_id, contact_id, nickname)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, contact_id, nickname, is_blocked, is_favorite, created_at, updated_at
	`, req.UserID, req.ContactID, req.Nickname).Scan(
		&contact.ID, &contact.UserID, &contact.ContactID, &contact.Nickname,
		&contact.IsBlocked, &contact.IsFavorite, &contact.CreatedAt, &contact.UpdatedAt,
	)
	if err != nil {
		if err.Error() == "ERROR: duplicate key value violates unique constraint" {
			return nil, ErrContactExists
		}
		return nil, fmt.Errorf("failed to create contact: %w", err)
	}

	// Fetch contact user details
	contact.Contact = &models.User{}
	err = s.db.Pool.QueryRow(ctx, `
		SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at
		FROM users WHERE id = $1
	`, contact.ContactID).Scan(
		&contact.Contact.ID, &contact.Contact.Phone, &contact.Contact.Email,
		&contact.Contact.Username, &contact.Contact.DisplayName, &contact.Contact.AvatarURL,
		&contact.Contact.Bio, &contact.Contact.Status, &contact.Contact.LastSeenAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch contact details: %w", err)
	}

	return &contact, nil
}

// GetContacts retrieves all contacts for a user
func (s *Service) GetContacts(ctx context.Context, userID uuid.UUID, includeBlocked bool) ([]models.Contact, error) {
	query := `
		SELECT c.id, c.user_id, c.contact_id, c.nickname, c.is_blocked, c.is_favorite, c.created_at, c.updated_at,
		       u.id, u.phone, u.email, u.username, u.display_name, u.avatar_url, u.bio, u.status, u.last_seen_at
		FROM contacts c
		JOIN users u ON c.contact_id = u.id
		WHERE c.user_id = $1
	`
	if !includeBlocked {
		query += " AND c.is_blocked = FALSE"
	}
	query += " ORDER BY c.is_favorite DESC, u.display_name ASC"

	rows, err := s.db.Pool.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get contacts: %w", err)
	}
	defer rows.Close()

	var contacts []models.Contact
	for rows.Next() {
		var contact models.Contact
		contact.Contact = &models.User{}
		err := rows.Scan(
			&contact.ID, &contact.UserID, &contact.ContactID, &contact.Nickname,
			&contact.IsBlocked, &contact.IsFavorite, &contact.CreatedAt, &contact.UpdatedAt,
			&contact.Contact.ID, &contact.Contact.Phone, &contact.Contact.Email,
			&contact.Contact.Username, &contact.Contact.DisplayName, &contact.Contact.AvatarURL,
			&contact.Contact.Bio, &contact.Contact.Status, &contact.Contact.LastSeenAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan contact: %w", err)
		}
		contacts = append(contacts, contact)
	}

	return contacts, nil
}

// GetContact retrieves a specific contact
func (s *Service) GetContact(ctx context.Context, userID, contactID uuid.UUID) (*models.Contact, error) {
	var contact models.Contact
	contact.Contact = &models.User{}

	err := s.db.Pool.QueryRow(ctx, `
		SELECT c.id, c.user_id, c.contact_id, c.nickname, c.is_blocked, c.is_favorite, c.created_at, c.updated_at,
		       u.id, u.phone, u.email, u.username, u.display_name, u.avatar_url, u.bio, u.status, u.last_seen_at
		FROM contacts c
		JOIN users u ON c.contact_id = u.id
		WHERE c.user_id = $1 AND c.contact_id = $2
	`, userID, contactID).Scan(
		&contact.ID, &contact.UserID, &contact.ContactID, &contact.Nickname,
		&contact.IsBlocked, &contact.IsFavorite, &contact.CreatedAt, &contact.UpdatedAt,
		&contact.Contact.ID, &contact.Contact.Phone, &contact.Contact.Email,
		&contact.Contact.Username, &contact.Contact.DisplayName, &contact.Contact.AvatarURL,
		&contact.Contact.Bio, &contact.Contact.Status, &contact.Contact.LastSeenAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrContactNotFound
		}
		return nil, fmt.Errorf("failed to get contact: %w", err)
	}

	return &contact, nil
}

// UpdateContactRequest represents a request to update a contact
type UpdateContactRequest struct {
	Nickname   *string `json:"nickname,omitempty"`
	IsFavorite *bool   `json:"is_favorite,omitempty"`
}

// UpdateContact updates a contact's information
func (s *Service) UpdateContact(ctx context.Context, userID, contactID uuid.UUID, req UpdateContactRequest) (*models.Contact, error) {
	// Build dynamic update query
	query := "UPDATE contacts SET updated_at = NOW()"
	args := []interface{}{userID, contactID}
	argIndex := 3

	if req.Nickname != nil {
		query += fmt.Sprintf(", nickname = $%d", argIndex)
		args = append(args, *req.Nickname)
		argIndex++
	}
	if req.IsFavorite != nil {
		query += fmt.Sprintf(", is_favorite = $%d", argIndex)
		args = append(args, *req.IsFavorite)
		argIndex++
	}

	query += " WHERE user_id = $1 AND contact_id = $2"

	result, err := s.db.Pool.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update contact: %w", err)
	}

	if result.RowsAffected() == 0 {
		return nil, ErrContactNotFound
	}

	return s.GetContact(ctx, userID, contactID)
}

// DeleteContact removes a contact
func (s *Service) DeleteContact(ctx context.Context, userID, contactID uuid.UUID) error {
	result, err := s.db.Pool.Exec(ctx, `
		DELETE FROM contacts WHERE user_id = $1 AND contact_id = $2
	`, userID, contactID)
	if err != nil {
		return fmt.Errorf("failed to delete contact: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrContactNotFound
	}

	return nil
}

// BlockContact blocks a contact
func (s *Service) BlockContact(ctx context.Context, userID, contactID uuid.UUID) error {
	result, err := s.db.Pool.Exec(ctx, `
		UPDATE contacts SET is_blocked = TRUE, updated_at = NOW()
		WHERE user_id = $1 AND contact_id = $2
	`, userID, contactID)
	if err != nil {
		return fmt.Errorf("failed to block contact: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrContactNotFound
	}

	return nil
}

// UnblockContact unblocks a contact
func (s *Service) UnblockContact(ctx context.Context, userID, contactID uuid.UUID) error {
	result, err := s.db.Pool.Exec(ctx, `
		UPDATE contacts SET is_blocked = FALSE, updated_at = NOW()
		WHERE user_id = $1 AND contact_id = $2
	`, userID, contactID)
	if err != nil {
		return fmt.Errorf("failed to unblock contact: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrContactNotFound
	}

	return nil
}

// GetBlockedContacts retrieves all blocked contacts
func (s *Service) GetBlockedContacts(ctx context.Context, userID uuid.UUID) ([]models.Contact, error) {
	rows, err := s.db.Pool.Query(ctx, `
		SELECT c.id, c.user_id, c.contact_id, c.nickname, c.is_blocked, c.is_favorite, c.created_at, c.updated_at,
		       u.id, u.phone, u.email, u.username, u.display_name, u.avatar_url, u.bio, u.status, u.last_seen_at
		FROM contacts c
		JOIN users u ON c.contact_id = u.id
		WHERE c.user_id = $1 AND c.is_blocked = TRUE
		ORDER BY u.display_name ASC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get blocked contacts: %w", err)
	}
	defer rows.Close()

	var contacts []models.Contact
	for rows.Next() {
		var contact models.Contact
		contact.Contact = &models.User{}
		err := rows.Scan(
			&contact.ID, &contact.UserID, &contact.ContactID, &contact.Nickname,
			&contact.IsBlocked, &contact.IsFavorite, &contact.CreatedAt, &contact.UpdatedAt,
			&contact.Contact.ID, &contact.Contact.Phone, &contact.Contact.Email,
			&contact.Contact.Username, &contact.Contact.DisplayName, &contact.Contact.AvatarURL,
			&contact.Contact.Bio, &contact.Contact.Status, &contact.Contact.LastSeenAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan contact: %w", err)
		}
		contacts = append(contacts, contact)
	}

	return contacts, nil
}

// SearchUsers searches for users by phone, email, or username
func (s *Service) SearchUsers(ctx context.Context, query string, limit int) ([]models.User, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	searchQuery := "%" + query + "%"
	rows, err := s.db.Pool.Query(ctx, `
		SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at
		FROM users
		WHERE username ILIKE $1 OR display_name ILIKE $1 OR phone = $2 OR email ILIKE $1
		LIMIT $3
	`, searchQuery, query, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to search users: %w", err)
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var user models.User
		err := rows.Scan(
			&user.ID, &user.Phone, &user.Email, &user.Username, &user.DisplayName,
			&user.AvatarURL, &user.Bio, &user.Status, &user.LastSeenAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}

	return users, nil
}

// SyncContacts syncs contacts from phone numbers or emails
func (s *Service) SyncContacts(ctx context.Context, userID uuid.UUID, identifiers []string) ([]models.User, error) {
	if len(identifiers) == 0 {
		return nil, nil
	}

	rows, err := s.db.Pool.Query(ctx, `
		SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at
		FROM users
		WHERE (phone = ANY($1) OR email = ANY($1)) AND id != $2
	`, identifiers, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to sync contacts: %w", err)
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var user models.User
		err := rows.Scan(
			&user.ID, &user.Phone, &user.Email, &user.Username, &user.DisplayName,
			&user.AvatarURL, &user.Bio, &user.Status, &user.LastSeenAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}

	return users, nil
}
