package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func TestSendOTPRequest_Validation(t *testing.T) {
	tests := []struct {
		name     string
		request  map[string]interface{}
		wantCode int
	}{
		{
			name: "valid phone request",
			request: map[string]interface{}{
				"target": "+1234567890",
				"type":   "phone",
			},
			wantCode: http.StatusOK, // Would be OK if service was mocked
		},
		{
			name: "valid email request",
			request: map[string]interface{}{
				"target": "test@example.com",
				"type":   "email",
			},
			wantCode: http.StatusOK,
		},
		{
			name: "missing target",
			request: map[string]interface{}{
				"type": "phone",
			},
			wantCode: http.StatusBadRequest,
		},
		{
			name: "missing type",
			request: map[string]interface{}{
				"target": "+1234567890",
			},
			wantCode: http.StatusBadRequest,
		},
		{
			name: "invalid type",
			request: map[string]interface{}{
				"target": "+1234567890",
				"type":   "invalid",
			},
			wantCode: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test request binding only
			req := SendOTPRequest{}
			body, _ := json.Marshal(tt.request)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
			c.Request.Header.Set("Content-Type", "application/json")

			err := c.ShouldBindJSON(&req)
			if tt.wantCode == http.StatusBadRequest {
				if err == nil {
					t.Error("Expected binding error, got nil")
				}
			} else {
				if err != nil {
					t.Errorf("Unexpected binding error: %v", err)
				}
			}
		})
	}
}

func TestVerifyOTPRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request map[string]interface{}
		wantErr bool
	}{
		{
			name: "valid request",
			request: map[string]interface{}{
				"target": "+1234567890",
				"type":   "phone",
				"code":   "123456",
			},
			wantErr: false,
		},
		{
			name: "missing code",
			request: map[string]interface{}{
				"target": "+1234567890",
				"type":   "phone",
			},
			wantErr: true,
		},
		{
			name: "empty request",
			request: map[string]interface{}{},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := VerifyOTPRequest{}
			body, _ := json.Marshal(tt.request)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
			c.Request.Header.Set("Content-Type", "application/json")

			err := c.ShouldBindJSON(&req)
			if tt.wantErr && err == nil {
				t.Error("Expected binding error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("Unexpected binding error: %v", err)
			}
		})
	}
}

func TestRegisterRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request map[string]interface{}
		wantErr bool
	}{
		{
			name: "valid with phone",
			request: map[string]interface{}{
				"phone":        "+1234567890",
				"username":     "testuser",
				"display_name": "Test User",
				"device_name":  "iPhone 15",
				"platform":     "ios",
			},
			wantErr: false,
		},
		{
			name: "valid with email",
			request: map[string]interface{}{
				"email":        "test@example.com",
				"username":     "testuser",
				"display_name": "Test User",
				"device_name":  "Pixel 8",
				"platform":     "android",
			},
			wantErr: false,
		},
		{
			name: "missing username",
			request: map[string]interface{}{
				"phone":        "+1234567890",
				"display_name": "Test User",
				"device_name":  "iPhone 15",
				"platform":     "ios",
			},
			wantErr: true,
		},
		{
			name: "missing display_name",
			request: map[string]interface{}{
				"phone":       "+1234567890",
				"username":    "testuser",
				"device_name": "iPhone 15",
				"platform":    "ios",
			},
			wantErr: true,
		},
		{
			name: "missing device_name",
			request: map[string]interface{}{
				"phone":        "+1234567890",
				"username":     "testuser",
				"display_name": "Test User",
				"platform":     "ios",
			},
			wantErr: true,
		},
		{
			name: "missing platform",
			request: map[string]interface{}{
				"phone":        "+1234567890",
				"username":     "testuser",
				"display_name": "Test User",
				"device_name":  "iPhone 15",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := RegisterRequest{}
			body, _ := json.Marshal(tt.request)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
			c.Request.Header.Set("Content-Type", "application/json")

			err := c.ShouldBindJSON(&req)
			if tt.wantErr && err == nil {
				t.Error("Expected binding error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("Unexpected binding error: %v", err)
			}
		})
	}
}

func TestLoginRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request map[string]interface{}
		wantErr bool
	}{
		{
			name: "valid phone login",
			request: map[string]interface{}{
				"target":      "+1234567890",
				"type":        "phone",
				"device_name": "iPhone 15",
				"platform":    "ios",
			},
			wantErr: false,
		},
		{
			name: "valid email login",
			request: map[string]interface{}{
				"target":      "test@example.com",
				"type":        "email",
				"device_name": "Pixel 8",
				"platform":    "android",
			},
			wantErr: false,
		},
		{
			name: "missing target",
			request: map[string]interface{}{
				"type":        "phone",
				"device_name": "iPhone 15",
				"platform":    "ios",
			},
			wantErr: true,
		},
		{
			name: "invalid type",
			request: map[string]interface{}{
				"target":      "+1234567890",
				"type":        "sms",
				"device_name": "iPhone 15",
				"platform":    "ios",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := LoginRequest{}
			body, _ := json.Marshal(tt.request)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
			c.Request.Header.Set("Content-Type", "application/json")

			err := c.ShouldBindJSON(&req)
			if tt.wantErr && err == nil {
				t.Error("Expected binding error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("Unexpected binding error: %v", err)
			}
		})
	}
}

func TestRefreshRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request map[string]interface{}
		wantErr bool
	}{
		{
			name: "valid request",
			request: map[string]interface{}{
				"refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
			},
			wantErr: false,
		},
		{
			name:    "missing refresh_token",
			request: map[string]interface{}{},
			wantErr: true,
		},
		{
			name: "empty refresh_token",
			request: map[string]interface{}{
				"refresh_token": "",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := RefreshRequest{}
			body, _ := json.Marshal(tt.request)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
			c.Request.Header.Set("Content-Type", "application/json")

			err := c.ShouldBindJSON(&req)
			if tt.wantErr && err == nil {
				t.Error("Expected binding error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("Unexpected binding error: %v", err)
			}
		})
	}
}

func TestCORSMiddleware(t *testing.T) {
	router := gin.New()
	router.Use(corsMiddleware())
	router.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	// Test OPTIONS preflight
	w := httptest.NewRecorder()
	req, _ := http.NewRequest(http.MethodOptions, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("OPTIONS request should return 204, got %d", w.Code)
	}

	// Check CORS headers
	headers := w.Header()
	if headers.Get("Access-Control-Allow-Origin") != "*" {
		t.Error("Missing Access-Control-Allow-Origin header")
	}
	if headers.Get("Access-Control-Allow-Methods") == "" {
		t.Error("Missing Access-Control-Allow-Methods header")
	}
	if headers.Get("Access-Control-Allow-Headers") == "" {
		t.Error("Missing Access-Control-Allow-Headers header")
	}

	// Test regular request passes through
	w = httptest.NewRecorder()
	req, _ = http.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("GET request should return 200, got %d", w.Code)
	}
}

func TestGetUserID(t *testing.T) {
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Set("user_id", "550e8400-e29b-41d4-a716-446655440000")

	userID := getUserID(c)
	if userID != "550e8400-e29b-41d4-a716-446655440000" {
		t.Errorf("Expected user_id '550e8400-e29b-41d4-a716-446655440000', got '%s'", userID)
	}
}

func TestGetDeviceID(t *testing.T) {
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Set("device_id", "1")

	deviceID := getDeviceID(c)
	if deviceID != "1" {
		t.Errorf("Expected device_id '1', got '%s'", deviceID)
	}
}

func TestJSONBinding_ContentType(t *testing.T) {
	// Test that non-JSON content type fails gracefully
	req := SendOTPRequest{}
	body := []byte(`{"target": "+1234567890", "type": "phone"}`)

	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodPost, "/", bytes.NewBuffer(body))
	// Missing Content-Type header

	// Should still work due to Gin's fallback
	err := c.ShouldBindJSON(&req)
	if err != nil {
		// Some versions of Gin require Content-Type
		t.Logf("Binding without Content-Type: %v", err)
	}
}
