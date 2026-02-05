import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ansible_talk.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        phone TEXT,
        email TEXT,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        avatar_url TEXT,
        bio TEXT,
        status TEXT DEFAULT 'offline',
        last_seen_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Contacts table
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        contact_id TEXT NOT NULL,
        nickname TEXT,
        is_blocked INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Conversations table
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT,
        avatar_url TEXT,
        created_by TEXT NOT NULL,
        last_message_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Participants table
    await db.execute('''
      CREATE TABLE participants (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        joined_at TEXT NOT NULL,
        left_at TEXT,
        muted_until TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content BLOB NOT NULL,
        decrypted_content TEXT,
        sticker_id TEXT,
        reply_to_id TEXT,
        status TEXT DEFAULT 'sending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at)');
    await db.execute('CREATE INDEX idx_participants_conversation ON participants(conversation_id)');
    await db.execute('CREATE INDEX idx_contacts_user ON contacts(user_id)');

    // Sticker packs table
    await db.execute('''
      CREATE TABLE sticker_packs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        author TEXT NOT NULL,
        description TEXT,
        cover_url TEXT NOT NULL,
        is_official INTEGER DEFAULT 0,
        is_animated INTEGER DEFAULT 0,
        price INTEGER DEFAULT 0,
        downloads INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Stickers table
    await db.execute('''
      CREATE TABLE stickers (
        id TEXT PRIMARY KEY,
        pack_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        image_url TEXT NOT NULL,
        position INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (pack_id) REFERENCES sticker_packs(id)
      )
    ''');

    // Signal sessions table
    await db.execute('''
      CREATE TABLE signal_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id INTEGER NOT NULL,
        session_data BLOB NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(user_id, device_id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations
  }

  // User operations
  Future<void> saveUser(Map<String, dynamic> user) async {
    final db = await database;
    await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getUser(String id) async {
    final db = await database;
    final results = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : results.first;
  }

  // Contact operations
  Future<void> saveContact(Map<String, dynamic> contact) async {
    final db = await database;
    await db.insert('contacts', contact, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getContacts(String userId) async {
    final db = await database;
    return db.query('contacts', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> deleteContact(String id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  // Conversation operations
  Future<void> saveConversation(Map<String, dynamic> conversation) async {
    final db = await database;
    await db.insert('conversations', conversation, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await database;
    return db.query('conversations', orderBy: 'last_message_at DESC');
  }

  Future<Map<String, dynamic>?> getConversation(String id) async {
    final db = await database;
    final results = await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : results.first;
  }

  // Message operations
  Future<void> saveMessage(Map<String, dynamic> message) async {
    final db = await database;
    await db.insert('messages', message, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId, {int limit = 50, int offset = 0}) async {
    final db = await database;
    return db.query(
      'messages',
      where: 'conversation_id = ? AND deleted_at IS NULL',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> updateMessageStatus(String id, String status) async {
    final db = await database;
    await db.update('messages', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.update('messages', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  // Sticker operations
  Future<void> saveStickerPack(Map<String, dynamic> pack) async {
    final db = await database;
    await db.insert('sticker_packs', pack, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getStickerPacks() async {
    final db = await database;
    return db.query('sticker_packs', orderBy: 'position ASC');
  }

  Future<void> saveSticker(Map<String, dynamic> sticker) async {
    final db = await database;
    await db.insert('stickers', sticker, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getStickers(String packId) async {
    final db = await database;
    return db.query('stickers', where: 'pack_id = ?', whereArgs: [packId], orderBy: 'position ASC');
  }

  // Signal session operations
  Future<void> saveSignalSession(String odUserId, int deviceId, List<int> sessionData) async {
    final db = await database;
    await db.insert('signal_sessions', {
      'id': '${odUserId}_$deviceId',
      'user_id': odUserId,
      'device_id': deviceId,
      'session_data': sessionData,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<int>?> getSignalSession(String odUserId, int deviceId) async {
    final db = await database;
    final results = await db.query(
      'signal_sessions',
      where: 'user_id = ? AND device_id = ?',
      whereArgs: [odUserId, deviceId],
    );
    if (results.isEmpty) return null;
    return List<int>.from(results.first['session_data'] as List);
  }

  Future<void> deleteSignalSession(String odUserId, int deviceId) async {
    final db = await database;
    await db.delete('signal_sessions', where: 'user_id = ? AND device_id = ?', whereArgs: [odUserId, deviceId]);
  }

  // Clear all data
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('participants');
    await db.delete('conversations');
    await db.delete('contacts');
    await db.delete('users');
    await db.delete('stickers');
    await db.delete('sticker_packs');
    await db.delete('signal_sessions');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

// Provider
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  return LocalDatabase();
});
