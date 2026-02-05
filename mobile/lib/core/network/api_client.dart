import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';

class ApiClient {
  late final Dio _dio;
  final SecureStorage _storage;

  static const String baseUrl = 'http://localhost:8080/api/v1';

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh token
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Retry the request
            final token = await _storage.getAccessToken();
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await _dio.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        return handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final tokens = response.data['tokens'];
      await _storage.saveTokens(
        tokens['access_token'],
        tokens['refresh_token'],
      );
      return true;
    } catch (e) {
      await _storage.clearTokens();
      return false;
    }
  }

  // Auth endpoints
  Future<Response> sendOTP(String target, String type) async {
    return _dio.post('/auth/otp/send', data: {
      'target': target,
      'type': type,
    });
  }

  Future<Response> verifyOTP(String target, String type, String code) async {
    return _dio.post('/auth/otp/verify', data: {
      'target': target,
      'type': type,
      'code': code,
    });
  }

  Future<Response> register({
    String? phone,
    String? email,
    required String username,
    required String displayName,
    required String deviceName,
    required String platform,
  }) async {
    return _dio.post('/auth/register', data: {
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      'username': username,
      'display_name': displayName,
      'device_name': deviceName,
      'platform': platform,
    });
  }

  Future<Response> login({
    required String target,
    required String type,
    required String deviceName,
    required String platform,
  }) async {
    return _dio.post('/auth/login', data: {
      'target': target,
      'type': type,
      'device_name': deviceName,
      'platform': platform,
    });
  }

  Future<Response> logout() async {
    return _dio.post('/auth/logout');
  }

  // User endpoints
  Future<Response> getCurrentUser() async {
    return _dio.get('/users/me');
  }

  Future<Response> updateCurrentUser(Map<String, dynamic> data) async {
    return _dio.put('/users/me', data: data);
  }

  Future<Response> searchUsers(String query, {int limit = 20}) async {
    return _dio.get('/users/search', queryParameters: {
      'q': query,
      'limit': limit,
    });
  }

  // Contact endpoints
  Future<Response> getContacts({bool includeBlocked = false}) async {
    return _dio.get('/contacts', queryParameters: {
      'include_blocked': includeBlocked,
    });
  }

  Future<Response> addContact(String contactId, {String? nickname}) async {
    return _dio.post('/contacts', data: {
      'contact_id': contactId,
      if (nickname != null) 'nickname': nickname,
    });
  }

  Future<Response> getContact(String contactId) async {
    return _dio.get('/contacts/$contactId');
  }

  Future<Response> updateContact(String contactId, Map<String, dynamic> data) async {
    return _dio.put('/contacts/$contactId', data: data);
  }

  Future<Response> deleteContact(String contactId) async {
    return _dio.delete('/contacts/$contactId');
  }

  Future<Response> blockContact(String contactId) async {
    return _dio.post('/contacts/$contactId/block');
  }

  Future<Response> unblockContact(String contactId) async {
    return _dio.post('/contacts/$contactId/unblock');
  }

  Future<Response> getBlockedContacts() async {
    return _dio.get('/contacts/blocked');
  }

  Future<Response> syncContacts(List<String> identifiers) async {
    return _dio.post('/contacts/sync', data: {
      'identifiers': identifiers,
    });
  }

  // Conversation endpoints
  Future<Response> getConversations({int limit = 20, int offset = 0}) async {
    return _dio.get('/conversations', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> createDirectConversation(String userId) async {
    return _dio.post('/conversations/direct', data: {
      'user_id': userId,
    });
  }

  Future<Response> createGroupConversation(String name, List<String> memberIds) async {
    return _dio.post('/conversations/group', data: {
      'name': name,
      'member_ids': memberIds,
    });
  }

  Future<Response> getConversation(String conversationId) async {
    return _dio.get('/conversations/$conversationId');
  }

  Future<Response> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return _dio.get('/conversations/$conversationId/messages', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> sendMessage(
    String conversationId, {
    required String type,
    required List<int> content,
    String? stickerId,
    String? replyToId,
  }) async {
    return _dio.post('/conversations/$conversationId/messages', data: {
      'type': type,
      'content': content,
      if (stickerId != null) 'sticker_id': stickerId,
      if (replyToId != null) 'reply_to_id': replyToId,
    });
  }

  Future<Response> sendTyping(String conversationId, bool isTyping) async {
    return _dio.post('/conversations/$conversationId/typing', data: {
      'is_typing': isTyping,
    });
  }

  // Message endpoints
  Future<Response> markDelivered(String messageId) async {
    return _dio.post('/messages/$messageId/delivered');
  }

  Future<Response> markRead(String messageId) async {
    return _dio.post('/messages/$messageId/read');
  }

  Future<Response> deleteMessage(String messageId) async {
    return _dio.delete('/messages/$messageId');
  }

  // Signal keys endpoints
  Future<Response> registerKeys(Map<String, dynamic> keys) async {
    return _dio.post('/keys/register', data: keys);
  }

  Future<Response> getKeyBundle(String userId, int deviceId) async {
    return _dio.get('/keys/bundle/$userId/$deviceId');
  }

  Future<Response> getPreKeyCount(int deviceId) async {
    return _dio.get('/keys/count', queryParameters: {
      'device_id': deviceId,
    });
  }

  Future<Response> refreshPreKeys(int deviceId, List<Map<String, dynamic>> preKeys) async {
    return _dio.post('/keys/prekeys', data: {
      'device_id': deviceId,
      'pre_keys': preKeys,
    });
  }

  // Sticker endpoints
  Future<Response> getStickerCatalog({int limit = 20, int offset = 0, bool? official}) async {
    return _dio.get('/stickers/catalog', queryParameters: {
      'limit': limit,
      'offset': offset,
      if (official != null) 'official': official,
    });
  }

  Future<Response> searchStickers(String query, {int limit = 20}) async {
    return _dio.get('/stickers/search', queryParameters: {
      'q': query,
      'limit': limit,
    });
  }

  Future<Response> getStickerPack(String packId) async {
    return _dio.get('/stickers/packs/$packId');
  }

  Future<Response> downloadStickerPack(String packId) async {
    return _dio.post('/stickers/packs/$packId/download');
  }

  Future<Response> removeStickerPack(String packId) async {
    return _dio.delete('/stickers/packs/$packId');
  }

  Future<Response> getUserStickerPacks() async {
    return _dio.get('/stickers/my-packs');
  }

  Future<Response> reorderStickerPacks(List<String> packIds) async {
    return _dio.put('/stickers/my-packs/reorder', data: {
      'pack_ids': packIds,
    });
  }
}

// Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage);
});
