# Installation Guide

This guide provides detailed instructions for setting up Ansible Talk on your development machine.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start with Docker](#quick-start-with-docker)
- [Manual Installation](#manual-installation)
  - [Database Setup](#database-setup)
  - [Redis Setup](#redis-setup)
  - [MinIO Setup](#minio-setup)
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

### For Backend Development

| Software | Version | Installation |
|----------|---------|--------------|
| Rust | 1.70+ | https://rustup.rs/ |
| SQLx CLI | 0.8+ | `cargo install sqlx-cli --no-default-features --features postgres` |

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
cd backend-rs
cp .env.example .env
```

Edit `.env` with your configuration (see [Environment Configuration](#environment-configuration) below).

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
cd backend-rs

# Set DATABASE_URL for sqlx
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/ansible_talk"

# Run migrations
sqlx migrate run
```

### 5. Start the Backend

```bash
cd backend-rs
cargo run --release
```

The server will start on http://localhost:8080

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
CREATE USER postgres WITH PASSWORD 'postgres';
CREATE DATABASE ansible_talk OWNER postgres;
GRANT ALL PRIVILEGES ON DATABASE ansible_talk TO postgres;

# Exit
\q
```

#### Run Migrations

```bash
cd backend-rs

# Set DATABASE_URL
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/ansible_talk"

# Run migrations
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

### Rust Backend Setup

#### 1. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

Verify installation:
```bash
rustc --version
cargo --version
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

Edit `.env` with your settings:

```env
# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
ENVIRONMENT=development

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=ansible_talk
DB_SSL_MODE=disable
DB_MAX_CONNS=25

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# MinIO Configuration
MINIO_ENDPOINT=http://localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_USE_SSL=false
MINIO_REGION=us-east-1
MINIO_PUBLIC_URL=http://localhost:9000

# JWT Configuration
JWT_SECRET=your-super-secret-key-change-in-production
JWT_ACCESS_TOKEN_TTL=900
JWT_REFRESH_TOKEN_TTL=604800
JWT_ISSUER=ansible-talk

# OTP Configuration
OTP_LENGTH=6
OTP_TTL=300
OTP_MAX_ATTEMPTS=3
```

#### 4. Set DATABASE_URL for SQLx

```bash
export DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
```

Or add to your shell profile:
```bash
echo 'export DATABASE_URL="postgres://postgres:postgres@localhost:5432/ansible_talk"' >> ~/.bashrc
source ~/.bashrc
```

#### 5. Run Migrations

```bash
cd backend-rs
sqlx migrate run
```

This creates all necessary database tables with the schema defined in `migrations/`.

#### 6. Build and Run

**Development mode:**
```bash
cargo run
```

**Production mode:**
```bash
cargo build --release
./target/release/server
```

**With logging:**
```bash
RUST_LOG=info cargo run
# or for debug logging
RUST_LOG=debug cargo run
```

The server will start on http://localhost:8080

### Flutter Mobile App Setup

#### 1. Install Flutter

Follow the official guide: https://flutter.dev/docs/get-started/install

Verify installation:
```bash
flutter doctor
```

Ensure all checks pass (or at least the ones relevant to your target platform).

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

**For Android emulator**, use `10.0.2.2` instead of `localhost`:
```dart
static const String baseUrl = 'http://10.0.2.2:8080/api/v1';
```

**For iOS simulator**, `localhost` works fine.

**For physical devices**, use your machine's local IP:
```dart
static const String baseUrl = 'http://192.168.1.100:8080/api/v1';
```

Similarly, update the WebSocket URL in `lib/core/network/websocket_client.dart`:
```dart
static const String wsUrl = 'ws://localhost:8080/api/v1/ws';
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

## Environment Configuration

### Complete `.env` Reference

```env
# ===================
# Server Configuration
# ===================
SERVER_HOST=0.0.0.0          # Bind address
SERVER_PORT=8080             # Server port
ENVIRONMENT=development      # development | production

# ===================
# Database (PostgreSQL)
# ===================
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=ansible_talk
DB_SSL_MODE=disable          # disable | require | verify-full
DB_MAX_CONNS=25              # Connection pool size

# ===================
# Redis
# ===================
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=              # Leave empty for no auth
REDIS_DB=0

# ===================
# MinIO / S3
# ===================
MINIO_ENDPOINT=http://localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_USE_SSL=false
MINIO_REGION=us-east-1
MINIO_PUBLIC_URL=http://localhost:9000

# Bucket names (created automatically)
MINIO_STICKERS_BUCKET=stickers
MINIO_AVATARS_BUCKET=avatars
MINIO_ATTACHMENTS_BUCKET=attachments

# ===================
# JWT Authentication
# ===================
JWT_SECRET=change-this-to-a-secure-random-string
JWT_ACCESS_TOKEN_TTL=900     # 15 minutes in seconds
JWT_REFRESH_TOKEN_TTL=604800 # 7 days in seconds
JWT_ISSUER=ansible-talk

# ===================
# OTP Configuration
# ===================
OTP_LENGTH=6
OTP_TTL=300                  # 5 minutes in seconds
OTP_MAX_ATTEMPTS=3

# ===================
# SMS (Twilio) - Optional
# ===================
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_FROM_NUMBER=

# ===================
# Email (SendGrid) - Optional
# ===================
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=
EMAIL_FROM=noreply@yourdomain.com
```

## Production Deployment

### Security Checklist

- [ ] Use strong, randomly generated `JWT_SECRET` (256-bit)
- [ ] Enable `DB_SSL_MODE=require` for database connections
- [ ] Enable `MINIO_USE_SSL=true` for object storage
- [ ] Use managed services for PostgreSQL and Redis
- [ ] Set `ENVIRONMENT=production`
- [ ] Configure proper firewall rules
- [ ] Set up TLS/SSL certificates for the API

### Environment Configuration (Production)

```env
ENVIRONMENT=production

# Use strong secrets
JWT_SECRET=<generate-with: openssl rand -hex 32>

# Enable SSL for database
DB_SSL_MODE=require

# Use production MinIO/S3
MINIO_USE_SSL=true
MINIO_ENDPOINT=s3.amazonaws.com
```

### Database

- Use managed PostgreSQL (AWS RDS, Google Cloud SQL, Azure Database)
- Enable SSL connections
- Configure connection pooling (PgBouncer recommended)
- Set up automated backups
- Enable point-in-time recovery

### Redis

- Use managed Redis (AWS ElastiCache, Redis Cloud, Upstash)
- Enable authentication (`REDIS_PASSWORD`)
- Configure persistence (RDB + AOF)
- Set up replication for high availability

### Object Storage

- Use S3 or S3-compatible storage (AWS S3, Cloudflare R2, MinIO)
- Configure proper bucket policies
- Enable server-side encryption
- Set up CDN (CloudFront, Cloudflare) for content delivery
- Configure CORS for web access

### Backend Deployment

**Using Docker:**
```bash
# Build the image
docker build -t ansible-talk-backend -f backend-rs/Dockerfile .

# Run the container
docker run -d \
  --name ansible-talk \
  -p 8080:8080 \
  --env-file backend-rs/.env \
  ansible-talk-backend
```

**Example Dockerfile for Rust backend:**
```dockerfile
FROM rust:1.75 as builder
WORKDIR /app
COPY backend-rs/ .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/server /usr/local/bin/
CMD ["server"]
```

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
- Verify username and password in `.env`
- Check `pg_hba.conf` for authentication method
- Ensure the user has access to the database

**Error:** `database "ansible_talk" does not exist`
```bash
sudo -u postgres createdb ansible_talk
```

### Redis Connection Issues

**Error:** `NOAUTH Authentication required`
- Set `REDIS_PASSWORD` in `.env`
- Or disable Redis authentication for development

**Error:** `Connection refused`
- Ensure Redis is running: `redis-cli ping`
- Check host and port configuration

### MinIO Issues

**Error:** `Access Denied`
- Verify access key and secret key
- Check bucket policies
- Ensure buckets exist

**Error:** `Bucket does not exist`
```bash
mc mb local/stickers
mc mb local/avatars
mc mb local/attachments
```

### Rust Backend Issues

**Error:** `sqlx prepare failed`
```bash
# Ensure database is running and configured
export DATABASE_URL="postgres://postgres:postgres@localhost/ansible_talk"
cargo sqlx prepare
```

**Error:** `migration failed`
```bash
# Check migration status
sqlx migrate info

# Revert and retry
sqlx migrate revert
sqlx migrate run
```

**Error:** `cannot find -lpq`
```bash
# Install PostgreSQL development libraries
# macOS
brew install libpq

# Ubuntu
sudo apt install libpq-dev
```

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

## Getting Help

- Open an issue on GitHub
- Check existing issues for solutions
- Review the logs for error messages

```bash
# Rust backend logs with debug output
RUST_LOG=debug cargo run 2>&1 | tee server.log

# Flutter logs
flutter run --verbose

# Check database logs
tail -f /var/log/postgresql/postgresql-14-main.log
```

## Verification

After installation, verify everything works:

1. **Backend health check:**
   ```bash
   curl http://localhost:8080/health
   # Should return: {"status":"ok"}
   ```

2. **Database connection:**
   ```bash
   psql -h localhost -U postgres -d ansible_talk -c "SELECT 1"
   ```

3. **Redis connection:**
   ```bash
   redis-cli ping
   # Should return: PONG
   ```

4. **MinIO connection:**
   ```bash
   mc ls local/
   # Should list the buckets
   ```
