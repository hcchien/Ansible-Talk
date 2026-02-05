.PHONY: help dev dev-down backend mobile test clean migrate

# Default target
help:
	@echo "Ansible Talk - Messenger App"
	@echo ""
	@echo "Usage:"
	@echo "  make dev          - Start development infrastructure (Docker)"
	@echo "  make dev-down     - Stop development infrastructure"
	@echo "  make backend      - Run Go backend server"
	@echo "  make mobile       - Run Flutter mobile app"
	@echo "  make test         - Run all tests"
	@echo "  make test-backend - Run backend tests"
	@echo "  make test-mobile  - Run mobile tests"
	@echo "  make migrate      - Run database migrations"
	@echo "  make clean        - Clean build artifacts"
	@echo ""

# Development infrastructure
dev:
	docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Development infrastructure is ready!"
	@echo "  - PostgreSQL: localhost:5432"
	@echo "  - Redis: localhost:6379"
	@echo "  - MinIO: localhost:9000 (Console: localhost:9001)"

dev-down:
	docker-compose down

dev-logs:
	docker-compose logs -f

# Backend
backend:
	cd backend && go run cmd/server/main.go

backend-build:
	cd backend && go build -o bin/server cmd/server/main.go

# Mobile
mobile:
	cd mobile && flutter run

mobile-build-android:
	cd mobile && flutter build apk --release

mobile-build-ios:
	cd mobile && flutter build ios --release

mobile-build-web:
	cd mobile && flutter build web --release

# Testing
test: test-backend test-mobile

test-backend:
	cd backend && go test -v ./...

test-mobile:
	cd mobile && flutter test

# Database
migrate:
	cd backend && go run cmd/migrate/main.go up

migrate-down:
	cd backend && go run cmd/migrate/main.go down

# Clean
clean:
	rm -rf backend/bin
	cd mobile && flutter clean

# Dependencies
deps-backend:
	cd backend && go mod tidy

deps-mobile:
	cd mobile && flutter pub get

deps: deps-backend deps-mobile
