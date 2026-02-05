package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"github.com/ansible-talk/backend/internal/storage"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins in development
	},
}

// Hub maintains the set of active clients
type Hub struct {
	clients    map[string]*Client
	register   chan *Client
	unregister chan *Client
	redis      *storage.RedisClient
	mu         sync.RWMutex
}

// Client represents a WebSocket client
type Client struct {
	hub      *Hub
	conn     *websocket.Conn
	userID   string
	deviceID string
	send     chan []byte
}

// NewHub creates a new Hub
func NewHub(redis *storage.RedisClient) *Hub {
	return &Hub{
		clients:    make(map[string]*Client),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		redis:      redis,
	}
}

// Run starts the hub
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			key := client.userID + ":" + client.deviceID
			h.clients[key] = client
			h.mu.Unlock()

			// Update presence
			ctx := context.Background()
			_ = h.redis.SetUserPresence(ctx, client.userID, "online", 5*time.Minute)

			log.Printf("Client connected: %s", key)

		case client := <-h.unregister:
			h.mu.Lock()
			key := client.userID + ":" + client.deviceID
			if _, ok := h.clients[key]; ok {
				delete(h.clients, key)
				close(client.send)
			}
			h.mu.Unlock()

			// Update presence
			ctx := context.Background()
			_ = h.redis.SetUserPresence(ctx, client.userID, "offline", 5*time.Minute)

			log.Printf("Client disconnected: %s", key)
		}
	}
}

// SendToUser sends a message to all devices of a user
func (h *Hub) SendToUser(userID string, message []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for key, client := range h.clients {
		if client.userID == userID {
			select {
			case client.send <- message:
			default:
				log.Printf("Failed to send to client: %s", key)
			}
		}
	}
}

// SendToDevice sends a message to a specific device
func (h *Hub) SendToDevice(userID, deviceID string, message []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	key := userID + ":" + deviceID
	if client, ok := h.clients[key]; ok {
		select {
		case client.send <- message:
		default:
			log.Printf("Failed to send to client: %s", key)
		}
	}
}

// handleWebSocket handles WebSocket connections
func (s *Server) handleWebSocket(c *gin.Context) {
	userID := getUserID(c)
	deviceID := getDeviceID(c)

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	client := &Client{
		hub:      s.WSHub,
		conn:     conn,
		userID:   userID,
		deviceID: deviceID,
		send:     make(chan []byte, 256),
	}

	s.WSHub.register <- client

	// Start goroutines for reading and writing
	go client.writePump()
	go client.readPump(s)

	// Subscribe to Redis channel for this user
	go client.subscribeToRedis(s.Redis)
}

// readPump pumps messages from the WebSocket connection to the hub
func (c *Client) readPump(s *Server) {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(512 * 1024) // 512KB max message size
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		// Handle incoming message
		c.handleMessage(s, message)
	}
}

// writePump pumps messages from the hub to the WebSocket connection
func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued messages to the current WebSocket message
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}

			// Refresh presence
			ctx := context.Background()
			_ = c.hub.redis.SetUserPresence(ctx, c.userID, "online", 5*time.Minute)
		}
	}
}

// subscribeToRedis subscribes to Redis pub/sub for this user
func (c *Client) subscribeToRedis(redis *storage.RedisClient) {
	ctx := context.Background()
	pubsub := redis.SubscribeMessages(ctx, c.userID)
	defer pubsub.Close()

	ch := pubsub.Channel()
	for msg := range ch {
		select {
		case c.send <- []byte(msg.Payload):
		default:
			// Channel full, skip message
		}
	}
}

// WSIncomingMessage represents an incoming WebSocket message
type WSIncomingMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// handleMessage processes incoming WebSocket messages
func (c *Client) handleMessage(s *Server, data []byte) {
	var msg WSIncomingMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Printf("Failed to parse WebSocket message: %v", err)
		return
	}

	ctx := context.Background()
	userID, _ := uuid.Parse(c.userID)

	switch msg.Type {
	case "ping":
		// Respond with pong
		response, _ := json.Marshal(map[string]string{"type": "pong"})
		c.send <- response

	case "typing":
		var payload struct {
			ConversationID string `json:"conversation_id"`
			IsTyping       bool   `json:"is_typing"`
		}
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return
		}
		convID, _ := uuid.Parse(payload.ConversationID)
		s.MessagingService.BroadcastTyping(ctx, convID, userID, payload.IsTyping)

	case "presence":
		var payload struct {
			Status string `json:"status"`
		}
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return
		}
		s.MessagingService.UpdatePresence(ctx, userID, payload.Status)

	case "ack":
		// Message acknowledgment
		var payload struct {
			MessageID string `json:"message_id"`
			Type      string `json:"type"` // "delivered" or "read"
		}
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return
		}
		msgID, _ := uuid.Parse(payload.MessageID)
		if payload.Type == "read" {
			s.MessagingService.MarkAsRead(ctx, msgID, userID)
		} else {
			s.MessagingService.MarkAsDelivered(ctx, msgID, userID)
		}

	default:
		log.Printf("Unknown WebSocket message type: %s", msg.Type)
	}
}
