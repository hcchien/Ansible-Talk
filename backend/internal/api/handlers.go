package api

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/ansible-talk/backend/internal/auth"
	"github.com/ansible-talk/backend/internal/contacts"
	"github.com/ansible-talk/backend/internal/crypto"
	"github.com/ansible-talk/backend/internal/messaging"
	"github.com/ansible-talk/backend/internal/models"
	"github.com/ansible-talk/backend/internal/stickers"
)

// Auth handlers

type SendOTPRequest struct {
	Target string `json:"target" binding:"required"`
	Type   string `json:"type" binding:"required,oneof=phone email"`
}

func (s *Server) sendOTP(c *gin.Context) {
	var req SendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := s.AuthService.SendOTP(c.Request.Context(), req.Target, models.OTPType(req.Type))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send OTP"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "OTP sent successfully"})
}

type VerifyOTPRequest struct {
	Target string `json:"target" binding:"required"`
	Type   string `json:"type" binding:"required,oneof=phone email"`
	Code   string `json:"code" binding:"required"`
}

func (s *Server) verifyOTP(c *gin.Context) {
	var req VerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := s.AuthService.VerifyOTP(c.Request.Context(), req.Target, models.OTPType(req.Type), req.Code)
	if err != nil {
		status := http.StatusBadRequest
		if err == auth.ErrTooManyAttempts {
			status = http.StatusTooManyRequests
		}
		c.JSON(status, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"verified": true})
}

type RegisterRequest struct {
	Phone       *string `json:"phone,omitempty"`
	Email       *string `json:"email,omitempty"`
	Username    string  `json:"username" binding:"required"`
	DisplayName string  `json:"display_name" binding:"required"`
	DeviceName  string  `json:"device_name" binding:"required"`
	Platform    string  `json:"platform" binding:"required"`
}

func (s *Server) register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Phone == nil && req.Email == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone or email is required"})
		return
	}

	user, tokens, err := s.AuthService.Register(c.Request.Context(), auth.RegisterRequest{
		Phone:       req.Phone,
		Email:       req.Email,
		Username:    req.Username,
		DisplayName: req.DisplayName,
		DeviceName:  req.DeviceName,
		Platform:    req.Platform,
	})
	if err != nil {
		if err == auth.ErrUserAlreadyExists {
			c.JSON(http.StatusConflict, gin.H{"error": "user already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"user":   user,
		"tokens": tokens,
	})
}

type LoginRequest struct {
	Target     string `json:"target" binding:"required"`
	Type       string `json:"type" binding:"required,oneof=phone email"`
	DeviceName string `json:"device_name" binding:"required"`
	Platform   string `json:"platform" binding:"required"`
}

func (s *Server) login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, tokens, err := s.AuthService.Login(c.Request.Context(), req.Target, models.OTPType(req.Type), req.DeviceName, req.Platform)
	if err != nil {
		if err == auth.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"user":   user,
		"tokens": tokens,
	})
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (s *Server) refreshToken(c *gin.Context) {
	var req RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tokens, err := s.AuthService.RefreshToken(c.Request.Context(), req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"tokens": tokens})
}

func (s *Server) logout(c *gin.Context) {
	userID := getUserID(c)
	deviceID := getDeviceID(c)

	if err := s.AuthService.Logout(c.Request.Context(), userID, deviceID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "logout failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "logged out successfully"})
}

func (s *Server) logoutAll(c *gin.Context) {
	userID := getUserID(c)

	if err := s.AuthService.LogoutAll(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "logout failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "logged out from all devices"})
}

// User handlers

func (s *Server) getCurrentUser(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var user models.User
	err := s.DB.Pool.QueryRow(c.Request.Context(), `
		SELECT id, phone, email, username, display_name, avatar_url, bio, status, last_seen_at, created_at, updated_at
		FROM users WHERE id = $1
	`, uid).Scan(
		&user.ID, &user.Phone, &user.Email, &user.Username, &user.DisplayName,
		&user.AvatarURL, &user.Bio, &user.Status, &user.LastSeenAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

func (s *Server) updateCurrentUser(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		DisplayName *string `json:"display_name,omitempty"`
		Username    *string `json:"username,omitempty"`
		Bio         *string `json:"bio,omitempty"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Build update query dynamically
	updates := make(map[string]interface{})
	if req.DisplayName != nil {
		updates["display_name"] = *req.DisplayName
	}
	if req.Username != nil {
		updates["username"] = *req.Username
	}
	if req.Bio != nil {
		updates["bio"] = *req.Bio
	}

	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no fields to update"})
		return
	}

	// Simple update for now
	_, err := s.DB.Pool.Exec(c.Request.Context(), `
		UPDATE users SET display_name = COALESCE($1, display_name), username = COALESCE($2, username), bio = COALESCE($3, bio), updated_at = NOW()
		WHERE id = $4
	`, req.DisplayName, req.Username, req.Bio, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
		return
	}

	// Return updated user
	s.getCurrentUser(c)
}

func (s *Server) uploadAvatar(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	file, header, err := c.Request.FormFile("avatar")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "avatar file required"})
		return
	}
	defer file.Close()

	// Upload to MinIO
	objectName := "avatars/" + userID + "/" + header.Filename
	err = s.MinIO.UploadFile(c.Request.Context(), s.MinIO.Config.AvatarsBucket, objectName, file, header.Size, header.Header.Get("Content-Type"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "upload failed"})
		return
	}

	avatarURL := s.MinIO.GetFileURL(s.MinIO.Config.AvatarsBucket, objectName)

	// Update user
	_, err = s.DB.Pool.Exec(c.Request.Context(), `UPDATE users SET avatar_url = $1 WHERE id = $2`, avatarURL, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"avatar_url": avatarURL})
}

func (s *Server) searchUsers(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "search query required"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	users, err := s.ContactsService.SearchUsers(c.Request.Context(), query, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}

	// Filter out current user
	var filtered []models.User
	for _, u := range users {
		if u.ID != uid {
			filtered = append(filtered, u)
		}
	}

	c.JSON(http.StatusOK, filtered)
}

// Device handlers

func (s *Server) getDevices(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	rows, err := s.DB.Pool.Query(c.Request.Context(), `
		SELECT id, user_id, device_id, name, platform, last_active_at, created_at
		FROM devices WHERE user_id = $1
		ORDER BY last_active_at DESC
	`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get devices"})
		return
	}
	defer rows.Close()

	var devices []models.Device
	for rows.Next() {
		var d models.Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.DeviceID, &d.Name, &d.Platform, &d.LastActiveAt, &d.CreatedAt); err != nil {
			continue
		}
		devices = append(devices, d)
	}

	c.JSON(http.StatusOK, devices)
}

func (s *Server) removeDevice(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	deviceID, _ := uuid.Parse(c.Param("id"))

	_, err := s.DB.Pool.Exec(c.Request.Context(), `DELETE FROM devices WHERE id = $1 AND user_id = $2`, deviceID, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "device removed"})
}

// Signal keys handlers

func (s *Server) registerKeys(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req crypto.RegisterKeysRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.UserID = uid

	if err := s.CryptoService.RegisterKeys(c.Request.Context(), req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register keys"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "keys registered"})
}

func (s *Server) getKeyBundle(c *gin.Context) {
	targetUserID, _ := uuid.Parse(c.Param("user_id"))
	deviceID, _ := strconv.Atoi(c.Param("device_id"))

	bundle, err := s.CryptoService.GetKeyBundle(c.Request.Context(), targetUserID, deviceID)
	if err != nil {
		if err == crypto.ErrIdentityKeyNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "key bundle not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get key bundle"})
		return
	}

	c.JSON(http.StatusOK, bundle)
}

func (s *Server) getPreKeyCount(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	deviceID, _ := strconv.Atoi(c.Query("device_id"))

	count, err := s.CryptoService.GetPreKeyCount(c.Request.Context(), uid, deviceID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get count"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"count": count})
}

func (s *Server) refreshPreKeys(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		DeviceID int            `json:"device_id"`
		PreKeys  []crypto.PreKey `json:"pre_keys"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := s.CryptoService.RefreshPreKeys(c.Request.Context(), uid, req.DeviceID, req.PreKeys); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to refresh keys"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "pre-keys refreshed"})
}

func (s *Server) updateSignedPreKey(c *gin.Context) {
	userID := getUserID(c)
	deviceID := getDeviceID(c)
	uid, _ := uuid.Parse(userID)
	did, _ := strconv.Atoi(deviceID)

	var req crypto.SignedPreKey
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := s.CryptoService.UpdateSignedPreKey(c.Request.Context(), uid, did, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update signed pre-key"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "signed pre-key updated"})
}

// Contact handlers

func (s *Server) getContacts(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	includeBlocked := c.Query("include_blocked") == "true"

	contactsList, err := s.ContactsService.GetContacts(c.Request.Context(), uid, includeBlocked)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get contacts"})
		return
	}

	c.JSON(http.StatusOK, contactsList)
}

func (s *Server) addContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		ContactID string  `json:"contact_id" binding:"required"`
		Nickname  *string `json:"nickname,omitempty"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	contactID, _ := uuid.Parse(req.ContactID)

	contact, err := s.ContactsService.AddContact(c.Request.Context(), contacts.AddContactRequest{
		UserID:    uid,
		ContactID: contactID,
		Nickname:  req.Nickname,
	})
	if err != nil {
		if err == contacts.ErrCannotAddSelf {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cannot add yourself"})
			return
		}
		if err == contacts.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		if err == contacts.ErrContactExists {
			c.JSON(http.StatusConflict, gin.H{"error": "contact already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add contact"})
		return
	}

	c.JSON(http.StatusCreated, contact)
}

func (s *Server) getContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	contactID, _ := uuid.Parse(c.Param("id"))

	contact, err := s.ContactsService.GetContact(c.Request.Context(), uid, contactID)
	if err != nil {
		if err == contacts.ErrContactNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "contact not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get contact"})
		return
	}

	c.JSON(http.StatusOK, contact)
}

func (s *Server) updateContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	contactID, _ := uuid.Parse(c.Param("id"))

	var req contacts.UpdateContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	contact, err := s.ContactsService.UpdateContact(c.Request.Context(), uid, contactID, req)
	if err != nil {
		if err == contacts.ErrContactNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "contact not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update contact"})
		return
	}

	c.JSON(http.StatusOK, contact)
}

func (s *Server) deleteContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	contactID, _ := uuid.Parse(c.Param("id"))

	if err := s.ContactsService.DeleteContact(c.Request.Context(), uid, contactID); err != nil {
		if err == contacts.ErrContactNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "contact not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete contact"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "contact deleted"})
}

func (s *Server) blockContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	contactID, _ := uuid.Parse(c.Param("id"))

	if err := s.ContactsService.BlockContact(c.Request.Context(), uid, contactID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to block contact"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "contact blocked"})
}

func (s *Server) unblockContact(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	contactID, _ := uuid.Parse(c.Param("id"))

	if err := s.ContactsService.UnblockContact(c.Request.Context(), uid, contactID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to unblock contact"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "contact unblocked"})
}

func (s *Server) getBlockedContacts(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	blockedList, err := s.ContactsService.GetBlockedContacts(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get blocked contacts"})
		return
	}

	c.JSON(http.StatusOK, blockedList)
}

func (s *Server) syncContacts(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		Identifiers []string `json:"identifiers" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	users, err := s.ContactsService.SyncContacts(c.Request.Context(), uid, req.Identifiers)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to sync contacts"})
		return
	}

	c.JSON(http.StatusOK, users)
}

// Conversation handlers

func (s *Server) getConversations(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	conversations, err := s.MessagingService.GetUserConversations(c.Request.Context(), uid, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get conversations"})
		return
	}

	c.JSON(http.StatusOK, conversations)
}

func (s *Server) createDirectConversation(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		UserID string `json:"user_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	otherUserID, _ := uuid.Parse(req.UserID)

	conv, err := s.MessagingService.CreateDirectConversation(c.Request.Context(), uid, otherUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create conversation"})
		return
	}

	c.JSON(http.StatusCreated, conv)
}

func (s *Server) createGroupConversation(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		Name      string   `json:"name" binding:"required"`
		MemberIDs []string `json:"member_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	memberUUIDs := make([]uuid.UUID, len(req.MemberIDs))
	for i, id := range req.MemberIDs {
		memberUUIDs[i], _ = uuid.Parse(id)
	}

	conv, err := s.MessagingService.CreateGroupConversation(c.Request.Context(), uid, req.Name, memberUUIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create group"})
		return
	}

	c.JSON(http.StatusCreated, conv)
}

func (s *Server) getConversation(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	convID, _ := uuid.Parse(c.Param("id"))

	conv, err := s.MessagingService.GetConversation(c.Request.Context(), convID, uid)
	if err != nil {
		if err == messaging.ErrConversationNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get conversation"})
		return
	}

	c.JSON(http.StatusOK, conv)
}

func (s *Server) getMessages(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	convID, _ := uuid.Parse(c.Param("id"))

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	messages, err := s.MessagingService.GetMessages(c.Request.Context(), convID, uid, limit, offset, nil)
	if err != nil {
		if err == messaging.ErrNotParticipant {
			c.JSON(http.StatusForbidden, gin.H{"error": "not a participant"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get messages"})
		return
	}

	c.JSON(http.StatusOK, messages)
}

func (s *Server) sendMessage(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	convID, _ := uuid.Parse(c.Param("id"))

	var req struct {
		Type      string  `json:"type" binding:"required"`
		Content   []byte  `json:"content" binding:"required"`
		StickerID *string `json:"sticker_id,omitempty"`
		ReplyToID *string `json:"reply_to_id,omitempty"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	msgReq := messaging.SendMessageRequest{
		ConversationID: convID,
		SenderID:       uid,
		Type:           models.MessageType(req.Type),
		Content:        req.Content,
	}

	if req.StickerID != nil {
		stickerUUID, _ := uuid.Parse(*req.StickerID)
		msgReq.StickerID = &stickerUUID
	}
	if req.ReplyToID != nil {
		replyUUID, _ := uuid.Parse(*req.ReplyToID)
		msgReq.ReplyToID = &replyUUID
	}

	msg, err := s.MessagingService.SendMessage(c.Request.Context(), msgReq)
	if err != nil {
		if err == messaging.ErrNotParticipant {
			c.JSON(http.StatusForbidden, gin.H{"error": "not a participant"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}

	c.JSON(http.StatusCreated, msg)
}

func (s *Server) sendTyping(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	convID, _ := uuid.Parse(c.Param("id"))

	var req struct {
		IsTyping bool `json:"is_typing"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := s.MessagingService.BroadcastTyping(c.Request.Context(), convID, uid, req.IsTyping); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send typing"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "ok"})
}

// Message handlers

func (s *Server) markDelivered(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	msgID, _ := uuid.Parse(c.Param("id"))

	if err := s.MessagingService.MarkAsDelivered(c.Request.Context(), msgID, uid); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mark delivered"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "marked as delivered"})
}

func (s *Server) markRead(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	msgID, _ := uuid.Parse(c.Param("id"))

	if err := s.MessagingService.MarkAsRead(c.Request.Context(), msgID, uid); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mark read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "marked as read"})
}

func (s *Server) deleteMessage(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	msgID, _ := uuid.Parse(c.Param("id"))

	if err := s.MessagingService.DeleteMessage(c.Request.Context(), msgID, uid); err != nil {
		if err == messaging.ErrMessageNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete message"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "message deleted"})
}

// Sticker handlers

func (s *Server) getStickerCatalog(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	var official *bool
	if o := c.Query("official"); o != "" {
		v := o == "true"
		official = &v
	}

	packs, err := s.StickersService.GetCatalog(c.Request.Context(), limit, offset, official)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get catalog"})
		return
	}

	c.JSON(http.StatusOK, packs)
}

func (s *Server) searchStickers(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "search query required"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	packs, err := s.StickersService.SearchPacks(c.Request.Context(), query, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}

	c.JSON(http.StatusOK, packs)
}

func (s *Server) getStickerPack(c *gin.Context) {
	packID, _ := uuid.Parse(c.Param("id"))

	pack, err := s.StickersService.GetPack(c.Request.Context(), packID)
	if err != nil {
		if err == stickers.ErrPackNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "pack not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get pack"})
		return
	}

	c.JSON(http.StatusOK, pack)
}

func (s *Server) downloadStickerPack(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	packID, _ := uuid.Parse(c.Param("id"))

	if err := s.StickersService.DownloadPack(c.Request.Context(), uid, packID); err != nil {
		if err == stickers.ErrAlreadyOwned {
			c.JSON(http.StatusConflict, gin.H{"error": "pack already owned"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to download pack"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "pack downloaded"})
}

func (s *Server) removeStickerPack(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)
	packID, _ := uuid.Parse(c.Param("id"))

	if err := s.StickersService.RemovePack(c.Request.Context(), uid, packID); err != nil {
		if err == stickers.ErrNotOwned {
			c.JSON(http.StatusNotFound, gin.H{"error": "pack not owned"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove pack"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "pack removed"})
}

func (s *Server) getUserStickerPacks(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	packs, err := s.StickersService.GetUserPacks(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get packs"})
		return
	}

	c.JSON(http.StatusOK, packs)
}

func (s *Server) reorderStickerPacks(c *gin.Context) {
	userID := getUserID(c)
	uid, _ := uuid.Parse(userID)

	var req struct {
		PackIDs []string `json:"pack_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	packUUIDs := make([]uuid.UUID, len(req.PackIDs))
	for i, id := range req.PackIDs {
		packUUIDs[i], _ = uuid.Parse(id)
	}

	if err := s.StickersService.ReorderPacks(c.Request.Context(), uid, packUUIDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reorder"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "packs reordered"})
}

// Admin sticker handlers

func (s *Server) createStickerPack(c *gin.Context) {
	var req stickers.CreatePackRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	pack, err := s.StickersService.CreatePack(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create pack"})
		return
	}

	c.JSON(http.StatusCreated, pack)
}

func (s *Server) uploadPackCover(c *gin.Context) {
	packID, _ := uuid.Parse(c.Param("id"))

	file, header, err := c.Request.FormFile("cover")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cover file required"})
		return
	}
	defer file.Close()

	coverURL, err := s.StickersService.UploadPackCover(c.Request.Context(), packID, file, header.Size, header.Header.Get("Content-Type"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "upload failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"cover_url": coverURL})
}

func (s *Server) addSticker(c *gin.Context) {
	packID, _ := uuid.Parse(c.Param("id"))

	file, header, err := c.Request.FormFile("sticker")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sticker file required"})
		return
	}
	defer file.Close()

	emoji := c.PostForm("emoji")
	position, _ := strconv.Atoi(c.PostForm("position"))

	sticker, err := s.StickersService.AddSticker(c.Request.Context(), stickers.AddStickerRequest{
		PackID:   packID,
		Emoji:    emoji,
		Position: position,
	}, file, header.Size, header.Header.Get("Content-Type"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add sticker"})
		return
	}

	c.JSON(http.StatusCreated, sticker)
}
