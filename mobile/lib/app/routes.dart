import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/otp_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/chat/screens/conversations_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/contacts/screens/contacts_screen.dart';
import '../features/contacts/screens/add_contact_screen.dart';
import '../features/stickers/screens/sticker_store_screen.dart';
import '../features/stickers/screens/my_stickers_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.isLoggedIn;
      final isLoggingIn = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isLoggingIn) {
        return '/auth/login';
      }

      if (isLoggedIn && isLoggingIn) {
        return '/';
      }

      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/auth/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        name: 'otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OTPScreen(
            target: extra?['target'] ?? '',
            type: extra?['type'] ?? 'email',
            isRegistration: extra?['isRegistration'] ?? false,
          );
        },
      ),

      // Main app routes with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'conversations',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ConversationsScreen(),
            ),
          ),
          GoRoute(
            path: '/contacts',
            name: 'contacts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ContactsScreen(),
            ),
          ),
          GoRoute(
            path: '/stickers',
            name: 'myStickers',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MyStickersScreen(),
            ),
          ),
        ],
      ),

      // Chat screen
      GoRoute(
        path: '/chat/:conversationId',
        name: 'chat',
        builder: (context, state) => ChatScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),

      // Add contact
      GoRoute(
        path: '/contacts/add',
        name: 'addContact',
        builder: (context, state) => const AddContactScreen(),
      ),

      // Sticker store
      GoRoute(
        path: '/stickers/store',
        name: 'stickerStore',
        builder: (context, state) => const StickerStoreScreen(),
      ),
    ],
  );
});

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: const MainBottomNavBar(),
    );
  }
}

class MainBottomNavBar extends ConsumerWidget {
  const MainBottomNavBar({super.key});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/contacts')) return 1;
    if (location.startsWith('/stickers')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _calculateSelectedIndex(context);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.goNamed('conversations');
            break;
          case 1:
            context.goNamed('contacts');
            break;
          case 2:
            context.goNamed('myStickers');
            break;
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Chats',
        ),
        NavigationDestination(
          icon: Icon(Icons.contacts_outlined),
          selectedIcon: Icon(Icons.contacts),
          label: 'Contacts',
        ),
        NavigationDestination(
          icon: Icon(Icons.emoji_emotions_outlined),
          selectedIcon: Icon(Icons.emoji_emotions),
          label: 'Stickers',
        ),
      ],
    );
  }
}
