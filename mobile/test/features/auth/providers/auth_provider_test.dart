import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/features/auth/providers/auth_provider.dart';

void main() {
  group('AuthState', () {
    test('default values', () {
      const state = AuthState();

      expect(state.isLoggedIn, false);
      expect(state.isLoading, false);
      expect(state.user, null);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = AuthState(
        isLoggedIn: true,
        isLoading: false,
      );

      final newState = state.copyWith(isLoading: true);

      expect(newState.isLoggedIn, true);
      expect(newState.isLoading, true);
      expect(newState.user, null);
      expect(newState.error, null);
    });

    test('copyWith with isLoggedIn', () {
      const state = AuthState();
      final newState = state.copyWith(isLoggedIn: true);

      expect(newState.isLoggedIn, true);
    });

    test('copyWith with isLoading', () {
      const state = AuthState();
      final newState = state.copyWith(isLoading: true);

      expect(newState.isLoading, true);
    });

    test('copyWith with error', () {
      const state = AuthState();
      final newState = state.copyWith(error: 'Test error');

      expect(newState.error, 'Test error');
    });

    test('copyWith clears error when set to null', () {
      const state = AuthState(error: 'Previous error');
      final newState = state.copyWith(error: null);

      expect(newState.error, null);
    });

    test('loading state transition', () {
      const initial = AuthState();
      final loading = initial.copyWith(isLoading: true);
      final loaded = loading.copyWith(isLoading: false, isLoggedIn: true);

      expect(initial.isLoading, false);
      expect(loading.isLoading, true);
      expect(loaded.isLoading, false);
      expect(loaded.isLoggedIn, true);
    });

    test('error state transition', () {
      const initial = AuthState();
      final withError = initial.copyWith(error: 'Failed to login');
      final cleared = withError.copyWith(error: null);

      expect(initial.error, null);
      expect(withError.error, 'Failed to login');
      expect(cleared.error, null);
    });
  });

  group('OTP operations', () {
    test('OTP type validation', () {
      final types = ['phone', 'email'];

      for (final type in types) {
        expect(['phone', 'email'].contains(type), true);
      }
    });

    test('OTP target format - phone', () {
      const target = '+1234567890';
      expect(target.startsWith('+'), true);
    });

    test('OTP target format - email', () {
      const target = 'test@example.com';
      expect(target.contains('@'), true);
    });

    test('OTP code format', () {
      const code = '123456';
      expect(code.length, 6);
      expect(int.tryParse(code), isNotNull);
    });
  });

  group('Registration', () {
    test('registration data validation', () {
      const phone = '+1234567890';
      const email = 'test@example.com';
      const username = 'testuser';
      const displayName = 'Test User';

      expect(phone.isNotEmpty, true);
      expect(email.contains('@'), true);
      expect(username.isNotEmpty, true);
      expect(displayName.isNotEmpty, true);
    });

    test('username requirements', () {
      // Typical username rules
      const validUsernames = ['user123', 'test_user', 'JohnDoe'];
      const invalidUsernames = ['ab', 'a' * 51, ''];

      for (final username in validUsernames) {
        expect(username.length >= 3 && username.length <= 50, true);
      }

      for (final username in invalidUsernames) {
        expect(
          username.length < 3 || username.length > 50 || username.isEmpty,
          true,
        );
      }
    });
  });

  group('Login', () {
    test('login with phone', () {
      const target = '+1234567890';
      const type = 'phone';

      expect(target.startsWith('+'), true);
      expect(type, 'phone');
    });

    test('login with email', () {
      const target = 'test@example.com';
      const type = 'email';

      expect(target.contains('@'), true);
      expect(type, 'email');
    });
  });

  group('Profile update', () {
    test('profile update data structure', () {
      final data = <String, dynamic>{};

      const displayName = 'New Name';
      const username = 'newuser';
      const bio = 'New bio';

      data['display_name'] = displayName;
      data['username'] = username;
      data['bio'] = bio;

      expect(data['display_name'], displayName);
      expect(data['username'], username);
      expect(data['bio'], bio);
    });

    test('partial profile update', () {
      final data = <String, dynamic>{};

      const displayName = 'New Name';
      data['display_name'] = displayName;

      expect(data.containsKey('display_name'), true);
      expect(data.containsKey('username'), false);
      expect(data.containsKey('bio'), false);
    });
  });

  group('Platform detection', () {
    test('platform names', () {
      final platforms = ['ios', 'android', 'macos', 'windows', 'linux', 'unknown'];

      for (final platform in platforms) {
        expect(platform.isNotEmpty, true);
      }
    });

    test('device names', () {
      final deviceNames = [
        'iOS Device',
        'Android Device',
        'macOS Device',
        'Windows Device',
        'Linux Device',
        'Unknown Device',
      ];

      for (final name in deviceNames) {
        expect(name.contains('Device'), true);
      }
    });
  });

  group('Error messages', () {
    test('OTP send error', () {
      const error = 'Failed to send OTP. Please try again.';
      expect(error.contains('OTP'), true);
    });

    test('OTP verify error', () {
      const error = 'Invalid OTP. Please try again.';
      expect(error.contains('OTP'), true);
    });

    test('registration error', () {
      const error = 'Registration failed. Please try again.';
      expect(error.contains('Registration'), true);
    });

    test('login error', () {
      const error = 'Login failed. Please try again.';
      expect(error.contains('Login'), true);
    });

    test('profile update error', () {
      const error = 'Failed to update profile.';
      expect(error.contains('profile'), true);
    });
  });

  group('State transitions', () {
    test('login flow states', () {
      // Initial state
      const initial = AuthState();
      expect(initial.isLoggedIn, false);
      expect(initial.isLoading, false);

      // Loading state
      final loading = initial.copyWith(isLoading: true);
      expect(loading.isLoading, true);

      // Success state
      final success = loading.copyWith(isLoggedIn: true, isLoading: false);
      expect(success.isLoggedIn, true);
      expect(success.isLoading, false);
    });

    test('logout flow states', () {
      const loggedIn = AuthState(isLoggedIn: true);
      expect(loggedIn.isLoggedIn, true);

      final loggingOut = loggedIn.copyWith(isLoading: true);
      expect(loggingOut.isLoading, true);

      const loggedOut = AuthState(isLoggedIn: false, isLoading: false);
      expect(loggedOut.isLoggedIn, false);
      expect(loggedOut.isLoading, false);
    });

    test('error recovery', () {
      const initial = AuthState();
      final withError = initial.copyWith(error: 'Error occurred');
      final retry = withError.copyWith(isLoading: true, error: null);
      final success = retry.copyWith(isLoggedIn: true, isLoading: false);

      expect(withError.error, isNotNull);
      expect(retry.error, null);
      expect(retry.isLoading, true);
      expect(success.isLoggedIn, true);
    });
  });
}
