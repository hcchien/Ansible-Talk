import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/websocket_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/crypto/signal_client.dart';
import '../../../shared/models/user.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final User? user;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    User? user,
    String? error,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final SecureStorage _storage;
  final WebSocketClient _wsClient;
  final SignalClient _signalClient;

  AuthNotifier(
    this._apiClient,
    this._storage,
    this._wsClient,
    this._signalClient,
  ) : super(const AuthState()) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    try {
      final hasTokens = await _storage.hasTokens();
      if (hasTokens) {
        // Try to get current user
        final response = await _apiClient.getCurrentUser();
        final user = User.fromJson(response.data);
        state = state.copyWith(
          isLoggedIn: true,
          isLoading: false,
          user: user,
        );

        // Connect WebSocket
        await _wsClient.connect();
      } else {
        state = state.copyWith(isLoggedIn: false, isLoading: false);
      }
    } catch (e) {
      // Token might be invalid, clear and logout
      await _storage.clearTokens();
      state = state.copyWith(isLoggedIn: false, isLoading: false);
    }
  }

  Future<void> sendOTP(String target, String type) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _apiClient.sendOTP(target, type);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to send OTP. Please try again.',
      );
      rethrow;
    }
  }

  Future<bool> verifyOTP(String target, String type, String code) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _apiClient.verifyOTP(target, type, code);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Invalid OTP. Please try again.',
      );
      return false;
    }
  }

  Future<void> register({
    String? phone,
    String? email,
    required String username,
    required String displayName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.register(
        phone: phone,
        email: email,
        username: username,
        displayName: displayName,
        deviceName: _getDeviceName(),
        platform: _getPlatform(),
      );

      final user = User.fromJson(response.data['user']);
      final tokens = TokenPair.fromJson(response.data['tokens']);

      // Save tokens
      await _storage.saveTokens(tokens.accessToken, tokens.refreshToken);
      await _storage.saveUserId(user.id);

      // Initialize Signal keys
      await _signalClient.initializeKeys();

      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        user: user,
      );

      // Connect WebSocket
      await _wsClient.connect();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Registration failed. Please try again.',
      );
      rethrow;
    }
  }

  Future<void> login(String target, String type) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.login(
        target: target,
        type: type,
        deviceName: _getDeviceName(),
        platform: _getPlatform(),
      );

      final user = User.fromJson(response.data['user']);
      final tokens = TokenPair.fromJson(response.data['tokens']);

      // Save tokens
      await _storage.saveTokens(tokens.accessToken, tokens.refreshToken);
      await _storage.saveUserId(user.id);

      // Initialize Signal keys if needed
      await _signalClient.initializeKeys();

      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        user: user,
      );

      // Connect WebSocket
      await _wsClient.connect();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Login failed. Please try again.',
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      await _apiClient.logout();
    } catch (e) {
      // Ignore errors during logout
    }

    // Disconnect WebSocket
    _wsClient.disconnect();

    // Clear local data
    await _storage.clearTokens();

    state = const AuthState(isLoggedIn: false, isLoading: false);
  }

  Future<void> updateProfile({String? displayName, String? username, String? bio}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = <String, dynamic>{};
      if (displayName != null) data['display_name'] = displayName;
      if (username != null) data['username'] = username;
      if (bio != null) data['bio'] = bio;

      final response = await _apiClient.updateCurrentUser(data);
      final user = User.fromJson(response.data);

      state = state.copyWith(isLoading: false, user: user);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update profile.',
      );
      rethrow;
    }
  }

  String _getDeviceName() {
    if (Platform.isIOS) return 'iOS Device';
    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isMacOS) return 'macOS Device';
    if (Platform.isWindows) return 'Windows Device';
    if (Platform.isLinux) return 'Linux Device';
    return 'Unknown Device';
  }

  String _getPlatform() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

// Providers
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final storage = ref.watch(secureStorageProvider);
  final wsClient = ref.watch(webSocketClientProvider);
  final signalClient = ref.watch(signalClientProvider);
  return AuthNotifier(apiClient, storage, wsClient, signalClient);
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).user;
});
