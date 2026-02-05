package stickers

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path/filepath"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/storage"
)

var (
	ErrPackNotFound     = errors.New("sticker pack not found")
	ErrStickerNotFound  = errors.New("sticker not found")
	ErrAlreadyOwned     = errors.New("sticker pack already owned")
	ErrNotOwned         = errors.New("sticker pack not owned")
)

// Service handles sticker operations
type Service struct {
	db    *storage.PostgresDB
	minio *storage.MinIOClient
}

// NewService creates a new stickers service
func NewService(db *storage.PostgresDB, minio *storage.MinIOClient) *Service {
	return &Service{
		db:    db,
		minio: minio,
	}
}

// CreatePackRequest represents a request to create a sticker pack
type CreatePackRequest struct {
	Name        string  `json:"name"`
	Author      string  `json:"author"`
	Description *string `json:"description,omitempty"`
	IsOfficial  bool    `json:"is_official"`
	IsAnimated  bool    `json:"is_animated"`
	Price       int     `json:"price"`
}

// CreatePack creates a new sticker pack
func (s *Service) CreatePack(ctx context.Context, req CreatePackRequest) (*models.StickerPack, error) {
	var pack models.StickerPack
	err := s.db.Pool.QueryRow(ctx, `
		INSERT INTO sticker_packs (name, author, description, is_official, is_animated, price, cover_url)
		VALUES ($1, $2, $3, $4, $5, $6, '')
		RETURNING id, name, author, description, cover_url, is_official, is_animated, price, downloads, created_at, updated_at
	`, req.Name, req.Author, req.Description, req.IsOfficial, req.IsAnimated, req.Price).Scan(
		&pack.ID, &pack.Name, &pack.Author, &pack.Description, &pack.CoverURL,
		&pack.IsOfficial, &pack.IsAnimated, &pack.Price, &pack.Downloads, &pack.CreatedAt, &pack.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create sticker pack: %w", err)
	}

	return &pack, nil
}

// UploadPackCover uploads the cover image for a sticker pack
func (s *Service) UploadPackCover(ctx context.Context, packID uuid.UUID, reader io.Reader, size int64, contentType string) (string, error) {
	objectName := fmt.Sprintf("packs/%s/cover%s", packID, getExtensionFromContentType(contentType))

	err := s.minio.UploadFile(ctx, s.minio.Config.StickersBucket, objectName, reader, size, contentType)
	if err != nil {
		return "", fmt.Errorf("failed to upload cover: %w", err)
	}

	coverURL := s.minio.GetFileURL(s.minio.Config.StickersBucket, objectName)

	// Update pack with cover URL
	_, err = s.db.Pool.Exec(ctx, `
		UPDATE sticker_packs SET cover_url = $1, updated_at = NOW() WHERE id = $2
	`, coverURL, packID)
	if err != nil {
		return "", fmt.Errorf("failed to update pack cover: %w", err)
	}

	return coverURL, nil
}

// AddStickerRequest represents a request to add a sticker to a pack
type AddStickerRequest struct {
	PackID   uuid.UUID `json:"pack_id"`
	Emoji    string    `json:"emoji"`
	Position int       `json:"position"`
}

// AddSticker adds a sticker to a pack
func (s *Service) AddSticker(ctx context.Context, req AddStickerRequest, reader io.Reader, size int64, contentType string) (*models.Sticker, error) {
	// Verify pack exists
	var exists bool
	err := s.db.Pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM sticker_packs WHERE id = $1)`, req.PackID).Scan(&exists)
	if err != nil || !exists {
		return nil, ErrPackNotFound
	}

	// Generate sticker ID
	stickerID := uuid.New()
	objectName := fmt.Sprintf("packs/%s/%s%s", req.PackID, stickerID, getExtensionFromContentType(contentType))

	// Upload sticker image
	err = s.minio.UploadFile(ctx, s.minio.Config.StickersBucket, objectName, reader, size, contentType)
	if err != nil {
		return nil, fmt.Errorf("failed to upload sticker: %w", err)
	}

	imageURL := s.minio.GetFileURL(s.minio.Config.StickersBucket, objectName)

	// Create sticker record
	var sticker models.Sticker
	err = s.db.Pool.QueryRow(ctx, `
		INSERT INTO stickers (id, pack_id, emoji, image_url, position)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, pack_id, emoji, image_url, position, created_at
	`, stickerID, req.PackID, req.Emoji, imageURL, req.Position).Scan(
		&sticker.ID, &sticker.PackID, &sticker.Emoji, &sticker.ImageURL, &sticker.Position, &sticker.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create sticker: %w", err)
	}

	return &sticker, nil
}

// GetPack retrieves a sticker pack with all its stickers
func (s *Service) GetPack(ctx context.Context, packID uuid.UUID) (*models.StickerPack, error) {
	var pack models.StickerPack
	err := s.db.Pool.QueryRow(ctx, `
		SELECT id, name, author, description, cover_url, is_official, is_animated, price, downloads, created_at, updated_at
		FROM sticker_packs WHERE id = $1
	`, packID).Scan(
		&pack.ID, &pack.Name, &pack.Author, &pack.Description, &pack.CoverURL,
		&pack.IsOfficial, &pack.IsAnimated, &pack.Price, &pack.Downloads, &pack.CreatedAt, &pack.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrPackNotFound
		}
		return nil, fmt.Errorf("failed to get pack: %w", err)
	}

	// Get stickers
	rows, err := s.db.Pool.Query(ctx, `
		SELECT id, pack_id, emoji, image_url, position, created_at
		FROM stickers WHERE pack_id = $1
		ORDER BY position ASC
	`, packID)
	if err != nil {
		return nil, fmt.Errorf("failed to get stickers: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var sticker models.Sticker
		err := rows.Scan(&sticker.ID, &sticker.PackID, &sticker.Emoji, &sticker.ImageURL, &sticker.Position, &sticker.CreatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan sticker: %w", err)
		}
		pack.Stickers = append(pack.Stickers, sticker)
	}

	return &pack, nil
}

// GetCatalog retrieves the sticker pack catalog
func (s *Service) GetCatalog(ctx context.Context, limit, offset int, official *bool) ([]models.StickerPack, error) {
	if limit <= 0 {
		limit = 20
	}

	query := `
		SELECT id, name, author, description, cover_url, is_official, is_animated, price, downloads, created_at, updated_at
		FROM sticker_packs
	`
	args := []interface{}{}

	if official != nil {
		query += " WHERE is_official = $1"
		args = append(args, *official)
	}

	query += " ORDER BY downloads DESC, created_at DESC"
	query += fmt.Sprintf(" LIMIT %d OFFSET %d", limit, offset)

	rows, err := s.db.Pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get catalog: %w", err)
	}
	defer rows.Close()

	var packs []models.StickerPack
	for rows.Next() {
		var pack models.StickerPack
		err := rows.Scan(
			&pack.ID, &pack.Name, &pack.Author, &pack.Description, &pack.CoverURL,
			&pack.IsOfficial, &pack.IsAnimated, &pack.Price, &pack.Downloads, &pack.CreatedAt, &pack.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan pack: %w", err)
		}
		packs = append(packs, pack)
	}

	return packs, nil
}

// SearchPacks searches for sticker packs
func (s *Service) SearchPacks(ctx context.Context, query string, limit int) ([]models.StickerPack, error) {
	if limit <= 0 {
		limit = 20
	}

	searchQuery := "%" + query + "%"
	rows, err := s.db.Pool.Query(ctx, `
		SELECT id, name, author, description, cover_url, is_official, is_animated, price, downloads, created_at, updated_at
		FROM sticker_packs
		WHERE name ILIKE $1 OR author ILIKE $1 OR description ILIKE $1
		ORDER BY downloads DESC
		LIMIT $2
	`, searchQuery, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to search packs: %w", err)
	}
	defer rows.Close()

	var packs []models.StickerPack
	for rows.Next() {
		var pack models.StickerPack
		err := rows.Scan(
			&pack.ID, &pack.Name, &pack.Author, &pack.Description, &pack.CoverURL,
			&pack.IsOfficial, &pack.IsAnimated, &pack.Price, &pack.Downloads, &pack.CreatedAt, &pack.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan pack: %w", err)
		}
		packs = append(packs, pack)
	}

	return packs, nil
}

// DownloadPack adds a sticker pack to user's collection
func (s *Service) DownloadPack(ctx context.Context, userID, packID uuid.UUID) error {
	// Check if already owned
	var exists bool
	err := s.db.Pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM user_sticker_packs WHERE user_id = $1 AND pack_id = $2)
	`, userID, packID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("failed to check ownership: %w", err)
	}
	if exists {
		return ErrAlreadyOwned
	}

	// Get next position
	var maxPosition int
	s.db.Pool.QueryRow(ctx, `
		SELECT COALESCE(MAX(position), -1) FROM user_sticker_packs WHERE user_id = $1
	`, userID).Scan(&maxPosition)

	// Add to user's collection
	_, err = s.db.Pool.Exec(ctx, `
		INSERT INTO user_sticker_packs (user_id, pack_id, position)
		VALUES ($1, $2, $3)
	`, userID, packID, maxPosition+1)
	if err != nil {
		return fmt.Errorf("failed to add pack: %w", err)
	}

	// Increment download count
	_, err = s.db.Pool.Exec(ctx, `
		UPDATE sticker_packs SET downloads = downloads + 1 WHERE id = $1
	`, packID)
	if err != nil {
		return fmt.Errorf("failed to update download count: %w", err)
	}

	return nil
}

// RemovePack removes a sticker pack from user's collection
func (s *Service) RemovePack(ctx context.Context, userID, packID uuid.UUID) error {
	result, err := s.db.Pool.Exec(ctx, `
		DELETE FROM user_sticker_packs WHERE user_id = $1 AND pack_id = $2
	`, userID, packID)
	if err != nil {
		return fmt.Errorf("failed to remove pack: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrNotOwned
	}

	return nil
}

// GetUserPacks retrieves all sticker packs owned by a user
func (s *Service) GetUserPacks(ctx context.Context, userID uuid.UUID) ([]models.StickerPack, error) {
	rows, err := s.db.Pool.Query(ctx, `
		SELECT p.id, p.name, p.author, p.description, p.cover_url, p.is_official, p.is_animated, p.price, p.downloads, p.created_at, p.updated_at
		FROM sticker_packs p
		JOIN user_sticker_packs up ON p.id = up.pack_id
		WHERE up.user_id = $1
		ORDER BY up.position ASC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user packs: %w", err)
	}
	defer rows.Close()

	var packs []models.StickerPack
	for rows.Next() {
		var pack models.StickerPack
		err := rows.Scan(
			&pack.ID, &pack.Name, &pack.Author, &pack.Description, &pack.CoverURL,
			&pack.IsOfficial, &pack.IsAnimated, &pack.Price, &pack.Downloads, &pack.CreatedAt, &pack.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan pack: %w", err)
		}
		packs = append(packs, pack)
	}

	// Fetch stickers for each pack
	for i := range packs {
		pack, err := s.GetPack(ctx, packs[i].ID)
		if err == nil {
			packs[i].Stickers = pack.Stickers
		}
	}

	return packs, nil
}

// ReorderPacks reorders user's sticker packs
func (s *Service) ReorderPacks(ctx context.Context, userID uuid.UUID, packIDs []uuid.UUID) error {
	tx, err := s.db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	for i, packID := range packIDs {
		_, err := tx.Exec(ctx, `
			UPDATE user_sticker_packs SET position = $1 WHERE user_id = $2 AND pack_id = $3
		`, i, userID, packID)
		if err != nil {
			return fmt.Errorf("failed to update position: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// GetSticker retrieves a single sticker
func (s *Service) GetSticker(ctx context.Context, stickerID uuid.UUID) (*models.Sticker, error) {
	var sticker models.Sticker
	err := s.db.Pool.QueryRow(ctx, `
		SELECT id, pack_id, emoji, image_url, position, created_at
		FROM stickers WHERE id = $1
	`, stickerID).Scan(
		&sticker.ID, &sticker.PackID, &sticker.Emoji, &sticker.ImageURL, &sticker.Position, &sticker.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrStickerNotFound
		}
		return nil, fmt.Errorf("failed to get sticker: %w", err)
	}

	return &sticker, nil
}

// Helper function to get file extension from content type
func getExtensionFromContentType(contentType string) string {
	switch contentType {
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "application/json":
		return ".json" // For Lottie animations
	default:
		return filepath.Ext(contentType)
	}
}
