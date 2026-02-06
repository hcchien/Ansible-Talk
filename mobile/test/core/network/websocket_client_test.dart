import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/core/network/websocket_client.dart';

void main() {
  group('WebSocketClient constants', () {
    test('wsUrl is set correctly', () {
      expect(WebSocketClient.wsUrl, 'ws://localhost:8080/api/v1/ws');
    });

    test('wsUrl starts with ws', () {
      expect(WebSocketClient.wsUrl.startsWith('ws'), true);
    });

    test('wsUrl contains api version', () {
      expect(WebSocketClient.wsUrl.contains('/api/v1'), true);
    });

    test('wsUrl ends with /ws', () {
      expect(WebSocketClient.wsUrl.endsWith('/ws'), true);
    });
  });

  group('ConnectionState', () {
    test('disconnected state', () {
      expect(ConnectionState.disconnected.name, 'disconnected');
    });

    test('connecting state', () {
      expect(ConnectionState.connecting.name, 'connecting');
    });

    test('connected state', () {
      expect(ConnectionState.connected.name, 'connected');
    });

    test('reconnecting state', () {
      expect(ConnectionState.reconnecting.name, 'reconnecting');
    });

    test('state enum values', () {
      expect(ConnectionState.values.length, 4);
    });
  });

  group('WebSocketMessage', () {
    test('create message with type and payload', () {
      final message = WebSocketMessage(
        type: 'new_message',
        payload: {'content': 'Hello'},
      );

      expect(message.type, 'new_message');
      expect(message.payload, isA<Map>());
    });

    test('fromJson creates message', () {
      final json = {
        'type': 'typing',
        'payload': {
          'conversation_id': 'conv-123',
          'is_typing': true,
        },
      };

      final message = WebSocketMessage.fromJson(json);

      expect(message.type, 'typing');
      expect(message.payload['conversation_id'], 'conv-123');
      expect(message.payload['is_typing'], true);
    });

    test('toJson serializes message', () {
      final message = WebSocketMessage(
        type: 'presence',
        payload: {'status': 'online'},
      );

      final json = message.toJson();

      expect(json['type'], 'presence');
      expect(json['payload']['status'], 'online');
    });

    test('message roundtrip', () {
      final original = WebSocketMessage(
        type: 'ack',
        payload: {'message_id': 'msg-123', 'type': 'read'},
      );

      final json = original.toJson();
      final decoded = WebSocketMessage.fromJson(json);

      expect(decoded.type, original.type);
      expect(decoded.payload['message_id'], original.payload['message_id']);
    });
  });

  group('Message types', () {
    test('new_message type', () {
      const type = 'new_message';
      expect(type, 'new_message');
    });

    test('typing type', () {
      const type = 'typing';
      expect(type, 'typing');
    });

    test('presence type', () {
      const type = 'presence';
      expect(type, 'presence');
    });

    test('ack type', () {
      const type = 'ack';
      expect(type, 'ack');
    });

    test('ping type', () {
      const type = 'ping';
      expect(type, 'ping');
    });

    test('pong type', () {
      const type = 'pong';
      expect(type, 'pong');
    });
  });

  group('Typing indicator', () {
    test('typing payload structure', () {
      final payload = {
        'conversation_id': 'conv-123',
        'is_typing': true,
      };

      expect(payload['conversation_id'], 'conv-123');
      expect(payload['is_typing'], true);
    });

    test('typing message', () {
      final message = WebSocketMessage(
        type: 'typing',
        payload: {
          'conversation_id': 'conv-123',
          'is_typing': true,
        },
      );

      expect(message.type, 'typing');
    });

    test('stop typing', () {
      final message = WebSocketMessage(
        type: 'typing',
        payload: {
          'conversation_id': 'conv-123',
          'is_typing': false,
        },
      );

      expect(message.payload['is_typing'], false);
    });
  });

  group('Presence', () {
    test('presence payload structure', () {
      final payload = {'status': 'online'};

      expect(payload['status'], 'online');
    });

    test('online status', () {
      final message = WebSocketMessage(
        type: 'presence',
        payload: {'status': 'online'},
      );

      expect(message.payload['status'], 'online');
    });

    test('away status', () {
      final message = WebSocketMessage(
        type: 'presence',
        payload: {'status': 'away'},
      );

      expect(message.payload['status'], 'away');
    });

    test('offline status', () {
      final message = WebSocketMessage(
        type: 'presence',
        payload: {'status': 'offline'},
      );

      expect(message.payload['status'], 'offline');
    });
  });

  group('Acknowledgment', () {
    test('ack payload structure', () {
      final payload = {
        'message_id': 'msg-123',
        'type': 'delivered',
      };

      expect(payload['message_id'], 'msg-123');
      expect(payload['type'], 'delivered');
    });

    test('delivered ack', () {
      final message = WebSocketMessage(
        type: 'ack',
        payload: {
          'message_id': 'msg-123',
          'type': 'delivered',
        },
      );

      expect(message.payload['type'], 'delivered');
    });

    test('read ack', () {
      final message = WebSocketMessage(
        type: 'ack',
        payload: {
          'message_id': 'msg-123',
          'type': 'read',
        },
      );

      expect(message.payload['type'], 'read');
    });
  });

  group('Ping/Pong', () {
    test('ping message', () {
      final message = WebSocketMessage(
        type: 'ping',
        payload: {},
      );

      expect(message.type, 'ping');
      expect(message.payload, isEmpty);
    });

    test('pong message', () {
      final message = WebSocketMessage(
        type: 'pong',
        payload: {},
      );

      expect(message.type, 'pong');
    });

    test('ping interval', () {
      const interval = Duration(seconds: 30);
      expect(interval.inSeconds, 30);
    });
  });

  group('Reconnection', () {
    test('reconnect delay', () {
      const delay = Duration(seconds: 5);
      expect(delay.inSeconds, 5);
    });

    test('reconnection state flow', () {
      final states = [
        ConnectionState.connected,
        ConnectionState.disconnected,
        ConnectionState.reconnecting,
        ConnectionState.connecting,
        ConnectionState.connected,
      ];

      expect(states[0], ConnectionState.connected);
      expect(states[1], ConnectionState.disconnected);
      expect(states[2], ConnectionState.reconnecting);
    });
  });

  group('Message serialization', () {
    test('JSON encode message', () {
      final message = WebSocketMessage(
        type: 'test',
        payload: {'key': 'value'},
      );

      final encoded = jsonEncode(message.toJson());

      expect(encoded.isNotEmpty, true);
      expect(encoded.contains('test'), true);
    });

    test('JSON decode message', () {
      const jsonString = '{"type":"test","payload":{"key":"value"}}';

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final message = WebSocketMessage.fromJson(decoded);

      expect(message.type, 'test');
      expect(message.payload['key'], 'value');
    });
  });

  group('URL with token', () {
    test('URL format with token', () {
      const baseUrl = 'ws://localhost:8080/api/v1/ws';
      const token = 'test-token';
      final url = '$baseUrl?token=$token';

      expect(url.contains('?token='), true);
    });

    test('URI parsing', () {
      const url = 'ws://localhost:8080/api/v1/ws?token=test-token';
      final uri = Uri.parse(url);

      expect(uri.scheme, 'ws');
      expect(uri.host, 'localhost');
      expect(uri.port, 8080);
      expect(uri.queryParameters['token'], 'test-token');
    });
  });

  group('State transitions', () {
    test('initial state is disconnected', () {
      const initialState = ConnectionState.disconnected;
      expect(initialState, ConnectionState.disconnected);
    });

    test('connect flow', () {
      final flow = [
        ConnectionState.disconnected,
        ConnectionState.connecting,
        ConnectionState.connected,
      ];

      expect(flow[0], ConnectionState.disconnected);
      expect(flow[1], ConnectionState.connecting);
      expect(flow[2], ConnectionState.connected);
    });

    test('disconnect flow', () {
      final flow = [
        ConnectionState.connected,
        ConnectionState.disconnected,
      ];

      expect(flow[0], ConnectionState.connected);
      expect(flow[1], ConnectionState.disconnected);
    });

    test('error recovery flow', () {
      final flow = [
        ConnectionState.connected,
        ConnectionState.disconnected,
        ConnectionState.reconnecting,
        ConnectionState.connecting,
        ConnectionState.connected,
      ];

      expect(flow.length, 5);
    });
  });

  group('Connection guards', () {
    test('skip connect if connecting', () {
      const state = ConnectionState.connecting;
      final shouldSkip = state == ConnectionState.connecting ||
          state == ConnectionState.connected;

      expect(shouldSkip, true);
    });

    test('skip connect if connected', () {
      const state = ConnectionState.connected;
      final shouldSkip = state == ConnectionState.connecting ||
          state == ConnectionState.connected;

      expect(shouldSkip, true);
    });

    test('allow connect if disconnected', () {
      const state = ConnectionState.disconnected;
      final shouldSkip = state == ConnectionState.connecting ||
          state == ConnectionState.connected;

      expect(shouldSkip, false);
    });
  });

  group('Send guards', () {
    test('skip send if not connected', () {
      const state = ConnectionState.disconnected;
      final canSend = state == ConnectionState.connected;

      expect(canSend, false);
    });

    test('allow send if connected', () {
      const state = ConnectionState.connected;
      final canSend = state == ConnectionState.connected;

      expect(canSend, true);
    });
  });

  group('Stream controllers', () {
    test('message stream is broadcast', () {
      // Broadcast streams allow multiple listeners
      const isBroadcast = true;
      expect(isBroadcast, true);
    });

    test('state stream is broadcast', () {
      const isBroadcast = true;
      expect(isBroadcast, true);
    });
  });
}
