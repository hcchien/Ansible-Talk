-- Migration: initial_schema
-- Description: Initial database schema for Ansible Talk messenger

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom types
DO $$ BEGIN
    CREATE TYPE user_status AS ENUM ('online', 'offline', 'away');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE otp_type AS ENUM ('phone', 'email');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE conversation_type AS ENUM ('direct', 'group');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE participant_role AS ENUM ('owner', 'admin', 'member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE message_type AS ENUM ('text', 'image', 'video', 'audio', 'file', 'sticker', 'system');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE message_status AS ENUM ('sending', 'sent', 'delivered', 'read', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE receipt_type AS ENUM ('delivered', 'read');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    status user_status DEFAULT 'offline',
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT phone_or_email CHECK (phone IS NOT NULL OR email IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- Devices table
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL,
    name VARCHAR(100) NOT NULL,
    platform VARCHAR(20) NOT NULL,
    push_token TEXT,
    last_active_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- Contacts table
CREATE TABLE IF NOT EXISTS contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nickname VARCHAR(100),
    is_blocked BOOLEAN DEFAULT FALSE,
    is_favorite BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_id),
    CONSTRAINT no_self_contact CHECK (user_id != contact_id)
);

CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_blocked ON contacts(user_id, is_blocked) WHERE is_blocked = TRUE;

-- Conversations table
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type conversation_type NOT NULL DEFAULT 'direct',
    name VARCHAR(100),
    avatar_url TEXT,
    created_by UUID NOT NULL REFERENCES users(id),
    last_message_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_last_message ON conversations(last_message_at DESC);

-- Participants table
CREATE TABLE IF NOT EXISTS participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role participant_role DEFAULT 'member',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    muted_until TIMESTAMP WITH TIME ZONE,
    UNIQUE(conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_participants_conversation ON participants(conversation_id);
CREATE INDEX IF NOT EXISTS idx_participants_user ON participants(user_id);
CREATE INDEX IF NOT EXISTS idx_participants_active ON participants(conversation_id) WHERE left_at IS NULL;

-- Sticker packs table (before messages for FK)
CREATE TABLE IF NOT EXISTS sticker_packs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    author VARCHAR(100) NOT NULL,
    description TEXT,
    cover_url TEXT,
    is_official BOOLEAN DEFAULT FALSE,
    is_animated BOOLEAN DEFAULT FALSE,
    price INTEGER DEFAULT 0,
    downloads BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sticker_packs_official ON sticker_packs(is_official);
CREATE INDEX IF NOT EXISTS idx_sticker_packs_downloads ON sticker_packs(downloads DESC);

-- Stickers table
CREATE TABLE IF NOT EXISTS stickers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pack_id UUID NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
    emoji VARCHAR(10) NOT NULL,
    image_url TEXT NOT NULL,
    position INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stickers_pack ON stickers(pack_id, position);

-- Messages table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    type message_type NOT NULL DEFAULT 'text',
    content BYTEA NOT NULL,
    sticker_id UUID REFERENCES stickers(id) ON DELETE SET NULL,
    reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    status message_status DEFAULT 'sent',
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_sticker ON messages(sticker_id) WHERE sticker_id IS NOT NULL;

-- Message receipts table
CREATE TABLE IF NOT EXISTS receipts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type receipt_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, type)
);

CREATE INDEX IF NOT EXISTS idx_receipts_message ON receipts(message_id);

-- User sticker packs
CREATE TABLE IF NOT EXISTS user_sticker_packs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pack_id UUID NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, pack_id)
);

CREATE INDEX IF NOT EXISTS idx_user_sticker_packs_user ON user_sticker_packs(user_id, position);

-- Signal Protocol Keys

-- Identity keys
CREATE TABLE IF NOT EXISTS signal_identity_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    registration_id INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_signal_identity_user ON signal_identity_keys(user_id);

-- Signed pre-keys
CREATE TABLE IF NOT EXISTS signal_signed_prekeys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL,
    key_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    signature BYTEA NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id, key_id)
);

CREATE INDEX IF NOT EXISTS idx_signal_signed_prekey_user ON signal_signed_prekeys(user_id, device_id);

-- One-time pre-keys
CREATE TABLE IF NOT EXISTS signal_prekeys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL,
    key_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id, key_id)
);

CREATE INDEX IF NOT EXISTS idx_signal_prekey_user ON signal_prekeys(user_id, device_id);

-- OTP verification codes
CREATE TABLE IF NOT EXISTS otps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    target VARCHAR(255) NOT NULL,
    type otp_type NOT NULL,
    code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts INTEGER DEFAULT 0,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(target, type)
);

CREATE INDEX IF NOT EXISTS idx_otps_target ON otps(target, type);
CREATE INDEX IF NOT EXISTS idx_otps_expires ON otps(expires_at);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    refresh_token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_contacts_updated_at ON contacts;
CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_conversations_updated_at ON conversations;
CREATE TRIGGER update_conversations_updated_at BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_sticker_packs_updated_at ON sticker_packs;
CREATE TRIGGER update_sticker_packs_updated_at BEFORE UPDATE ON sticker_packs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_signal_identity_keys_updated_at ON signal_identity_keys;
CREATE TRIGGER update_signal_identity_keys_updated_at BEFORE UPDATE ON signal_identity_keys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_signal_signed_prekeys_updated_at ON signal_signed_prekeys;
CREATE TRIGGER update_signal_signed_prekeys_updated_at BEFORE UPDATE ON signal_signed_prekeys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
