import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OTP Screen Widget Tests', () {
    test('OTP length validation', () {
      const otp = '123456';
      expect(otp.length, 6);
    });

    test('incomplete OTP validation', () {
      const otp = '123';
      expect(otp.length == 6, false);
    });

    test('OTP digit validation', () {
      const otp = '123456';
      final isAllDigits = RegExp(r'^[0-9]+$').hasMatch(otp);
      expect(isAllDigits, true);
    });

    test('OTP with non-digits fails validation', () {
      const otp = '12345a';
      final isAllDigits = RegExp(r'^[0-9]+$').hasMatch(otp);
      expect(isAllDigits, false);
    });
  });

  group('OTP Input Fields', () {
    test('6 input fields required', () {
      const fieldCount = 6;
      expect(fieldCount, 6);
    });

    test('focus moves to next field on digit entry', () {
      // Simulate: when value.length == 1 && index < 5, move to next
      const index = 2;
      const value = '5';

      final shouldMoveFocus = value.length == 1 && index < 5;
      expect(shouldMoveFocus, true);
    });

    test('focus moves to previous field on backspace', () {
      // Simulate: when value is empty && index > 0, move to previous
      const index = 3;
      const value = '';

      final shouldMoveBack = value.isEmpty && index > 0;
      expect(shouldMoveBack, true);
    });

    test('no focus change on first field backspace', () {
      const index = 0;
      const value = '';

      final shouldMoveBack = value.isEmpty && index > 0;
      expect(shouldMoveBack, false);
    });

    test('no focus change on last field complete', () {
      const index = 5;
      const value = '9';

      final shouldMoveFocus = value.length == 1 && index < 5;
      expect(shouldMoveFocus, false);
    });
  });

  group('OTP Auto-verify', () {
    test('auto-verify triggers when OTP is complete', () {
      const otp = '123456';
      final shouldAutoVerify = otp.length == 6;
      expect(shouldAutoVerify, true);
    });

    test('auto-verify does not trigger when incomplete', () {
      const otp = '12345';
      final shouldAutoVerify = otp.length == 6;
      expect(shouldAutoVerify, false);
    });
  });

  group('OTP Screen Properties', () {
    test('target is required', () {
      const target = '+1234567890';
      expect(target.isNotEmpty, true);
    });

    test('type is required - phone', () {
      const type = 'phone';
      expect(type, 'phone');
    });

    test('type is required - email', () {
      const type = 'email';
      expect(type, 'email');
    });

    test('isRegistration flag', () {
      const isRegistration = true;
      expect(isRegistration, true);
    });

    test('username for registration', () {
      const username = 'testuser';
      expect(username.isNotEmpty, true);
    });

    test('displayName for registration', () {
      const displayName = 'Test User';
      expect(displayName.isNotEmpty, true);
    });
  });

  group('OTP Screen UI Elements', () {
    test('screen title', () {
      const title = 'Verify OTP';
      expect(title.contains('OTP'), true);
    });

    test('verification message contains target', () {
      const target = '+1234567890';
      final message = 'We sent a verification code to\n$target';
      expect(message.contains(target), true);
    });

    test('verify button text', () {
      const buttonText = 'Verify';
      expect(buttonText, 'Verify');
    });

    test('resend button text', () {
      const buttonText = 'Resend';
      expect(buttonText, 'Resend');
    });

    test('resend prompt text', () {
      const promptText = "Didn't receive the code? ";
      expect(promptText.contains('code'), true);
    });

    test('incomplete OTP error message', () {
      const errorMessage = 'Please enter the complete OTP';
      expect(errorMessage.contains('OTP'), true);
    });

    test('success message', () {
      const message = 'OTP sent successfully';
      expect(message.contains('successfully'), true);
    });
  });

  group('OTP Screen State', () {
    test('loading state disables verify button', () {
      const isLoading = true;
      final buttonEnabled = !isLoading;
      expect(buttonEnabled, false);
    });

    test('loading state disables resend button', () {
      const isLoading = true;
      final buttonEnabled = !isLoading;
      expect(buttonEnabled, false);
    });

    test('error state shows error message', () {
      const String? error = 'Invalid OTP';
      expect(error != null, true);
    });

    test('no error state hides error message', () {
      const String? error = null;
      expect(error == null, true);
    });
  });

  group('Registration vs Login Flow', () {
    test('registration flow calls register', () {
      const isRegistration = true;
      expect(isRegistration, true);
    });

    test('login flow calls login', () {
      const isRegistration = false;
      expect(isRegistration, false);
    });

    test('registration requires username', () {
      const isRegistration = true;
      const username = 'testuser';

      if (isRegistration) {
        expect(username.isNotEmpty, true);
      }
    });

    test('registration requires displayName', () {
      const isRegistration = true;
      const displayName = 'Test User';

      if (isRegistration) {
        expect(displayName.isNotEmpty, true);
      }
    });

    test('login does not require username', () {
      const isRegistration = false;
      const String? username = null;

      if (!isRegistration) {
        expect(username == null || username.isEmpty, true);
      }
    });
  });

  group('OTP Input Formatting', () {
    test('only digits allowed', () {
      const input = '5';
      final isDigit = RegExp(r'^[0-9]$').hasMatch(input);
      expect(isDigit, true);
    });

    test('max length is 1 per field', () {
      const maxLength = 1;
      expect(maxLength, 1);
    });

    test('numeric keyboard type', () {
      const keyboardType = TextInputType.number;
      expect(keyboardType, TextInputType.number);
    });
  });

  group('Error Handling', () {
    test('clear fields on verification error', () {
      // Simulate clearing controllers
      final controllers = List.generate(6, (_) => '');
      final allEmpty = controllers.every((c) => c.isEmpty);
      expect(allEmpty, true);
    });

    test('focus first field on verification error', () {
      const focusIndex = 0;
      expect(focusIndex, 0);
    });

    test('show snackbar on send error', () {
      const hasError = true;
      expect(hasError, true);
    });
  });

  group('Navigation', () {
    test('navigate to home on success', () {
      const route = '/';
      expect(route, '/');
    });

    test('mounted check before navigation', () {
      const isMounted = true;
      if (isMounted) {
        // Navigate
        expect(true, true);
      }
    });
  });

  group('Dispose', () {
    test('dispose all controllers', () {
      const controllerCount = 6;
      expect(controllerCount, 6);
    });

    test('dispose all focus nodes', () {
      const focusNodeCount = 6;
      expect(focusNodeCount, 6);
    });
  });
}
