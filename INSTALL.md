# Installation Guide

This guide provides detailed instructions for setting up Ansible Talk on your development machine.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start with Docker](#quick-start-with-docker)
- [Manual Installation](#manual-installation)
  - [Database Setup](#database-setup)
  - [Redis Setup](#redis-setup)
  - [MinIO Setup](#minio-setup)
  - [Go Backend Setup](#go-backend-setup)
  - [Rust Backend Setup](#rust-backend-setup)
  - [Flutter Mobile App Setup](#flutter-mobile-app-setup)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Docker | 20.10+ | Container runtime |
| Docker Compose | 2.0+ | Multi-container orchestration |
| Git | 2.30+ | Version control |

### For Go Backend Development

| Software | Version | Installation |
|----------|---------|--------------|
| Go | 1.21+ | https://golang.org/dl/ |

### For Rust Backend Development

| Software | Version | Installation |
|----------|---------|--------------|
| Rust | 1.70+ | https://rustup.rs/ |
| SQLx CLI | 0.7+ | `cargo install sqlx-cli` |

### For Mobile Development

| Software | Version | Installation |
|----------|---------|--------------|
| Flutter | 3.10+ | https://flutter.dev/docs/get-started/install |
| Android Studio | Latest | For Android development |
| Xcode | 14+ | For iOS development (macOS only) |

## Quick Start with Docker

The fastest way to get started is using Docker Compose.

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/ansible-talk.git
cd ansible-talk
```

### 2. Create Environment File

```bash
# For Go backend
cp backend/.env.example backend/.env

# For Rust backend
cp backend-rs/.env.example backend-rs/.env
```

### 3. Start Infrastructure Services

```bash
docker-compose up -d
```

This starts:
- PostgreSQL on port 5432
- Redis on port 6379
- MinIO on port 9000 (API) and 9001 (Console)

### 4. Initialize the Database

```bash
# For Go backend
cd backend
go run cmd/migrate/main.go up

# For Rust backend
cd backend-rs
sqlx migrate run
```

### 5. Start the Backend

```bash
# Go backend
cd backend
go run cmd/server/main.go

# OR Rust backend
cd backend-rs
cargo run
```

### 6. Run the Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

## Manual Installation

### Database Setup

#### PostgreSQL Installation

**macOS (Homebrew):**
```bash
brew install postgresql@14
brew services start postgresql@14
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**Windows:**
Download from https://www.postgresql.org/download/windows/

#### Create Database and User

```bash
# Connect to PostgreSQL
sudo -u postgres psql

# Create user and database
CREATE USER ansible WITH PASSWORD 'ansible_secret';
CREATE DATABASE ansible_talk OWNER ansible;
GRANT ALL PRIVILEGES ON DATABASE ansible_talk TO ansible;

# Exit
\q
```

#### Run Migrations

**Go Backend:**
```bash
cd backend
psql -h localhost -U ansible -d ansible_talk -f migrations/001_initial_schema.sql
```

**Rust Backend:**
```bash
cd backend-rs
sqlx migrate run
```

### Redis Setup

#### Installation

**macOS (Homebrew):**
```bash
brew install redis
brew services start redis
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install redis-server
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

**Windows:**
Download from https://github.com/microsoftarchive/redis/releases

#### Verify Installation

```bash
redis-cli ping
# Should return: PONG
```

### MinIO Setup

#### Using Docker (Recommended)

```bash
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"
```

#### Manual Installation

**macOS (Homebrew):**
```bash
brew install minio/stable/minio
minio server ~/minio-data --console-address ":9001"
```

**Linux:**
```bash
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
./minio server ~/minio-data --console-address ":9001"
```

#### Create Buckets

Access MinIO Console at http://localhost:9001 (login: minioadmin/minioadmin)

Create the following buckets:
- `stickers`
- `avatars`
- `attachments`

Or via CLI:
```bash
# Install MinIO client
brew install minio/stable/mc  # macOS
# or download from https://min.io/download

# Configure client
mc alias set local http://localhost:9000 minioadmin minioadmin

# Create buckets
mc mb local/stickers
mc mb local/avatars
mc mb local/attachments

# Set public read policy (optional, for development)
mc anonymous set download local/stickers
mc anonymous set download local/avatars
```

### Go Backend Setup

#### 1. Install Go

Download from https://golang.org/dl/ or use a package manager:

```bash
# macOS
brew install go

# Ubuntu
sudo apt install golang-go
```

#### 2. Configure Environment

```bash
cd backend
cp .env.example .env
```

Edit `.env` with your settings:
```env
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
ENVIRONMENT=development

DB_HOST=localhost
DB_PORT=5432
DB_USER=ansible
DB_PASSWORD=ansible_secret
DB_NAME=ansible_talk

REDIS_HOST=localhost
REDIS_PORT=6379

MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin

JWT_SECRET=your-super-secret-key-change-in-production
```

#### 3. Install Dependencies

```bash
go mod download
```

#### 4. Run the Server

```bash
go run cmd/server/main.go
```

The server will start on http://localhost:8080

### Rust Backend Setup

#### 1. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

#### 2. Install SQLx CLI

```bash
cargo install sqlx-cli --no-default-features --features postgres
```

#### 3. Configure Environment

```bash
cd backend-rs
cp .env.example .env
```

Edit `.env` with your settings (same as Go backend).

#### 4. Run Migrations

```bash
sqlx migrate run
```

#### 5. Build and Run

```bash
# Development
cargo run

# Production
cargo build --release
./target/release/server
```

### Flutter Mobile App Setup

#### 1. Install Flutter

Follow the official guide: https://flutter.dev/docs/get-started/install

Verify installation:
```bash
flutter doctor
```

#### 2. Install Dependencies

```bash
cd mobile
flutter pub get
```

#### 3. Configure API Endpoint

Edit `lib/core/network/api_client.dart`:
```dart
static const String baseUrl = 'http://localhost:8080/api/v1';
```

For Android emulator, use `10.0.2.2` instead of `localhost`:
```dart
static const String baseUrl = 'http://10.0.2.2:8080/api/v1';
```

For iOS simulator, `localhost` works fine.

For physical devices, use your machine's local IP:
```dart
static const String baseUrl = 'http://192.168.1.100:8080/api/v1';
```

#### 4. Run the App

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Run on all connected devices
flutter run -d all
```

#### 5. Build for Release

**Android:**
```bash
flutter build apk --release
# or for app bundle
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

## Production Deployment

### Environment Configuration

For production, ensure you set:

```env
ENVIRONMENT=production

# Use strong secrets
JWT_SECRET=<generate-a-256-bit-random-key>

# Enable SSL for database
DB_SSL_MODE=require

# Use production MinIO/S3
MINIO_USE_SSL=true
MINIO_ENDPOINT=s3.amazonaws.com
```

### Database

- Use managed PostgreSQL (AWS RDS, Google Cloud SQL, etc.)
- Enable SSL connections
- Configure connection pooling
- Set up automated backups

### Redis

- Use managed Redis (AWS ElastiCache, Redis Cloud, etc.)
- Enable authentication
- Configure persistence

### Object Storage

- Use S3 or S3-compatible storage
- Configure proper bucket policies
- Enable server-side encryption
- Set up CDN for content delivery

### Backend Deployment

**Docker:**
```bash
# Build
docker build -t ansible-talk-backend ./backend

# Run
docker run -d \
  --name ansible-talk \
  -p 8080:8080 \
  --env-file .env \
  ansible-talk-backend
```

**Kubernetes:**
See `deploy/kubernetes/` for example manifests.

### Mobile App Distribution

- **Android**: Google Play Store or direct APK distribution
- **iOS**: Apple App Store or TestFlight

## Troubleshooting

### Database Connection Issues

**Error:** `connection refused`
- Ensure PostgreSQL is running: `sudo systemctl status postgresql`
- Check the host and port in `.env`
- Verify firewall allows connections on port 5432

**Error:** `authentication failed`
- Verify username and password
- Check `pg_hba.conf` for authentication method

### Redis Connection Issues

**Error:** `NOAUTH Authentication required`
- Set `REDIS_PASSWORD` in `.env`
- Or disable Redis authentication for development

### MinIO Issues

**Error:** `Access Denied`
- Verify access key and secret key
- Check bucket policies
- Ensure buckets exist

### Flutter Issues

**Error:** `Unable to find a target platform`
```bash
flutter clean
flutter pub get
```

**Error:** `Gradle build failed`
```bash
cd android
./gradlew clean
cd ..
flutter run
```

**Error:** `CocoaPods not installed`
```bash
sudo gem install cocoapods
cd ios
pod install
```

### Port Already in Use

```bash
# Find process using port 8080
lsof -i :8080

# Kill the process
kill -9 <PID>
```

### Common Go Errors

**Error:** `go.mod file not found`
```bash
go mod init github.com/ansible-talk/backend
go mod tidy
```

### Common Rust Errors

**Error:** `sqlx prepare failed`
```bash
# Ensure database is running and configured
export DATABASE_URL="postgres://ansible:ansible_secret@localhost/ansible_talk"
cargo sqlx prepare
```

## Getting Help

- Open an issue on GitHub
- Check existing issues for solutions
- Review the logs for error messages

```bash
# Go backend logs
go run cmd/server/main.go 2>&1 | tee server.log

# Rust backend logs
RUST_LOG=debug cargo run 2>&1 | tee server.log

# Flutter logs
flutter run --verbose
```
