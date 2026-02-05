import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../storage/secure_storage.dart';

enum ConnectionState { disconnected, connecting, connected, reconnecting }

class WebSocketMessage {
  final String type;
  final dynamic payload;

  WebSocketMessage({required this.type, required this.payload});

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] as String,
      payload: json['payload'],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
      };
}

class WebSocketClient {
  static const String wsUrl = 'ws://localhost:8080/api/v1/ws';

  final SecureStorage _storage;
  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _messageController = StreamController<WebSocketMessage>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();

  Stream<WebSocketMessage> get messages => _messageController.stream;
  Stream<ConnectionState> get connectionState => _stateController.stream;
  ConnectionState get state => _state;

  WebSocketClient(this._storage);

  Future<void> connect() async {
    if (_state == ConnectionState.connecting || _state == ConnectionState.connected) {
      return;
    }

    _updateState(ConnectionState.connecting);

    try {
      final token = await _storage.getAccessToken();
      if (token == null) {
        _updateState(ConnectionState.disconnected);
        return;
      }

      final uri = Uri.parse('$wsUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      _updateState(ConnectionState.connected);

      // Start ping timer
      _startPingTimer();

      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _updateState(ConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _updateState(ConnectionState.disconnected);
  }

  void send(WebSocketMessage message) {
    if (_state != ConnectionState.connected || _channel == null) {
      return;
    }

    _channel!.sink.add(jsonEncode(message.toJson()));
  }

  void sendTyping(String conversationId, bool isTyping) {
    send(WebSocketMessage(
      type: 'typing',
      payload: {
        'conversation_id': conversationId,
        'is_typing': isTyping,
      },
    ));
  }

  void sendPresence(String status) {
    send(WebSocketMessage(
      type: 'presence',
      payload: {'status': status},
    ));
  }

  void sendAck(String messageId, String type) {
    send(WebSocketMessage(
      type: 'ack',
      payload: {
        'message_id': messageId,
        'type': type,
      },
    ));
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final message = WebSocketMessage.fromJson(json);

      if (message.type == 'pong') {
        // Pong received, connection is alive
        return;
      }

      _messageController.add(message);
    } catch (e) {
      // Invalid message format
    }
  }

  void _onError(dynamic error) {
    _updateState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    _updateState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _updateState(ConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      send(WebSocketMessage(type: 'ping', payload: {}));
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _updateState(ConnectionState.reconnecting);
      connect();
    });
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}

// Provider
final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final client = WebSocketClient(storage);
  ref.onDispose(() => client.dispose());
  return client;
});

// Stream provider for messages
final webSocketMessagesProvider = StreamProvider<WebSocketMessage>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return client.messages;
});

// Stream provider for connection state
final webSocketStateProvider = StreamProvider<ConnectionState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return client.connectionState;
});
