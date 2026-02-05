package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ansible-talk/backend/internal/api"
	"github.com/ansible-talk/backend/internal/config"
	"github.com/ansible-talk/backend/internal/storage"
)

func main() {
	// Load configuration
	cfg := config.Load()

	log.Printf("Starting Ansible Talk server in %s mode...", cfg.Server.Environment)

	// Initialize PostgreSQL
	log.Println("Connecting to PostgreSQL...")
	db, err := storage.NewPostgresDB(cfg.Database)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()
	log.Println("PostgreSQL connected successfully")

	// Initialize Redis
	log.Println("Connecting to Redis...")
	redis, err := storage.NewRedisClient(cfg.Redis)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	defer redis.Close()
	log.Println("Redis connected successfully")

	// Initialize MinIO
	log.Println("Connecting to MinIO...")
	minio, err := storage.NewMinIOClient(cfg.MinIO)
	if err != nil {
		log.Fatalf("Failed to connect to MinIO: %v", err)
	}

	// Ensure buckets exist
	if err := minio.EnsureBuckets(context.Background()); err != nil {
		log.Printf("Warning: Failed to ensure buckets: %v", err)
	}
	log.Println("MinIO connected successfully")

	// Create API server
	server := api.NewServer(cfg, db, redis, minio)

	// Start WebSocket hub
	go server.WSHub.Run()

	// Setup router
	router := server.SetupRouter()

	// Create HTTP server
	addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
	httpServer := &http.Server{
		Addr:         addr,
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Server listening on %s", addr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Graceful shutdown with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
