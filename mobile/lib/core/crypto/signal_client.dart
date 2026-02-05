import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/local_database.dart';
import '../storage/secure_storage.dart';

/// Signal protocol client for end-to-end encryption
/// Note: This is a simplified implementation. For production use,
/// consider using the full libsignal_protocol_dart package.
class SignalClient {
  final SecureStorage _secureStorage;
  final LocalDatabase _localDatabase;
  final ApiClient _apiClient;

  // Crypto algorithms
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();

  SignalClient(this._secureStorage, this._localDatabase, this._apiClient);

  /// Initialize Signal protocol keys for a new device
  Future<void> initializeKeys() async {
    // Check if already initialized
    final existingKey = await _secureStorage.getSignalIdentityKey();
    if (existingKey != null) return;

    // Generate identity key pair
    final identityKeyPair = await _x25519.newKeyPair();
    final identityPrivateKey = await identityKeyPair.extractPrivateKeyBytes();
    final identityPublicKey = (await identityKeyPair.extractPublicKey()).bytes;

    // Generate registration ID
    final registrationId = Random.secure().nextInt(16383) + 1;

    // Save locally
    await _secureStorage.saveSignalIdentityKey(identityPrivateKey, identityPublicKey);
    await _secureStorage.saveSignalRegistrationId(registrationId);

    // Generate signed pre-key
    final signedPreKey = await _generateSignedPreKey(identityPrivateKey);

    // Generate one-time pre-keys
    final preKeys = await _generatePreKeys(0, 100);

    // Register keys with server
    await _apiClient.registerKeys({
      'registration_id': registrationId,
      'identity_key': base64Encode(identityPublicKey),
      'signed_pre_key': {
        'key_id': signedPreKey['key_id'],
        'public_key': base64Encode(signedPreKey['public_key'] as List<int>),
        'signature': base64Encode(signedPreKey['signature'] as List<int>),
      },
      'pre_keys': preKeys.map((pk) => {
        'key_id': pk['key_id'],
        'public_key': base64Encode(pk['public_key'] as List<int>),
      }).toList(),
    });
  }

  /// Generate a signed pre-key
  Future<Map<String, dynamic>> _generateSignedPreKey(List<int> identityPrivateKey) async {
    final keyId = Random.secure().nextInt(0xFFFFFF);
    final keyPair = await _x25519.newKeyPair();
    final publicKey = (await keyPair.extractPublicKey()).bytes;

    // Sign with identity key
    final signature = await _sign(Uint8List.fromList(publicKey), Uint8List.fromList(identityPrivateKey));

    // Store private key locally
    final privateKey = await keyPair.extractPrivateKeyBytes();
    await _secureStorage.saveSignalKey('signed_prekey_$keyId', privateKey);

    return {
      'key_id': keyId,
      'public_key': publicKey,
      'signature': signature,
    };
  }

  /// Generate one-time pre-keys
  Future<List<Map<String, dynamic>>> _generatePreKeys(int start, int count) async {
    final preKeys = <Map<String, dynamic>>[];

    for (var i = start; i < start + count; i++) {
      final keyPair = await _x25519.newKeyPair();
      final publicKey = (await keyPair.extractPublicKey()).bytes;
      final privateKey = await keyPair.extractPrivateKeyBytes();

      // Store private key locally
      await _secureStorage.saveSignalKey('prekey_$i', privateKey);

      preKeys.add({
        'key_id': i,
        'public_key': publicKey,
      });
    }

    return preKeys;
  }

  /// Encrypt a message for a recipient
  Future<List<int>> encryptMessage(String recipientUserId, int recipientDeviceId, String plaintext) async {
    // Get or create session
    var sessionData = await _localDatabase.getSignalSession(recipientUserId, recipientDeviceId);

    if (sessionData == null) {
      // Establish new session
      sessionData = await _establishSession(recipientUserId, recipientDeviceId);
    }

    // Derive message key from session
    final messageKey = await _deriveMessageKey(sessionData);

    // Encrypt with AES-GCM
    final nonce = _aesGcm.newNonce();
    final secretKey = SecretKey(messageKey);
    final encrypted = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Combine nonce + ciphertext + mac
    final result = <int>[];
    result.addAll(nonce);
    result.addAll(encrypted.cipherText);
    result.addAll(encrypted.mac.bytes);

    // Update session
    await _updateSession(recipientUserId, recipientDeviceId, sessionData);

    return result;
  }

  /// Decrypt a message from a sender
  Future<String> decryptMessage(String senderUserId, int senderDeviceId, List<int> ciphertext) async {
    // Get session
    var sessionData = await _localDatabase.getSignalSession(senderUserId, senderDeviceId);

    if (sessionData == null) {
      throw Exception('No session found for sender');
    }

    // Extract nonce, ciphertext, and mac
    final nonce = ciphertext.sublist(0, 12);
    final mac = ciphertext.sublist(ciphertext.length - 16);
    final encryptedData = ciphertext.sublist(12, ciphertext.length - 16);

    // Derive message key from session
    final messageKey = await _deriveMessageKey(sessionData);

    // Decrypt
    final secretKey = SecretKey(messageKey);
    final decrypted = await _aesGcm.decrypt(
      SecretBox(encryptedData, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );

    // Update session
    await _updateSession(senderUserId, senderDeviceId, sessionData);

    return utf8.decode(decrypted);
  }

  /// Establish a new session with a recipient
  Future<List<int>> _establishSession(String userId, int deviceId) async {
    // Fetch recipient's key bundle from server
    final response = await _apiClient.getKeyBundle(userId, deviceId);
    final bundle = response.data;

    // Get our identity key
    final identityKey = await _secureStorage.getSignalIdentityKey();
    if (identityKey == null) {
      throw Exception('Identity key not found');
    }

    // Perform X3DH key agreement
    final theirIdentityKey = base64Decode(bundle['identity_key']);
    final theirSignedPreKey = base64Decode(bundle['signed_pre_key']['public_key']);
    List<int>? theirPreKey;
    if (bundle['pre_key'] != null) {
      theirPreKey = base64Decode(bundle['pre_key']['public_key']);
    }

    // Generate ephemeral key pair
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPrivateKey = await ephemeralKeyPair.extractPrivateKeyBytes();

    // Compute shared secrets
    final dh1 = await _dh(identityKey['private']!, theirSignedPreKey);
    final dh2 = await _dh(ephemeralPrivateKey, theirIdentityKey);
    final dh3 = await _dh(ephemeralPrivateKey, theirSignedPreKey);

    var masterSecret = <int>[];
    masterSecret.addAll(dh1);
    masterSecret.addAll(dh2);
    masterSecret.addAll(dh3);

    if (theirPreKey != null) {
      final dh4 = await _dh(ephemeralPrivateKey, theirPreKey);
      masterSecret.addAll(dh4);
    }

    // Derive root key
    final rootKey = await _kdf(masterSecret, 'root');

    // Create session data
    final sessionData = <int>[];
    sessionData.addAll(rootKey);
    sessionData.addAll((await ephemeralKeyPair.extractPublicKey()).bytes);

    // Save session
    await _localDatabase.saveSignalSession(userId, deviceId, sessionData);

    return sessionData;
  }

  /// Derive message key from session data
  Future<List<int>> _deriveMessageKey(List<int> sessionData) async {
    final rootKey = sessionData.sublist(0, 32);
    return _kdf(rootKey, 'message');
  }

  /// Update session after message
  Future<void> _updateSession(String userId, int deviceId, List<int> sessionData) async {
    // Ratchet the chain key
    final newChainKey = await _kdf(sessionData.sublist(0, 32), 'chain');
    final newSessionData = <int>[];
    newSessionData.addAll(newChainKey);
    newSessionData.addAll(sessionData.sublist(32));

    await _localDatabase.saveSignalSession(userId, deviceId, newSessionData);
  }

  /// X25519 Diffie-Hellman
  Future<List<int>> _dh(List<int> privateKey, List<int> publicKey) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKey);
    final sharedKey = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    return sharedKey.extractBytes();
  }

  /// Key derivation function
  Future<List<int>> _kdf(List<int> input, String info) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(input),
      info: utf8.encode(info),
      nonce: Uint8List(32),
    );
    return derivedKey.extractBytes();
  }

  /// Sign data with private key (simplified Ed25519-like signature)
  Future<List<int>> _sign(Uint8List data, Uint8List privateKey) async {
    // In production, use proper Ed25519 signing
    // This is a simplified HMAC-based signature for demo
    final hmac = Hmac.sha512();
    final mac = await hmac.calculateMac(data, secretKey: SecretKey(privateKey));
    return mac.bytes;
  }

  /// Check and refresh pre-keys if needed
  Future<void> checkPreKeyCount(int deviceId) async {
    final response = await _apiClient.getPreKeyCount(deviceId);
    final count = response.data['count'] as int;

    if (count < 20) {
      // Generate more pre-keys
      final newPreKeys = await _generatePreKeys(count, 100);
      await _apiClient.refreshPreKeys(deviceId, newPreKeys.map((pk) => {
        'key_id': pk['key_id'],
        'public_key': base64Encode(pk['public_key'] as List<int>),
      }).toList());
    }
  }
}

// Provider
final signalClientProvider = Provider<SignalClient>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final localDatabase = ref.watch(localDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  return SignalClient(secureStorage, localDatabase, apiClient);
});
