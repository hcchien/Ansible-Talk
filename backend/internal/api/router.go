package api

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/ansible-talk/backend/internal/auth"
	"github.com/ansible-talk/backend/internal/config"
	"github.com/ansible-talk/backend/internal/contacts"
	"github.com/ansible-talk/backend/internal/crypto"
	"github.com/ansible-talk/backend/internal/messaging"
	"github.com/ansible-talk/backend/internal/stickers"
	"github.com/ansible-talk/backend/internal/storage"
)

// Server holds all dependencies for the API server
type Server struct {
	Config       *config.Config
	DB           *storage.PostgresDB
	Redis        *storage.RedisClient
	MinIO        *storage.MinIOClient
	AuthService  *auth.Service
	CryptoService *crypto.Service
	ContactsService *contacts.Service
	MessagingService *messaging.Service
	StickersService *stickers.Service
	WSHub        *Hub
}

// NewServer creates a new API server
func NewServer(cfg *config.Config, db *storage.PostgresDB, redis *storage.RedisClient, minio *storage.MinIOClient) *Server {
	authSvc := auth.NewService(db, redis, cfg)
	cryptoSvc := crypto.NewService(db)
	contactsSvc := contacts.NewService(db)
	messagingSvc := messaging.NewService(db, redis)
	stickersSvc := stickers.NewService(db, minio)

	return &Server{
		Config:          cfg,
		DB:              db,
		Redis:           redis,
		MinIO:           minio,
		AuthService:     authSvc,
		CryptoService:   cryptoSvc,
		ContactsService: contactsSvc,
		MessagingService: messagingSvc,
		StickersService: stickersSvc,
		WSHub:           NewHub(redis),
	}
}

// SetupRouter configures all API routes
func (s *Server) SetupRouter() *gin.Engine {
	if s.Config.Server.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(corsMiddleware())

	// Health check
	r.GET("/health", s.healthCheck)

	// API v1
	v1 := r.Group("/api/v1")
	{
		// Auth routes (public)
		authRoutes := v1.Group("/auth")
		{
			authRoutes.POST("/otp/send", s.sendOTP)
			authRoutes.POST("/otp/verify", s.verifyOTP)
			authRoutes.POST("/register", s.register)
			authRoutes.POST("/login", s.login)
			authRoutes.POST("/refresh", s.refreshToken)
		}

		// Protected routes
		protected := v1.Group("")
		protected.Use(s.authMiddleware())
		{
			// User routes
			userRoutes := protected.Group("/users")
			{
				userRoutes.GET("/me", s.getCurrentUser)
				userRoutes.PUT("/me", s.updateCurrentUser)
				userRoutes.POST("/me/avatar", s.uploadAvatar)
				userRoutes.GET("/search", s.searchUsers)
			}

			// Auth management
			protected.POST("/auth/logout", s.logout)
			protected.POST("/auth/logout-all", s.logoutAll)

			// Device routes
			deviceRoutes := protected.Group("/devices")
			{
				deviceRoutes.GET("", s.getDevices)
				deviceRoutes.DELETE("/:id", s.removeDevice)
			}

			// Signal keys routes
			keyRoutes := protected.Group("/keys")
			{
				keyRoutes.POST("/register", s.registerKeys)
				keyRoutes.GET("/bundle/:user_id/:device_id", s.getKeyBundle)
				keyRoutes.GET("/count", s.getPreKeyCount)
				keyRoutes.POST("/prekeys", s.refreshPreKeys)
				keyRoutes.PUT("/signed-prekey", s.updateSignedPreKey)
			}

			// Contact routes
			contactRoutes := protected.Group("/contacts")
			{
				contactRoutes.GET("", s.getContacts)
				contactRoutes.POST("", s.addContact)
				contactRoutes.GET("/:id", s.getContact)
				contactRoutes.PUT("/:id", s.updateContact)
				contactRoutes.DELETE("/:id", s.deleteContact)
				contactRoutes.POST("/:id/block", s.blockContact)
				contactRoutes.POST("/:id/unblock", s.unblockContact)
				contactRoutes.GET("/blocked", s.getBlockedContacts)
				contactRoutes.POST("/sync", s.syncContacts)
			}

			// Conversation routes
			convRoutes := protected.Group("/conversations")
			{
				convRoutes.GET("", s.getConversations)
				convRoutes.POST("/direct", s.createDirectConversation)
				convRoutes.POST("/group", s.createGroupConversation)
				convRoutes.GET("/:id", s.getConversation)
				convRoutes.GET("/:id/messages", s.getMessages)
				convRoutes.POST("/:id/messages", s.sendMessage)
				convRoutes.POST("/:id/typing", s.sendTyping)
			}

			// Message routes
			msgRoutes := protected.Group("/messages")
			{
				msgRoutes.POST("/:id/delivered", s.markDelivered)
				msgRoutes.POST("/:id/read", s.markRead)
				msgRoutes.DELETE("/:id", s.deleteMessage)
			}

			// Sticker routes
			stickerRoutes := protected.Group("/stickers")
			{
				stickerRoutes.GET("/catalog", s.getStickerCatalog)
				stickerRoutes.GET("/search", s.searchStickers)
				stickerRoutes.GET("/packs/:id", s.getStickerPack)
				stickerRoutes.POST("/packs/:id/download", s.downloadStickerPack)
				stickerRoutes.DELETE("/packs/:id", s.removeStickerPack)
				stickerRoutes.GET("/my-packs", s.getUserStickerPacks)
				stickerRoutes.PUT("/my-packs/reorder", s.reorderStickerPacks)
			}

			// Admin sticker routes (for creating packs)
			adminStickerRoutes := protected.Group("/admin/stickers")
			{
				adminStickerRoutes.POST("/packs", s.createStickerPack)
				adminStickerRoutes.POST("/packs/:id/cover", s.uploadPackCover)
				adminStickerRoutes.POST("/packs/:id/stickers", s.addSticker)
			}
		}

		// WebSocket route
		v1.GET("/ws", s.authMiddleware(), s.handleWebSocket)
	}

	return r
}

// Health check handler
func (s *Server) healthCheck(c *gin.Context) {
	ctx := c.Request.Context()

	// Check database
	if err := s.DB.Health(ctx); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  "database connection failed",
		})
		return
	}

	// Check Redis
	if err := s.Redis.Health(ctx); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  "redis connection failed",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":    "healthy",
		"timestamp": time.Now().UTC(),
	})
}

// CORS middleware
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// Auth middleware
func (s *Server) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader("Authorization")
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authorization header required"})
			c.Abort()
			return
		}

		// Remove "Bearer " prefix if present
		if len(token) > 7 && token[:7] == "Bearer " {
			token = token[7:]
		}

		claims, err := s.AuthService.ValidateToken(c.Request.Context(), token)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			c.Abort()
			return
		}

		// Set user info in context
		c.Set("user_id", claims.UserID)
		c.Set("device_id", claims.DeviceID)

		c.Next()
	}
}

// Helper to get user ID from context
func getUserID(c *gin.Context) string {
	userID, _ := c.Get("user_id")
	return userID.(string)
}

// Helper to get device ID from context
func getDeviceID(c *gin.Context) string {
	deviceID, _ := c.Get("device_id")
	return deviceID.(string)
}
