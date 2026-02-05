# Ansible Talk

A secure cross-platform messenger app with end-to-end encryption based on the Signal protocol.

## Features

- **End-to-End Encryption**: Messages are encrypted using the Signal protocol
- **Multi-Platform**: Works on iOS, Android, Web, and Desktop (via Flutter)
- **Contact Management**: Add, edit, block contacts; sync from phone contacts
- **Real-time Messaging**: WebSocket-based instant messaging with delivery/read receipts
- **Sticker Support**: Download and use sticker packs in chats
- **Authentication**: Phone number or email authentication with OTP verification

## Architecture

```
├── backend/                    # Go backend server
│   ├── cmd/server/             # Server entry point
│   ├── internal/
│   │   ├── api/                # REST API & WebSocket handlers
│   │   ├── auth/               # Authentication service
│   │   ├── contacts/           # Contacts management
│   │   ├── crypto/             # Signal protocol keys
│   │   ├── messaging/          # Message handling
│   │   ├── stickers/           # Sticker packs
│   │   ├── storage/            # Database & Redis clients
│   │   └── models/             # Data models
│   └── migrations/             # Database migrations
│
├── mobile/                     # Flutter mobile app
│   ├── lib/
│   │   ├── app/                # App configuration & routing
│   │   ├── core/               # Core services (crypto, network, storage)
│   │   ├── features/           # Feature modules
│   │   │   ├── auth/           # Login, register, OTP verification
│   │   │   ├── contacts/       # Contact list & management
│   │   │   ├── chat/           # Conversations & messaging
│   │   │   └── stickers/       # Sticker picker & store
│   │   └── shared/             # Shared models & widgets
│   └── pubspec.yaml
│
├── docker-compose.yml          # Development infrastructure
└── Makefile                    # Build commands
```

## Tech Stack

### Backend
- **Go** - Server implementation
- **Gin** - HTTP framework
- **PostgreSQL** - Primary database
- **Redis** - Caching, sessions, pub/sub
- **MinIO** - S3-compatible object storage for media

### Mobile
- **Flutter** - Cross-platform UI
- **Riverpod** - State management
- **Dio** - HTTP client
- **sqflite** - Local database
- **libsignal_protocol_dart** - E2E encryption

## Getting Started

### Prerequisites

- Docker & Docker Compose
- Go 1.21+
- Flutter 3.10+

### Development Setup

1. **Start infrastructure**:
   ```bash
   make dev
   ```
   This starts PostgreSQL, Redis, and MinIO containers.

2. **Run database migrations**:
   ```bash
   cd backend
   psql -h localhost -U ansible -d ansible_talk -f migrations/001_initial_schema.sql
   ```

3. **Start the backend**:
   ```bash
   make backend
   ```
   Server runs on http://localhost:8080

4. **Run the mobile app**:
   ```bash
   make mobile
   ```

### Configuration

Backend configuration via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_HOST` | `0.0.0.0` | Server bind address |
| `SERVER_PORT` | `8080` | Server port |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `ansible` | Database user |
| `DB_PASSWORD` | `ansible_secret` | Database password |
| `DB_NAME` | `ansible_talk` | Database name |
| `REDIS_HOST` | `localhost` | Redis host |
| `JWT_SECRET` | `change-me` | JWT signing secret |

## API Overview

### Authentication
- `POST /api/v1/auth/otp/send` - Send OTP
- `POST /api/v1/auth/otp/verify` - Verify OTP
- `POST /api/v1/auth/register` - Create account
- `POST /api/v1/auth/login` - Login
- `POST /api/v1/auth/refresh` - Refresh tokens

### Contacts
- `GET /api/v1/contacts` - List contacts
- `POST /api/v1/contacts` - Add contact
- `PUT /api/v1/contacts/:id` - Update contact
- `DELETE /api/v1/contacts/:id` - Delete contact
- `POST /api/v1/contacts/:id/block` - Block contact

### Conversations
- `GET /api/v1/conversations` - List conversations
- `POST /api/v1/conversations/direct` - Create 1:1 chat
- `POST /api/v1/conversations/group` - Create group chat
- `GET /api/v1/conversations/:id/messages` - Get messages
- `POST /api/v1/conversations/:id/messages` - Send message

### Stickers
- `GET /api/v1/stickers/catalog` - Browse sticker store
- `GET /api/v1/stickers/my-packs` - User's downloaded packs
- `POST /api/v1/stickers/packs/:id/download` - Download pack
- `DELETE /api/v1/stickers/packs/:id` - Remove pack

### WebSocket
Connect to `ws://localhost:8080/api/v1/ws?token=<access_token>`

Message types:
- `new_message` - New incoming message
- `typing` - Typing indicator
- `presence` - User online status
- `ack` - Delivery/read receipts

## Security

- All messages are end-to-end encrypted using the Signal protocol
- JWT tokens for API authentication
- OTP verification for account security
- Session management with device tracking

## License

MIT License
