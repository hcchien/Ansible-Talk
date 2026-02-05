import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../network/api_client.dart';
import '../storage/secure_storage.dart';

/// Signal protocol client for end-to-end encryption
/// Uses the official libsignal_protocol_dart library
class SignalClient {
  final SecureStorage _secureStorage;
  final ApiClient _apiClient;

  // Signal protocol stores (separate stores as per library design)
  InMemorySessionStore? _sessionStore;
  InMemoryPreKeyStore? _preKeyStore;
  InMemorySignedPreKeyStore? _signedPreKeyStore;
  InMemoryIdentityKeyStore? _identityKeyStore;

  IdentityKeyPair? _identityKeyPair;
  int? _registrationId;
  bool _isInitialized = false;

  SignalClient(this._secureStorage, this._apiClient);

  /// Initialize Signal protocol stores
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    _identityKeyPair = await _loadOrCreateIdentityKeyPair();
    _registrationId = await _loadOrCreateRegistrationId();

    // Initialize stores
    _sessionStore = InMemorySessionStore();
    _preKeyStore = InMemoryPreKeyStore();
    _signedPreKeyStore = InMemorySignedPreKeyStore();
    _identityKeyStore = InMemoryIdentityKeyStore(_identityKeyPair!, _registrationId!);

    _isInitialized = true;
  }

  /// Load or create identity key pair
  Future<IdentityKeyPair> _loadOrCreateIdentityKeyPair() async {
    final stored = await _secureStorage.getSignalIdentityKey();

    if (stored != null && stored['private'] != null && stored['public'] != null) {
      try {
        final privateKey = Uint8List.fromList(stored['private']!);
        final publicKey = Uint8List.fromList(stored['public']!);
        return IdentityKeyPair(
          IdentityKey(Curve.decodePoint(publicKey, 0)),
          Curve.decodePrivatePoint(privateKey),
        );
      } catch (e) {
        // If loading fails, generate new keys
      }
    }

    // Generate new identity key pair
    final keyPair = generateIdentityKeyPair();

    // Save to secure storage
    await _secureStorage.saveSignalIdentityKey(
      keyPair.getPrivateKey().serialize(),
      keyPair.getPublicKey().publicKey.serialize(),
    );

    return keyPair;
  }

  /// Load or create registration ID
  Future<int> _loadOrCreateRegistrationId() async {
    final stored = await _secureStorage.getSignalRegistrationId();
    if (stored != null) {
      return stored;
    }

    // Generate new registration ID (1-16380)
    final registrationId = generateRegistrationId(false);
    await _secureStorage.saveSignalRegistrationId(registrationId);
    return registrationId;
  }

  /// Initialize Signal protocol keys for a new device
  Future<void> initializeKeys() async {
    await _ensureInitialized();

    // Check if already registered with server
    final existingKeys = await _secureStorage.hasSignalKeys();
    if (existingKeys) return;

    // Generate signed pre-key
    final signedPreKey = generateSignedPreKey(_identityKeyPair!, 0);

    // Store signed pre-key
    await _signedPreKeyStore!.storeSignedPreKey(signedPreKey.id, signedPreKey);

    // Generate one-time pre-keys
    final preKeys = generatePreKeys(0, 100);
    for (final preKey in preKeys) {
      await _preKeyStore!.storePreKey(preKey.id, preKey);
    }

    // Register keys with server
    await _apiClient.registerKeys({
      'registration_id': _registrationId,
      'identity_key': base64Encode(
        _identityKeyPair!.getPublicKey().publicKey.serialize(),
      ),
      'signed_pre_key': {
        'key_id': signedPreKey.id,
        'public_key': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
      'pre_keys': preKeys
          .map((pk) => {
                'key_id': pk.id,
                'public_key': base64Encode(pk.getKeyPair().publicKey.serialize()),
              })
          .toList(),
    });

    // Mark as initialized
    await _secureStorage.markSignalKeysInitialized();
  }

  /// Encrypt a message for a recipient
  Future<CiphertextMessage> encryptMessage(
    String recipientUserId,
    int recipientDeviceId,
    String plaintext,
  ) async {
    await _ensureInitialized();

    final address = SignalProtocolAddress(recipientUserId, recipientDeviceId);

    // Check if we have a session, if not establish one
    if (!await _sessionStore!.containsSession(address)) {
      await _establishSession(recipientUserId, recipientDeviceId);
    }

    // Create session cipher and encrypt
    final sessionCipher = SessionCipher(
      _sessionStore!,
      _preKeyStore!,
      _signedPreKeyStore!,
      _identityKeyStore!,
      address,
    );
    final ciphertext = await sessionCipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));

    return ciphertext;
  }

  /// Decrypt a message from a sender
  Future<String> decryptMessage(
    String senderUserId,
    int senderDeviceId,
    Uint8List ciphertext,
    int messageType, // 1 = PreKeySignalMessage, 2 = SignalMessage
  ) async {
    await _ensureInitialized();

    final address = SignalProtocolAddress(senderUserId, senderDeviceId);
    final sessionCipher = SessionCipher(
      _sessionStore!,
      _preKeyStore!,
      _signedPreKeyStore!,
      _identityKeyStore!,
      address,
    );

    Uint8List plaintext;
    if (messageType == CiphertextMessage.prekeyType) {
      // First message with pre-key
      final preKeyMessage = PreKeySignalMessage(ciphertext);
      plaintext = await sessionCipher.decrypt(preKeyMessage);
    } else {
      // Regular message
      final signalMessage = SignalMessage.fromSerialized(ciphertext);
      plaintext = await sessionCipher.decryptFromSignal(signalMessage);
    }

    return utf8.decode(plaintext);
  }

  /// Establish a new session with a recipient using X3DH
  Future<void> _establishSession(String userId, int deviceId) async {
    // Fetch recipient's key bundle from server
    final response = await _apiClient.getKeyBundle(userId, deviceId);
    final bundle = response.data;

    // Parse the key bundle
    final registrationId = bundle['registration_id'] as int;
    final identityKeyBytes = base64Decode(bundle['identity_key']);
    final signedPreKeyId = bundle['signed_pre_key']['key_id'] as int;
    final signedPreKeyBytes = base64Decode(bundle['signed_pre_key']['public_key']);
    final signedPreKeySignature = base64Decode(bundle['signed_pre_key']['signature']);

    ECPublicKey? preKey;
    int? preKeyId;
    if (bundle['pre_key'] != null) {
      preKeyId = bundle['pre_key']['key_id'] as int;
      final preKeyBytes = base64Decode(bundle['pre_key']['public_key']);
      preKey = Curve.decodePoint(Uint8List.fromList(preKeyBytes), 0);
    }

    // Create pre-key bundle
    final preKeyBundle = PreKeyBundle(
      registrationId,
      deviceId,
      preKeyId,
      preKey,
      signedPreKeyId,
      Curve.decodePoint(Uint8List.fromList(signedPreKeyBytes), 0),
      Uint8List.fromList(signedPreKeySignature),
      IdentityKey(Curve.decodePoint(Uint8List.fromList(identityKeyBytes), 0)),
    );

    // Build session using X3DH
    final address = SignalProtocolAddress(userId, deviceId);
    final sessionBuilder = SessionBuilder(
      _sessionStore!,
      _preKeyStore!,
      _signedPreKeyStore!,
      _identityKeyStore!,
      address,
    );
    await sessionBuilder.processPreKeyBundle(preKeyBundle);
  }

  /// Check and refresh pre-keys if needed
  Future<void> checkPreKeyCount(int deviceId) async {
    await _ensureInitialized();

    final response = await _apiClient.getPreKeyCount(deviceId);
    final count = response.data['count'] as int;

    if (count < 20) {
      // Generate more pre-keys starting from current max + 1
      final currentMaxId = await _getMaxPreKeyId();
      final newPreKeys = generatePreKeys(currentMaxId + 1, 100);

      for (final preKey in newPreKeys) {
        await _preKeyStore!.storePreKey(preKey.id, preKey);
      }

      await _apiClient.refreshPreKeys(
        deviceId,
        newPreKeys
            .map((pk) => {
                  'key_id': pk.id,
                  'public_key': base64Encode(pk.getKeyPair().publicKey.serialize()),
                })
            .toList(),
      );
    }
  }

  /// Rotate signed pre-key (should be done periodically)
  Future<void> rotateSignedPreKey() async {
    await _ensureInitialized();

    final currentMaxId = await _getMaxSignedPreKeyId();
    final newSignedPreKey = generateSignedPreKey(
      _identityKeyPair!,
      currentMaxId + 1,
    );

    await _signedPreKeyStore!.storeSignedPreKey(newSignedPreKey.id, newSignedPreKey);

    // Update on server
    await _apiClient.updateSignedPreKey({
      'key_id': newSignedPreKey.id,
      'public_key': base64Encode(newSignedPreKey.getKeyPair().publicKey.serialize()),
      'signature': base64Encode(newSignedPreKey.signature),
    });
  }

  Future<int> _getMaxPreKeyId() async {
    // For simplicity, track in secure storage or return a default
    // In production, you'd track this properly
    return 100;
  }

  Future<int> _getMaxSignedPreKeyId() async {
    // For simplicity, track in secure storage or return a default
    return 0;
  }

  /// Get the identity public key for display/verification
  Future<String> getIdentityPublicKey() async {
    await _ensureInitialized();
    return base64Encode(
      _identityKeyPair!.getPublicKey().publicKey.serialize(),
    );
  }

  /// Verify a contact's identity key fingerprint
  Future<bool> verifyIdentityKey(String userId, int deviceId, String expectedKeyBase64) async {
    await _ensureInitialized();

    final address = SignalProtocolAddress(userId, deviceId);
    final storedIdentity = await _identityKeyStore!.getIdentity(address);

    if (storedIdentity == null) return false;

    final storedKeyBase64 = base64Encode(storedIdentity.publicKey.serialize());
    return storedKeyBase64 == expectedKeyBase64;
  }

  /// Get fingerprint for identity verification (safety numbers)
  Future<String> getFingerprint(String localUserId, String remoteUserId, int remoteDeviceId) async {
    await _ensureInitialized();

    final remoteAddress = SignalProtocolAddress(remoteUserId, remoteDeviceId);
    final remoteIdentity = await _identityKeyStore!.getIdentity(remoteAddress);

    if (remoteIdentity == null) {
      throw Exception('No identity found for remote user');
    }

    // Generate numeric fingerprint
    final localFingerprint = NumericFingerprintGenerator(5200).createFor(
      1,
      Uint8List.fromList(utf8.encode(localUserId)),
      _identityKeyPair!.getPublicKey(),
      Uint8List.fromList(utf8.encode(remoteUserId)),
      remoteIdentity,
    );

    return localFingerprint.displayableFingerprint.getDisplayText();
  }
}

// Provider
final signalClientProvider = Provider<SignalClient>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final apiClient = ref.watch(apiClientProvider);
  return SignalClient(secureStorage, apiClient);
});
