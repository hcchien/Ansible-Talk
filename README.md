# Ansible Talk

A secure, end-to-end encrypted messaging application built with the Signal Protocol. Features a Flutter mobile client and a high-performance Rust backend.

## Features

- **End-to-End Encryption**: Uses the Signal Protocol (X3DH key exchange + Double Ratchet) for secure messaging
- **Real-time Messaging**: WebSocket-based communication for instant message delivery
- **Cross-Platform Mobile App**: Flutter-based client for iOS and Android
- **High-Performance Backend**: Built with Rust and Axum for speed and safety
- **Rich Messaging**: Text, images, videos, audio, files, and stickers
- **Group Chats**: Create and manage group conversations
- **Contact Management**: Add, block, and organize contacts
- **Typing Indicators**: Real-time typing status
- **Read Receipts**: Message delivery and read confirmations
- **Presence System**: Online/offline/away status tracking
- **Sticker Store**: Download and use sticker packs

## Architecture

```
ansible-talk/
├── mobile/                 # Flutter mobile application
│   ├── lib/
│   │   ├── core/          # Core functionality (crypto, network, storage)
│   │   ├── features/      # Feature modules (auth, chat, contacts, stickers)
│   │   └── shared/        # Shared models and widgets
│   └── test/              # Unit and widget tests
├── backend-rs/            # Rust backend (primary)
│   ├── src/
│   │   ├── api/           # Axum handlers, middleware, router
│   │   ├── models/        # Data models
│   │   ├── services/      # Business logic (auth, crypto, messaging, etc.)
│   │   └── storage/       # Redis and MinIO clients
│   └── migrations/        # SQLx database migrations
├── backend/               # Go backend (legacy)
│   └── internal/          # Go implementation
└── docs/                  # Additional documentation
```

## Tech Stack

### Mobile (Flutter)
| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.10+ |
| State Management | Riverpod |
| Navigation | Go Router |
| HTTP Client | Dio |
| WebSocket | web_socket_channel |
| Local Database | SQLite (sqflite) |
| Secure Storage | flutter_secure_storage |
| Encryption | libsignal_protocol_dart |

### Backend (Rust)
| Component | Technology |
|-----------|------------|
| Web Framework | Axum |
| Database | PostgreSQL (SQLx) |
| Cache | Redis |
| Object Storage | AWS SDK (S3-compatible) |
| Auth | JWT (jsonwebtoken) |
| Async Runtime | Tokio |
| Password Hashing | bcrypt |
| Serialization | serde |

## Quick Start

For detailed installation instructions, see [INSTALL.md](INSTALL.md).

### Prerequisites
- Flutter 3.10+
- Rust 1.70+
- PostgreSQL 14+
- Redis 7+
- MinIO (or S3-compatible storage)
- Docker & Docker Compose (recommended)

### Using Docker (Recommended)

```bash
# Start infrastructure services
docker-compose up -d

# Run database migrations
cd backend-rs
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/ansible_talk"
sqlx migrate run

# Start the backend
cargo run --release
```

### Manual Setup

**1. Start the Rust Backend:**
```bash
cd backend-rs
cp .env.example .env
# Edit .env with your configuration
cargo run --release
```

**3. Run the Mobile App:**
```bash
cd mobile
flutter pub get
flutter run
```

## API Reference

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/otp/send` | Send OTP to phone/email |
| POST | `/api/v1/auth/otp/verify` | Verify OTP code |
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/login` | Login existing user |
| POST | `/api/v1/auth/logout` | Logout and invalidate tokens |
| POST | `/api/v1/auth/refresh` | Refresh access token |

### Users
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/users/me` | Get current user profile |
| PUT | `/api/v1/users/me` | Update profile |
| GET | `/api/v1/users/search` | Search users by name/phone/email |

### Contacts
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/contacts` | List all contacts |
| POST | `/api/v1/contacts` | Add new contact |
| GET | `/api/v1/contacts/:id` | Get contact details |
| PUT | `/api/v1/contacts/:id` | Update contact |
| DELETE | `/api/v1/contacts/:id` | Remove contact |
| POST | `/api/v1/contacts/:id/block` | Block contact |
| POST | `/api/v1/contacts/:id/unblock` | Unblock contact |
| GET | `/api/v1/contacts/blocked` | List blocked contacts |
| POST | `/api/v1/contacts/sync` | Sync phone contacts |

### Conversations
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/conversations` | List conversations |
| POST | `/api/v1/conversations/direct` | Create 1:1 conversation |
| POST | `/api/v1/conversations/group` | Create group conversation |
| GET | `/api/v1/conversations/:id` | Get conversation details |
| GET | `/api/v1/conversations/:id/messages` | Get messages |
| POST | `/api/v1/conversations/:id/messages` | Send message |
| POST | `/api/v1/conversations/:id/typing` | Send typing indicator |

### Messages
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/messages/:id/delivered` | Mark as delivered |
| POST | `/api/v1/messages/:id/read` | Mark as read |
| DELETE | `/api/v1/messages/:id` | Delete message |

### Signal Keys
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/keys/register` | Register device keys |
| GET | `/api/v1/keys/bundle/:userId/:deviceId` | Get key bundle |
| GET | `/api/v1/keys/count` | Get pre-key count |
| POST | `/api/v1/keys/prekeys` | Refresh pre-keys |
| PUT | `/api/v1/keys/signed-prekey` | Update signed pre-key |

### Stickers
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/stickers/catalog` | Browse sticker catalog |
| GET | `/api/v1/stickers/search` | Search sticker packs |
| GET | `/api/v1/stickers/packs/:id` | Get sticker pack |
| POST | `/api/v1/stickers/packs/:id/download` | Download pack |
| DELETE | `/api/v1/stickers/packs/:id` | Remove pack |
| GET | `/api/v1/stickers/my-packs` | Get user's packs |
| PUT | `/api/v1/stickers/my-packs/reorder` | Reorder packs |

### WebSocket

Connect to `ws://localhost:8080/api/v1/ws?token=<access_token>`

**Message Types:**
| Type | Direction | Description |
|------|-----------|-------------|
| `new_message` | Server → Client | New incoming message |
| `typing` | Bidirectional | Typing indicator |
| `presence` | Bidirectional | Online status update |
| `ack` | Client → Server | Delivery/read receipt |
| `ping` | Client → Server | Keep-alive ping |
| `pong` | Server → Client | Keep-alive response |

## Security

### Signal Protocol Implementation
- **X3DH (Extended Triple Diffie-Hellman)**: Establishes shared secrets for new sessions
- **Double Ratchet Algorithm**: Provides forward secrecy and break-in recovery
- **Pre-keys**: One-time pre-keys enable asynchronous session establishment

### Authentication Security
- JWT-based authentication with short-lived access tokens (15 min)
- Refresh tokens for session management (7 days)
- OTP verification for phone/email authentication
- Bcrypt password hashing (when applicable)

### Data Protection
- All messages are end-to-end encrypted on the client
- Encryption keys are generated and stored only on user devices
- Server stores only encrypted message content
- TLS for all network communications

## Testing

### Go Backend
```bash
cd backend
go test ./... -v
go test ./... -cover  # With coverage
```

### Rust Backend
```bash
cd backend-rs
cargo test
cargo test -- --nocapture  # With output
```

### Flutter App
```bash
cd mobile
flutter test
flutter test --coverage  # With coverage
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_HOST` | `0.0.0.0` | Server bind address |
| `SERVER_PORT` | `8080` | Server port |
| `ENVIRONMENT` | `development` | Environment (development/production) |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `postgres` | Database user |
| `DB_PASSWORD` | `postgres` | Database password |
| `DB_NAME` | `ansible_talk` | Database name |
| `REDIS_HOST` | `localhost` | Redis host |
| `REDIS_PORT` | `6379` | Redis port |
| `JWT_SECRET` | - | JWT signing secret (required) |
| `JWT_ACCESS_TOKEN_TTL` | `900` | Access token TTL in seconds |
| `JWT_REFRESH_TOKEN_TTL` | `604800` | Refresh token TTL in seconds |
| `MINIO_ENDPOINT` | `localhost:9000` | MinIO endpoint |
| `MINIO_ACCESS_KEY` | `minioadmin` | MinIO access key |
| `MINIO_SECRET_KEY` | `minioadmin` | MinIO secret key |

See `.env.example` files for complete configuration options.

## Project Structure

### Mobile App (`mobile/`)
```
lib/
├── app/                    # App configuration
│   └── router.dart         # Route definitions
├── core/
│   ├── crypto/             # Signal protocol client
│   ├── network/            # API & WebSocket clients
│   └── storage/            # Secure storage
├── features/
│   ├── auth/               # Authentication screens & providers
│   ├── chat/               # Chat screens & providers
│   ├── contacts/           # Contacts screens & providers
│   └── stickers/           # Stickers screens & providers
└── shared/
    ├── models/             # Data models
    └── widgets/            # Reusable widgets
```

### Go Backend (`backend/`)
```
internal/
├── api/                    # HTTP handlers & middleware
├── auth/                   # Auth service & JWT
├── config/                 # Configuration loading
├── contacts/               # Contacts service
├── crypto/                 # Signal key management
├── messaging/              # Messaging & WebSocket
├── models/                 # Data models
├── stickers/               # Stickers service
└── storage/                # Redis & MinIO clients
```

### Rust Backend (`backend-rs/`)
```
src/
├── api/                    # Handlers, middleware, router
├── config.rs               # Configuration
├── error.rs                # Error types
├── models/                 # Data models
├── services/               # Business logic
└── storage/                # Redis & MinIO clients
migrations/                 # SQLx migrations
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- **Go**: Follow standard Go conventions, use `gofmt`
- **Rust**: Follow Rust conventions, use `rustfmt`
- **Dart/Flutter**: Follow Dart style guide, use `dart format`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Signal Protocol](https://signal.org/docs/) for the encryption protocol specification
- [libsignal-protocol-dart](https://pub.dev/packages/libsignal_protocol_dart) for the Dart implementation
- The Flutter, Go, and Rust communities for excellent tooling and libraries
