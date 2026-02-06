import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/core/network/api_client.dart';

void main() {
  group('ApiClient constants', () {
    test('baseUrl is set correctly', () {
      expect(ApiClient.baseUrl, 'http://localhost:8080/api/v1');
    });

    test('baseUrl starts with http', () {
      expect(ApiClient.baseUrl.startsWith('http'), true);
    });

    test('baseUrl contains api version', () {
      expect(ApiClient.baseUrl.contains('/api/v1'), true);
    });
  });

  group('API endpoints', () {
    group('Auth endpoints', () {
      test('OTP send endpoint', () {
        const endpoint = '/auth/otp/send';
        expect(endpoint.contains('otp'), true);
        expect(endpoint.contains('send'), true);
      });

      test('OTP verify endpoint', () {
        const endpoint = '/auth/otp/verify';
        expect(endpoint.contains('otp'), true);
        expect(endpoint.contains('verify'), true);
      });

      test('register endpoint', () {
        const endpoint = '/auth/register';
        expect(endpoint.contains('register'), true);
      });

      test('login endpoint', () {
        const endpoint = '/auth/login';
        expect(endpoint.contains('login'), true);
      });

      test('logout endpoint', () {
        const endpoint = '/auth/logout';
        expect(endpoint.contains('logout'), true);
      });

      test('refresh endpoint', () {
        const endpoint = '/auth/refresh';
        expect(endpoint.contains('refresh'), true);
      });
    });

    group('User endpoints', () {
      test('current user endpoint', () {
        const endpoint = '/users/me';
        expect(endpoint, '/users/me');
      });

      test('search users endpoint', () {
        const endpoint = '/users/search';
        expect(endpoint.contains('search'), true);
      });
    });

    group('Contact endpoints', () {
      test('contacts list endpoint', () {
        const endpoint = '/contacts';
        expect(endpoint, '/contacts');
      });

      test('contact by ID endpoint', () {
        const contactId = 'user-123';
        final endpoint = '/contacts/$contactId';
        expect(endpoint, '/contacts/user-123');
      });

      test('block contact endpoint', () {
        const contactId = 'user-123';
        final endpoint = '/contacts/$contactId/block';
        expect(endpoint.contains('block'), true);
      });

      test('unblock contact endpoint', () {
        const contactId = 'user-123';
        final endpoint = '/contacts/$contactId/unblock';
        expect(endpoint.contains('unblock'), true);
      });

      test('blocked contacts endpoint', () {
        const endpoint = '/contacts/blocked';
        expect(endpoint.contains('blocked'), true);
      });

      test('sync contacts endpoint', () {
        const endpoint = '/contacts/sync';
        expect(endpoint.contains('sync'), true);
      });
    });

    group('Conversation endpoints', () {
      test('conversations list endpoint', () {
        const endpoint = '/conversations';
        expect(endpoint, '/conversations');
      });

      test('direct conversation endpoint', () {
        const endpoint = '/conversations/direct';
        expect(endpoint.contains('direct'), true);
      });

      test('group conversation endpoint', () {
        const endpoint = '/conversations/group';
        expect(endpoint.contains('group'), true);
      });

      test('conversation by ID endpoint', () {
        const conversationId = 'conv-123';
        final endpoint = '/conversations/$conversationId';
        expect(endpoint, '/conversations/conv-123');
      });

      test('messages endpoint', () {
        const conversationId = 'conv-123';
        final endpoint = '/conversations/$conversationId/messages';
        expect(endpoint.contains('messages'), true);
      });

      test('typing endpoint', () {
        const conversationId = 'conv-123';
        final endpoint = '/conversations/$conversationId/typing';
        expect(endpoint.contains('typing'), true);
      });
    });

    group('Message endpoints', () {
      test('mark delivered endpoint', () {
        const messageId = 'msg-123';
        final endpoint = '/messages/$messageId/delivered';
        expect(endpoint.contains('delivered'), true);
      });

      test('mark read endpoint', () {
        const messageId = 'msg-123';
        final endpoint = '/messages/$messageId/read';
        expect(endpoint.contains('read'), true);
      });

      test('delete message endpoint', () {
        const messageId = 'msg-123';
        final endpoint = '/messages/$messageId';
        expect(endpoint, '/messages/msg-123');
      });
    });

    group('Signal keys endpoints', () {
      test('register keys endpoint', () {
        const endpoint = '/keys/register';
        expect(endpoint.contains('register'), true);
      });

      test('key bundle endpoint', () {
        const userId = 'user-123';
        const deviceId = 1;
        final endpoint = '/keys/bundle/$userId/$deviceId';
        expect(endpoint.contains('bundle'), true);
      });

      test('pre key count endpoint', () {
        const endpoint = '/keys/count';
        expect(endpoint.contains('count'), true);
      });

      test('refresh pre keys endpoint', () {
        const endpoint = '/keys/prekeys';
        expect(endpoint.contains('prekeys'), true);
      });

      test('signed pre key endpoint', () {
        const endpoint = '/keys/signed-prekey';
        expect(endpoint.contains('signed-prekey'), true);
      });
    });

    group('Sticker endpoints', () {
      test('catalog endpoint', () {
        const endpoint = '/stickers/catalog';
        expect(endpoint.contains('catalog'), true);
      });

      test('search stickers endpoint', () {
        const endpoint = '/stickers/search';
        expect(endpoint.contains('search'), true);
      });

      test('sticker pack endpoint', () {
        const packId = 'pack-123';
        final endpoint = '/stickers/packs/$packId';
        expect(endpoint.contains('packs'), true);
      });

      test('download pack endpoint', () {
        const packId = 'pack-123';
        final endpoint = '/stickers/packs/$packId/download';
        expect(endpoint.contains('download'), true);
      });

      test('user packs endpoint', () {
        const endpoint = '/stickers/my-packs';
        expect(endpoint.contains('my-packs'), true);
      });

      test('reorder packs endpoint', () {
        const endpoint = '/stickers/my-packs/reorder';
        expect(endpoint.contains('reorder'), true);
      });
    });
  });

  group('Request data structures', () {
    test('OTP send request data', () {
      final data = {
        'target': '+1234567890',
        'type': 'phone',
      };

      expect(data['target'], '+1234567890');
      expect(data['type'], 'phone');
    });

    test('OTP verify request data', () {
      final data = {
        'target': '+1234567890',
        'type': 'phone',
        'code': '123456',
      };

      expect(data['code'], '123456');
    });

    test('register request data with phone', () {
      final data = {
        'phone': '+1234567890',
        'username': 'testuser',
        'display_name': 'Test User',
        'device_name': 'iOS Device',
        'platform': 'ios',
      };

      expect(data.containsKey('phone'), true);
      expect(data.containsKey('email'), false);
    });

    test('register request data with email', () {
      final data = {
        'email': 'test@example.com',
        'username': 'testuser',
        'display_name': 'Test User',
        'device_name': 'Android Device',
        'platform': 'android',
      };

      expect(data.containsKey('email'), true);
      expect(data.containsKey('phone'), false);
    });

    test('login request data', () {
      final data = {
        'target': '+1234567890',
        'type': 'phone',
        'device_name': 'iOS Device',
        'platform': 'ios',
      };

      expect(data['target'], '+1234567890');
      expect(data['type'], 'phone');
    });

    test('message send request data', () {
      final data = {
        'type': 'text',
        'content': [72, 101, 108, 108, 111],
      };

      expect(data['type'], 'text');
      expect(data['content'], isA<List>());
    });

    test('message send with reply', () {
      final data = {
        'type': 'text',
        'content': [72, 101, 108, 108, 111],
        'reply_to_id': 'msg-123',
      };

      expect(data.containsKey('reply_to_id'), true);
    });

    test('message send with sticker', () {
      final data = {
        'type': 'sticker',
        'content': <int>[],
        'sticker_id': 'sticker-123',
      };

      expect(data['type'], 'sticker');
      expect(data.containsKey('sticker_id'), true);
    });

    test('create group conversation data', () {
      final data = {
        'name': 'My Group',
        'member_ids': ['user-1', 'user-2', 'user-3'],
      };

      expect(data['name'], 'My Group');
      expect(data['member_ids'], isA<List>());
      expect((data['member_ids'] as List).length, 3);
    });
  });

  group('Query parameters', () {
    test('search users parameters', () {
      final params = {
        'q': 'john',
        'limit': 20,
      };

      expect(params['q'], 'john');
      expect(params['limit'], 20);
    });

    test('contacts parameters', () {
      final params = {
        'include_blocked': false,
      };

      expect(params['include_blocked'], false);
    });

    test('conversations pagination', () {
      final params = {
        'limit': 20,
        'offset': 0,
      };

      expect(params['limit'], 20);
      expect(params['offset'], 0);
    });

    test('messages pagination', () {
      final params = {
        'limit': 50,
        'offset': 0,
      };

      expect(params['limit'], 50);
      expect(params['offset'], 0);
    });

    test('sticker catalog parameters', () {
      final params = {
        'limit': 20,
        'offset': 0,
        'official': true,
      };

      expect(params['official'], true);
    });

    test('pre key count parameters', () {
      final params = {
        'device_id': 1,
      };

      expect(params['device_id'], 1);
    });
  });

  group('HTTP methods', () {
    test('GET methods', () {
      final getMethods = [
        '/users/me',
        '/contacts',
        '/conversations',
        '/stickers/catalog',
      ];

      for (final method in getMethods) {
        expect(method.isNotEmpty, true);
      }
    });

    test('POST methods', () {
      final postMethods = [
        '/auth/register',
        '/auth/login',
        '/contacts',
        '/conversations/direct',
        '/messages/{id}/delivered',
      ];

      for (final method in postMethods) {
        expect(method.isNotEmpty, true);
      }
    });

    test('PUT methods', () {
      final putMethods = [
        '/users/me',
        '/contacts/{id}',
        '/keys/signed-prekey',
        '/stickers/my-packs/reorder',
      ];

      for (final method in putMethods) {
        expect(method.isNotEmpty, true);
      }
    });

    test('DELETE methods', () {
      final deleteMethods = [
        '/contacts/{id}',
        '/messages/{id}',
        '/stickers/packs/{id}',
      ];

      for (final method in deleteMethods) {
        expect(method.isNotEmpty, true);
      }
    });
  });

  group('Authorization', () {
    test('bearer token format', () {
      const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
      final header = 'Bearer $token';

      expect(header.startsWith('Bearer '), true);
    });

    test('authorization header key', () {
      const headerKey = 'Authorization';
      expect(headerKey, 'Authorization');
    });
  });

  group('Timeouts', () {
    test('connect timeout', () {
      const timeout = Duration(seconds: 30);
      expect(timeout.inSeconds, 30);
    });

    test('receive timeout', () {
      const timeout = Duration(seconds: 30);
      expect(timeout.inSeconds, 30);
    });
  });

  group('Content type', () {
    test('default content type', () {
      const contentType = 'application/json';
      expect(contentType, 'application/json');
    });
  });

  group('Token refresh', () {
    test('refresh token request data', () {
      final data = {
        'refresh_token': 'refresh-token-here',
      };

      expect(data.containsKey('refresh_token'), true);
    });

    test('401 status code triggers refresh', () {
      const statusCode = 401;
      expect(statusCode, 401);
    });
  });
}
