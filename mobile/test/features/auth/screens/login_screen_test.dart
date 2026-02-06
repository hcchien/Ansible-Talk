import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ansible_talk/features/auth/screens/login_screen.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('renders all UI elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Verify app title is displayed
      expect(find.text('Ansible Talk'), findsOneWidget);

      // Verify subtitle is displayed
      expect(
        find.text('Secure messaging with end-to-end encryption'),
        findsOneWidget,
      );

      // Verify segmented button for auth type exists
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);

      // Verify Send OTP button exists
      expect(find.text('Send OTP'), findsOneWidget);

      // Verify Register link exists
      expect(find.text("Don't have an account? "), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('shows email input by default', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Email label should be shown
      expect(find.text('Email'), findsWidgets);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });

    testWidgets('switches to phone input when phone is selected',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Tap on Phone button in SegmentedButton
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();

      // Phone icon should be visible
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
    });

    testWidgets('validates empty email field', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Tap Send OTP without entering anything
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('validates invalid email format', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Enter invalid email
      await tester.enterText(find.byType(TextFormField), 'invalid-email');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('accepts valid email format', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Enter valid email
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send OTP'));
      await tester.pump();

      // Should not show email validation error
      expect(find.text('Please enter a valid email'), findsNothing);
      expect(find.text('Please enter your email'), findsNothing);
    });

    testWidgets('validates empty phone field', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Switch to phone
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();

      // Tap Send OTP without entering anything
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter your phone number'), findsOneWidget);
    });

    testWidgets('clears input when switching auth type',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Enter email
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.pump();

      // Switch to phone
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();

      // Input should be cleared
      final textField = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('shows lock icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Verify lock icon is displayed
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}
