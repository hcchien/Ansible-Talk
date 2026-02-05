import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _deviceIdKey = 'device_id';
  static const _signalIdentityKeyKey = 'signal_identity_key';
  static const _signalRegistrationIdKey = 'signal_registration_id';
  static const _signalKeysInitializedKey = 'signal_keys_initialized';

  final FlutterSecureStorage _storage;

  SecureStorage() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Token management
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // User management
  Future<void> saveUserId(String userId) async {
    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<String?> getUserId() async {
    return _storage.read(key: _userIdKey);
  }

  Future<void> saveDeviceId(String deviceId) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<String?> getDeviceId() async {
    return _storage.read(key: _deviceIdKey);
  }

  // Signal protocol keys
  Future<void> saveSignalIdentityKey(List<int> privateKey, List<int> publicKey) async {
    final data = jsonEncode({
      'private': privateKey,
      'public': publicKey,
    });
    await _storage.write(key: _signalIdentityKeyKey, value: data);
  }

  Future<Map<String, List<int>>?> getSignalIdentityKey() async {
    final data = await _storage.read(key: _signalIdentityKeyKey);
    if (data == null) return null;

    final json = jsonDecode(data);
    return {
      'private': List<int>.from(json['private']),
      'public': List<int>.from(json['public']),
    };
  }

  Future<void> saveSignalRegistrationId(int registrationId) async {
    await _storage.write(key: _signalRegistrationIdKey, value: registrationId.toString());
  }

  Future<int?> getSignalRegistrationId() async {
    final data = await _storage.read(key: _signalRegistrationIdKey);
    if (data == null) return null;
    return int.tryParse(data);
  }

  // Generic key-value storage for Signal protocol
  Future<void> saveSignalKey(String key, List<int> value) async {
    await _storage.write(key: 'signal_$key', value: jsonEncode(value));
  }

  Future<List<int>?> getSignalKey(String key) async {
    final data = await _storage.read(key: 'signal_$key');
    if (data == null) return null;
    return List<int>.from(jsonDecode(data));
  }

  Future<void> deleteSignalKey(String key) async {
    await _storage.delete(key: 'signal_$key');
  }

  // Check if Signal keys have been initialized with server
  Future<bool> hasSignalKeys() async {
    final data = await _storage.read(key: _signalKeysInitializedKey);
    return data == 'true';
  }

  Future<void> markSignalKeysInitialized() async {
    await _storage.write(key: _signalKeysInitializedKey, value: 'true');
  }

  // Get all Signal pre-keys (for loading into protocol store)
  Future<Map<String, List<int>>> getSignalPreKeys() async {
    final allKeys = await _storage.readAll();
    final preKeys = <String, List<int>>{};

    for (final entry in allKeys.entries) {
      if (entry.key.startsWith('signal_prekey_')) {
        try {
          final keyName = entry.key.replaceFirst('signal_', '');
          preKeys[keyName] = List<int>.from(jsonDecode(entry.value));
        } catch (e) {
          // Skip invalid entries
        }
      }
    }

    return preKeys;
  }

  // Get all Signal signed pre-keys
  Future<Map<String, List<int>>> getSignalSignedPreKeys() async {
    final allKeys = await _storage.readAll();
    final signedPreKeys = <String, List<int>>{};

    for (final entry in allKeys.entries) {
      if (entry.key.startsWith('signal_signed_prekey_')) {
        try {
          final keyName = entry.key.replaceFirst('signal_', '');
          signedPreKeys[keyName] = List<int>.from(jsonDecode(entry.value));
        } catch (e) {
          // Skip invalid entries
        }
      }
    }

    return signedPreKeys;
  }

  // Get all Signal sessions
  Future<Map<String, List<int>>> getSignalSessions() async {
    final allKeys = await _storage.readAll();
    final sessions = <String, List<int>>{};

    for (final entry in allKeys.entries) {
      if (entry.key.startsWith('signal_session_')) {
        try {
          final sessionKey = entry.key.replaceFirst('signal_session_', '');
          sessions[sessionKey] = List<int>.from(jsonDecode(entry.value));
        } catch (e) {
          // Skip invalid entries
        }
      }
    }

    return sessions;
  }

  // Save Signal session
  Future<void> saveSignalSession(String userId, int deviceId, List<int> sessionData) async {
    await _storage.write(
      key: 'signal_session_${userId}_$deviceId',
      value: jsonEncode(sessionData),
    );
  }

  // Delete Signal session
  Future<void> deleteSignalSession(String userId, int deviceId) async {
    await _storage.delete(key: 'signal_session_${userId}_$deviceId');
  }

  // Clear all data
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}

// Provider
final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});
