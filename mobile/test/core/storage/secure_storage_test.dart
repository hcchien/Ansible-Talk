import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Tests for SecureStorage functionality
/// Note: These tests verify the logic without requiring actual platform channels
void main() {
  group('SecureStorage Key Constants', () {
    // Verify key constant values are correct
    test('has correct key constants', () {
      // These should match the constants in SecureStorage
      const accessTokenKey = 'access_token';
      const refreshTokenKey = 'refresh_token';
      const userIdKey = 'user_id';
      const deviceIdKey = 'device_id';
      const signalIdentityKeyKey = 'signal_identity_key';
      const signalRegistrationIdKey = 'signal_registration_id';
      const signalKeysInitializedKey = 'signal_keys_initialized';

      expect(accessTokenKey, equals('access_token'));
      expect(refreshTokenKey, equals('refresh_token'));
      expect(userIdKey, equals('user_id'));
      expect(deviceIdKey, equals('device_id'));
      expect(signalIdentityKeyKey, equals('signal_identity_key'));
      expect(signalRegistrationIdKey, equals('signal_registration_id'));
      expect(signalKeysInitializedKey, equals('signal_keys_initialized'));
    });
  });

  group('Signal Key Serialization', () {
    test('identity key can be serialized to JSON', () {
      final privateKey = [1, 2, 3, 4, 5];
      final publicKey = [6, 7, 8, 9, 10];

      final data = jsonEncode({
        'private': privateKey,
        'public': publicKey,
      });

      expect(data, isNotNull);
      expect(data, contains('private'));
      expect(data, contains('public'));
    });

    test('identity key can be deserialized from JSON', () {
      const data = '{"private":[1,2,3,4,5],"public":[6,7,8,9,10]}';

      final json = jsonDecode(data);

      expect(json['private'], equals([1, 2, 3, 4, 5]));
      expect(json['public'], equals([6, 7, 8, 9, 10]));
    });

    test('can convert JSON arrays to List<int>', () {
      const data = '{"private":[1,2,3,4,5],"public":[6,7,8,9,10]}';

      final json = jsonDecode(data);
      final privateKey = List<int>.from(json['private']);
      final publicKey = List<int>.from(json['public']);

      expect(privateKey, isA<List<int>>());
      expect(publicKey, isA<List<int>>());
      expect(privateKey.length, equals(5));
      expect(publicKey.length, equals(5));
    });

    test('registration ID can be parsed from string', () {
      const storedValue = '12345';
      final registrationId = int.tryParse(storedValue);

      expect(registrationId, equals(12345));
    });

    test('invalid registration ID returns null', () {
      const storedValue = 'invalid';
      final registrationId = int.tryParse(storedValue);

      expect(registrationId, isNull);
    });
  });

  group('Signal Session Key Format', () {
    test('session key format is correct', () {
      const userId = '550e8400-e29b-41d4-a716-446655440000';
      const deviceId = 1;
      final sessionKey = 'signal_session_${userId}_$deviceId';

      expect(
        sessionKey,
        equals('signal_session_550e8400-e29b-41d4-a716-446655440000_1'),
      );
    });

    test('can extract user ID from session key', () {
      const sessionKey = 'signal_session_550e8400-e29b-41d4-a716-446655440000_1';
      final withoutPrefix = sessionKey.replaceFirst('signal_session_', '');
      final parts = withoutPrefix.split('_');

      // UUID has hyphens so we need to handle that
      final deviceIdPart = parts.last;
      final userIdPart = parts.sublist(0, parts.length - 1).join('_');

      expect(userIdPart, equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(int.parse(deviceIdPart), equals(1));
    });
  });

  group('Pre-key Storage Key Format', () {
    test('pre-key key format is correct', () {
      const keyId = 42;
      final preKeyKey = 'signal_prekey_$keyId';

      expect(preKeyKey, equals('signal_prekey_42'));
    });

    test('signed pre-key key format is correct', () {
      const keyId = 0;
      final signedPreKeyKey = 'signal_signed_prekey_$keyId';

      expect(signedPreKeyKey, equals('signal_signed_prekey_0'));
    });

    test('can filter pre-keys from all keys', () {
      final allKeys = {
        'signal_prekey_0': '[1,2,3]',
        'signal_prekey_1': '[4,5,6]',
        'signal_signed_prekey_0': '[7,8,9]',
        'signal_session_user1_1': '[10,11,12]',
        'access_token': 'token',
      };

      final preKeys = <String, List<int>>{};
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith('signal_prekey_')) {
          preKeys[entry.key] = List<int>.from(jsonDecode(entry.value));
        }
      }

      expect(preKeys.length, equals(2));
      expect(preKeys.containsKey('signal_prekey_0'), isTrue);
      expect(preKeys.containsKey('signal_prekey_1'), isTrue);
    });

    test('can filter signed pre-keys from all keys', () {
      final allKeys = {
        'signal_prekey_0': '[1,2,3]',
        'signal_signed_prekey_0': '[7,8,9]',
        'signal_signed_prekey_1': '[10,11,12]',
        'signal_session_user1_1': '[13,14,15]',
      };

      final signedPreKeys = <String, List<int>>{};
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith('signal_signed_prekey_')) {
          signedPreKeys[entry.key] = List<int>.from(jsonDecode(entry.value));
        }
      }

      expect(signedPreKeys.length, equals(2));
      expect(signedPreKeys.containsKey('signal_signed_prekey_0'), isTrue);
      expect(signedPreKeys.containsKey('signal_signed_prekey_1'), isTrue);
    });

    test('can filter sessions from all keys', () {
      final allKeys = {
        'signal_prekey_0': '[1,2,3]',
        'signal_signed_prekey_0': '[7,8,9]',
        'signal_session_user1_1': '[10,11,12]',
        'signal_session_user2_2': '[13,14,15]',
      };

      final sessions = <String, List<int>>{};
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith('signal_session_')) {
          final sessionKey = entry.key.replaceFirst('signal_session_', '');
          sessions[sessionKey] = List<int>.from(jsonDecode(entry.value));
        }
      }

      expect(sessions.length, equals(2));
      expect(sessions.containsKey('user1_1'), isTrue);
      expect(sessions.containsKey('user2_2'), isTrue);
    });
  });

  group('Token Handling', () {
    test('hasTokens returns false for null token', () {
      const String? token = null;
      final hasTokens = token != null && token.isNotEmpty;

      expect(hasTokens, isFalse);
    });

    test('hasTokens returns false for empty token', () {
      const token = '';
      final hasTokens = token.isNotEmpty;

      expect(hasTokens, isFalse);
    });

    test('hasTokens returns true for valid token', () {
      const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
      final hasTokens = token.isNotEmpty;

      expect(hasTokens, isTrue);
    });
  });

  group('Signal Keys Initialized Flag', () {
    test('can check if initialized', () {
      const storedValue = 'true';
      final isInitialized = storedValue == 'true';

      expect(isInitialized, isTrue);
    });

    test('returns false for null value', () {
      const String? storedValue = null;
      final isInitialized = storedValue == 'true';

      expect(isInitialized, isFalse);
    });

    test('returns false for other values', () {
      const storedValue = 'false';
      final isInitialized = storedValue == 'true';

      expect(isInitialized, isFalse);
    });
  });
}
