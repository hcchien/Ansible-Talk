import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

void main() {
  group('Signal Protocol Key Generation', () {
    test('generates valid identity key pair', () {
      final keyPair = generateIdentityKeyPair();

      expect(keyPair, isNotNull);
      expect(keyPair.getPublicKey(), isNotNull);
      expect(keyPair.getPrivateKey(), isNotNull);

      // Public key should be serializable
      final serializedPublic = keyPair.getPublicKey().publicKey.serialize();
      expect(serializedPublic, isNotEmpty);

      // Private key should be serializable
      final serializedPrivate = keyPair.getPrivateKey().serialize();
      expect(serializedPrivate, isNotEmpty);
    });

    test('generates different key pairs each time', () {
      final keyPair1 = generateIdentityKeyPair();
      final keyPair2 = generateIdentityKeyPair();

      final publicKey1 = keyPair1.getPublicKey().publicKey.serialize();
      final publicKey2 = keyPair2.getPublicKey().publicKey.serialize();

      // Keys should be different
      expect(publicKey1, isNot(equals(publicKey2)));
    });

    test('generates valid registration ID', () {
      final registrationId = generateRegistrationId(false);

      // Registration ID should be within valid range
      expect(registrationId, greaterThan(0));
      expect(registrationId, lessThanOrEqualTo(16380));
    });

    test('generates different registration IDs', () {
      final ids = List.generate(100, (_) => generateRegistrationId(false));

      // Should have some unique values (not all the same)
      final uniqueIds = ids.toSet();
      expect(uniqueIds.length, greaterThan(1));
    });

    test('generates valid pre-keys', () {
      final preKeys = generatePreKeys(0, 10);

      expect(preKeys, isNotNull);
      expect(preKeys.length, equals(10));

      for (int i = 0; i < preKeys.length; i++) {
        expect(preKeys[i].id, equals(i));
        expect(preKeys[i].getKeyPair().publicKey.serialize(), isNotEmpty);
      }
    });

    test('generates valid signed pre-key', () {
      final identityKeyPair = generateIdentityKeyPair();
      final signedPreKey = generateSignedPreKey(identityKeyPair, 0);

      expect(signedPreKey, isNotNull);
      expect(signedPreKey.id, equals(0));
      expect(signedPreKey.getKeyPair().publicKey.serialize(), isNotEmpty);
      expect(signedPreKey.signature, isNotEmpty);
    });
  });

  group('Signal Protocol Session', () {
    late InMemorySessionStore sessionStore;
    late InMemoryPreKeyStore preKeyStore;
    late InMemorySignedPreKeyStore signedPreKeyStore;
    late InMemoryIdentityKeyStore identityKeyStoreAlice;
    late InMemoryIdentityKeyStore identityKeyStoreBob;

    late IdentityKeyPair aliceIdentityKeyPair;
    late IdentityKeyPair bobIdentityKeyPair;
    late int aliceRegistrationId;
    late int bobRegistrationId;

    setUp(() {
      // Generate keys for Alice and Bob
      aliceIdentityKeyPair = generateIdentityKeyPair();
      bobIdentityKeyPair = generateIdentityKeyPair();
      aliceRegistrationId = generateRegistrationId(false);
      bobRegistrationId = generateRegistrationId(false);

      // Initialize stores
      sessionStore = InMemorySessionStore();
      preKeyStore = InMemoryPreKeyStore();
      signedPreKeyStore = InMemorySignedPreKeyStore();
      identityKeyStoreAlice =
          InMemoryIdentityKeyStore(aliceIdentityKeyPair, aliceRegistrationId);
      identityKeyStoreBob =
          InMemoryIdentityKeyStore(bobIdentityKeyPair, bobRegistrationId);
    });

    test('can establish session with pre-key bundle', () async {
      // Generate Bob's keys
      final bobSignedPreKey = generateSignedPreKey(bobIdentityKeyPair, 0);
      final bobPreKeys = generatePreKeys(0, 1);

      await signedPreKeyStore.storeSignedPreKey(bobSignedPreKey.id, bobSignedPreKey);
      await preKeyStore.storePreKey(bobPreKeys[0].id, bobPreKeys[0]);

      // Create Bob's pre-key bundle
      final bobPreKeyBundle = PreKeyBundle(
        bobRegistrationId,
        1, // deviceId
        bobPreKeys[0].id,
        bobPreKeys[0].getKeyPair().publicKey,
        bobSignedPreKey.id,
        bobSignedPreKey.getKeyPair().publicKey,
        bobSignedPreKey.signature,
        bobIdentityKeyPair.getPublicKey(),
      );

      // Alice establishes session with Bob
      final bobAddress = SignalProtocolAddress('bob', 1);
      final sessionBuilder = SessionBuilder(
        sessionStore,
        preKeyStore,
        signedPreKeyStore,
        identityKeyStoreAlice,
        bobAddress,
      );

      await sessionBuilder.processPreKeyBundle(bobPreKeyBundle);

      // Verify session was created
      expect(await sessionStore.containsSession(bobAddress), isTrue);
    });

    test('can encrypt and decrypt message', () async {
      // Set up Alice's stores
      final aliceSessionStore = InMemorySessionStore();
      final alicePreKeyStore = InMemoryPreKeyStore();
      final aliceSignedPreKeyStore = InMemorySignedPreKeyStore();
      final aliceIdentityStore =
          InMemoryIdentityKeyStore(aliceIdentityKeyPair, aliceRegistrationId);

      // Set up Bob's stores
      final bobSessionStore = InMemorySessionStore();
      final bobPreKeyStore = InMemoryPreKeyStore();
      final bobSignedPreKeyStore = InMemorySignedPreKeyStore();
      final bobIdentityStore =
          InMemoryIdentityKeyStore(bobIdentityKeyPair, bobRegistrationId);

      // Generate Bob's keys
      final bobSignedPreKey = generateSignedPreKey(bobIdentityKeyPair, 0);
      final bobPreKeys = generatePreKeys(0, 1);

      await bobSignedPreKeyStore.storeSignedPreKey(bobSignedPreKey.id, bobSignedPreKey);
      await bobPreKeyStore.storePreKey(bobPreKeys[0].id, bobPreKeys[0]);

      // Create Bob's pre-key bundle
      final bobPreKeyBundle = PreKeyBundle(
        bobRegistrationId,
        1,
        bobPreKeys[0].id,
        bobPreKeys[0].getKeyPair().publicKey,
        bobSignedPreKey.id,
        bobSignedPreKey.getKeyPair().publicKey,
        bobSignedPreKey.signature,
        bobIdentityKeyPair.getPublicKey(),
      );

      // Alice establishes session with Bob
      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceSessionBuilder = SessionBuilder(
        aliceSessionStore,
        alicePreKeyStore,
        aliceSignedPreKeyStore,
        aliceIdentityStore,
        bobAddress,
      );
      await aliceSessionBuilder.processPreKeyBundle(bobPreKeyBundle);

      // Alice encrypts a message
      final aliceCipher = SessionCipher(
        aliceSessionStore,
        alicePreKeyStore,
        aliceSignedPreKeyStore,
        aliceIdentityStore,
        bobAddress,
      );

      const originalMessage = 'Hello, Bob!';
      final ciphertext = await aliceCipher.encrypt(
        Uint8List.fromList(utf8.encode(originalMessage)),
      );

      expect(ciphertext, isNotNull);
      expect(ciphertext.getType(), equals(CiphertextMessage.prekeyType));

      // Bob decrypts the message
      final aliceAddress = SignalProtocolAddress('alice', 1);
      final bobCipher = SessionCipher(
        bobSessionStore,
        bobPreKeyStore,
        bobSignedPreKeyStore,
        bobIdentityStore,
        aliceAddress,
      );

      final preKeyMessage = PreKeySignalMessage(ciphertext.serialize());
      final decrypted = await bobCipher.decrypt(preKeyMessage);

      expect(utf8.decode(decrypted), equals(originalMessage));
    });

    test('subsequent messages use regular SignalMessage', () async {
      // Set up Alice's stores
      final aliceSessionStore = InMemorySessionStore();
      final alicePreKeyStore = InMemoryPreKeyStore();
      final aliceSignedPreKeyStore = InMemorySignedPreKeyStore();
      final aliceIdentityStore =
          InMemoryIdentityKeyStore(aliceIdentityKeyPair, aliceRegistrationId);

      // Set up Bob's stores
      final bobSessionStore = InMemorySessionStore();
      final bobPreKeyStore = InMemoryPreKeyStore();
      final bobSignedPreKeyStore = InMemorySignedPreKeyStore();
      final bobIdentityStore =
          InMemoryIdentityKeyStore(bobIdentityKeyPair, bobRegistrationId);

      // Generate Bob's keys
      final bobSignedPreKey = generateSignedPreKey(bobIdentityKeyPair, 0);
      final bobPreKeys = generatePreKeys(0, 1);

      await bobSignedPreKeyStore.storeSignedPreKey(bobSignedPreKey.id, bobSignedPreKey);
      await bobPreKeyStore.storePreKey(bobPreKeys[0].id, bobPreKeys[0]);

      final bobPreKeyBundle = PreKeyBundle(
        bobRegistrationId,
        1,
        bobPreKeys[0].id,
        bobPreKeys[0].getKeyPair().publicKey,
        bobSignedPreKey.id,
        bobSignedPreKey.getKeyPair().publicKey,
        bobSignedPreKey.signature,
        bobIdentityKeyPair.getPublicKey(),
      );

      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceAddress = SignalProtocolAddress('alice', 1);

      // Alice establishes session
      final aliceSessionBuilder = SessionBuilder(
        aliceSessionStore,
        alicePreKeyStore,
        aliceSignedPreKeyStore,
        aliceIdentityStore,
        bobAddress,
      );
      await aliceSessionBuilder.processPreKeyBundle(bobPreKeyBundle);

      // Alice sends first message (PreKeySignalMessage)
      final aliceCipher = SessionCipher(
        aliceSessionStore,
        alicePreKeyStore,
        aliceSignedPreKeyStore,
        aliceIdentityStore,
        bobAddress,
      );

      final firstMessage = await aliceCipher.encrypt(
        Uint8List.fromList(utf8.encode('First message')),
      );
      expect(firstMessage.getType(), equals(CiphertextMessage.prekeyType));

      // Bob receives and decrypts
      final bobCipher = SessionCipher(
        bobSessionStore,
        bobPreKeyStore,
        bobSignedPreKeyStore,
        bobIdentityStore,
        aliceAddress,
      );

      final preKeyMessage = PreKeySignalMessage(firstMessage.serialize());
      await bobCipher.decrypt(preKeyMessage);

      // Bob sends reply (should be regular SignalMessage now)
      final replyMessage = await bobCipher.encrypt(
        Uint8List.fromList(utf8.encode('Reply from Bob')),
      );
      expect(replyMessage.getType(), equals(CiphertextMessage.whisperType));

      // Alice decrypts Bob's reply
      final signalMessage = SignalMessage.fromSerialized(replyMessage.serialize());
      final decrypted = await aliceCipher.decryptFromSignal(signalMessage);
      expect(utf8.decode(decrypted), equals('Reply from Bob'));
    });
  });

  group('Fingerprint Generation', () {
    test('generates reproducible fingerprints', () {
      final aliceKeyPair = generateIdentityKeyPair();
      final bobKeyPair = generateIdentityKeyPair();

      final generator = NumericFingerprintGenerator(5200);

      final fingerprint1 = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair.getPublicKey(),
      );

      final fingerprint2 = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair.getPublicKey(),
      );

      // Same inputs should produce same fingerprint
      expect(
        fingerprint1.displayableFingerprint.getDisplayText(),
        equals(fingerprint2.displayableFingerprint.getDisplayText()),
      );
    });

    test('fingerprints are symmetric', () {
      final aliceKeyPair = generateIdentityKeyPair();
      final bobKeyPair = generateIdentityKeyPair();

      final generator = NumericFingerprintGenerator(5200);

      final aliceFingerprint = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair.getPublicKey(),
      );

      final bobFingerprint = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
      );

      // Alice's fingerprint should match Bob's fingerprint
      expect(
        aliceFingerprint.displayableFingerprint.getDisplayText(),
        equals(bobFingerprint.displayableFingerprint.getDisplayText()),
      );
    });

    test('different keys produce different fingerprints', () {
      final aliceKeyPair = generateIdentityKeyPair();
      final bobKeyPair1 = generateIdentityKeyPair();
      final bobKeyPair2 = generateIdentityKeyPair();

      final generator = NumericFingerprintGenerator(5200);

      final fingerprint1 = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair1.getPublicKey(),
      );

      final fingerprint2 = generator.createFor(
        1,
        Uint8List.fromList(utf8.encode('alice')),
        aliceKeyPair.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bobKeyPair2.getPublicKey(),
      );

      // Different keys should produce different fingerprints
      expect(
        fingerprint1.displayableFingerprint.getDisplayText(),
        isNot(equals(fingerprint2.displayableFingerprint.getDisplayText())),
      );
    });
  });

  group('Key Serialization', () {
    test('identity key can be serialized and deserialized', () {
      final keyPair = generateIdentityKeyPair();

      // Serialize
      final publicKeySerialized = keyPair.getPublicKey().publicKey.serialize();
      final privateKeySerialized = keyPair.getPrivateKey().serialize();

      // Deserialize
      final publicKey = Curve.decodePoint(Uint8List.fromList(publicKeySerialized), 0);
      final privateKey = Curve.decodePrivatePoint(Uint8List.fromList(privateKeySerialized));

      final restoredKeyPair = IdentityKeyPair(
        IdentityKey(publicKey),
        privateKey,
      );

      // Verify they match
      expect(
        restoredKeyPair.getPublicKey().publicKey.serialize(),
        equals(publicKeySerialized),
      );
    });

    test('pre-key can be base64 encoded for API', () {
      final preKeys = generatePreKeys(0, 1);
      final preKey = preKeys[0];

      // Encode for API
      final encoded = base64Encode(preKey.getKeyPair().publicKey.serialize());

      expect(encoded, isNotEmpty);
      expect(encoded, isA<String>());

      // Decode back
      final decoded = base64Decode(encoded);
      expect(decoded, isNotEmpty);
    });

    test('signed pre-key signature can be base64 encoded', () {
      final identityKeyPair = generateIdentityKeyPair();
      final signedPreKey = generateSignedPreKey(identityKeyPair, 0);

      final encodedSignature = base64Encode(signedPreKey.signature);
      final decodedSignature = base64Decode(encodedSignature);

      expect(decodedSignature, equals(signedPreKey.signature));
    });
  });

  group('In-Memory Stores', () {
    test('InMemorySessionStore stores and retrieves sessions', () async {
      final store = InMemorySessionStore();
      final address = SignalProtocolAddress('user1', 1);

      expect(await store.containsSession(address), isFalse);

      // Create a session record
      final aliceKeyPair = generateIdentityKeyPair();
      final bobKeyPair = generateIdentityKeyPair();

      final bobSignedPreKey = generateSignedPreKey(bobKeyPair, 0);
      final bobPreKeys = generatePreKeys(0, 1);

      final preKeyBundle = PreKeyBundle(
        generateRegistrationId(false),
        1,
        bobPreKeys[0].id,
        bobPreKeys[0].getKeyPair().publicKey,
        bobSignedPreKey.id,
        bobSignedPreKey.getKeyPair().publicKey,
        bobSignedPreKey.signature,
        bobKeyPair.getPublicKey(),
      );

      final aliceIdentityStore = InMemoryIdentityKeyStore(
        aliceKeyPair,
        generateRegistrationId(false),
      );

      final builder = SessionBuilder(
        store,
        InMemoryPreKeyStore(),
        InMemorySignedPreKeyStore(),
        aliceIdentityStore,
        address,
      );

      await builder.processPreKeyBundle(preKeyBundle);

      expect(await store.containsSession(address), isTrue);
    });

    test('InMemoryPreKeyStore stores and retrieves pre-keys', () async {
      final store = InMemoryPreKeyStore();
      final preKeys = generatePreKeys(0, 5);

      for (final preKey in preKeys) {
        await store.storePreKey(preKey.id, preKey);
      }

      for (int i = 0; i < 5; i++) {
        final loaded = await store.loadPreKey(i);
        expect(loaded.id, equals(i));
      }

      // Remove a pre-key
      await store.removePreKey(2);

      // Should throw when loading removed key
      expect(() => store.loadPreKey(2), throwsA(isA<InvalidKeyIdException>()));
    });

    test('InMemorySignedPreKeyStore stores and retrieves signed pre-keys', () async {
      final store = InMemorySignedPreKeyStore();
      final identityKeyPair = generateIdentityKeyPair();
      final signedPreKey = generateSignedPreKey(identityKeyPair, 0);

      await store.storeSignedPreKey(signedPreKey.id, signedPreKey);

      final loaded = await store.loadSignedPreKey(signedPreKey.id);
      expect(loaded.id, equals(signedPreKey.id));
    });

    test('InMemoryIdentityKeyStore manages identity keys', () async {
      final localKeyPair = generateIdentityKeyPair();
      final registrationId = generateRegistrationId(false);
      final store = InMemoryIdentityKeyStore(localKeyPair, registrationId);

      // Get local identity
      expect(await store.getIdentityKeyPair(), equals(localKeyPair));
      expect(await store.getLocalRegistrationId(), equals(registrationId));

      // Save and retrieve remote identity
      final remoteAddress = SignalProtocolAddress('remote', 1);
      final remoteKeyPair = generateIdentityKeyPair();

      await store.saveIdentity(remoteAddress, remoteKeyPair.getPublicKey());

      final retrievedIdentity = await store.getIdentity(remoteAddress);
      expect(retrievedIdentity, isNotNull);
      expect(
        retrievedIdentity!.publicKey.serialize(),
        equals(remoteKeyPair.getPublicKey().publicKey.serialize()),
      );
    });
  });
}
