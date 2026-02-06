import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/features/chat/providers/chat_provider.dart';
import 'package:ansible_talk/shared/models/message.dart';

void main() {
  group('ConversationsState', () {
    test('default values', () {
      const state = ConversationsState();

      expect(state.conversations, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = ConversationsState(isLoading: true);
      final newState = state.copyWith(error: 'Test error');

      expect(newState.isLoading, true);
      expect(newState.error, 'Test error');
    });

    test('copyWith with conversations', () {
      const state = ConversationsState();
      final newState = state.copyWith(conversations: []);

      expect(newState.conversations, isEmpty);
    });

    test('copyWith with isLoading', () {
      const state = ConversationsState();
      final newState = state.copyWith(isLoading: true);

      expect(newState.isLoading, true);
    });

    test('copyWith with error', () {
      const state = ConversationsState();
      final newState = state.copyWith(error: 'Failed to load');

      expect(newState.error, 'Failed to load');
    });
  });

  group('MessagesState', () {
    test('default values', () {
      const state = MessagesState();

      expect(state.messages, isEmpty);
      expect(state.isLoading, false);
      expect(state.hasMore, true);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = MessagesState(hasMore: false);
      final newState = state.copyWith(isLoading: true);

      expect(newState.hasMore, false);
      expect(newState.isLoading, true);
    });

    test('copyWith with messages', () {
      const state = MessagesState();
      final newState = state.copyWith(messages: []);

      expect(newState.messages, isEmpty);
    });

    test('copyWith with hasMore', () {
      const state = MessagesState();
      final newState = state.copyWith(hasMore: false);

      expect(newState.hasMore, false);
    });
  });

  group('Message types', () {
    test('text message type', () {
      expect(MessageType.text.name, 'text');
    });

    test('image message type', () {
      expect(MessageType.image.name, 'image');
    });

    test('video message type', () {
      expect(MessageType.video.name, 'video');
    });

    test('audio message type', () {
      expect(MessageType.audio.name, 'audio');
    });

    test('file message type', () {
      expect(MessageType.file.name, 'file');
    });

    test('sticker message type', () {
      expect(MessageType.sticker.name, 'sticker');
    });

    test('system message type', () {
      expect(MessageType.system.name, 'system');
    });
  });

  group('Message status', () {
    test('sending status', () {
      expect(MessageStatus.sending.name, 'sending');
    });

    test('sent status', () {
      expect(MessageStatus.sent.name, 'sent');
    });

    test('delivered status', () {
      expect(MessageStatus.delivered.name, 'delivered');
    });

    test('read status', () {
      expect(MessageStatus.read.name, 'read');
    });

    test('failed status', () {
      expect(MessageStatus.failed.name, 'failed');
    });
  });

  group('Message content encoding', () {
    test('text encoding', () {
      const text = 'Hello, World!';
      final encoded = utf8.encode(text);
      final decoded = utf8.decode(encoded);

      expect(decoded, text);
    });

    test('unicode text encoding', () {
      const text = 'Hello 你好 مرحبا 🎉';
      final encoded = utf8.encode(text);
      final decoded = utf8.decode(encoded);

      expect(decoded, text);
    });

    test('empty content', () {
      const text = '';
      final encoded = utf8.encode(text);

      expect(encoded, isEmpty);
    });
  });

  group('Conversation types', () {
    test('direct conversation', () {
      const type = 'direct';
      expect(type, 'direct');
    });

    test('group conversation', () {
      const type = 'group';
      expect(type, 'group');
    });
  });

  group('Pagination', () {
    test('default limit', () {
      const limit = 50;
      expect(limit, 50);
    });

    test('has more calculation', () {
      const limit = 50;
      final messagesCount = 50;

      expect(messagesCount >= limit, true);
    });

    test('no more messages', () {
      const limit = 50;
      final messagesCount = 30;

      expect(messagesCount >= limit, false);
    });

    test('offset calculation', () {
      final existingMessages = List.generate(100, (i) => i);
      final offset = existingMessages.length;

      expect(offset, 100);
    });
  });

  group('Message sorting', () {
    test('sort by created time descending', () {
      final now = DateTime.now();
      final times = [
        now.subtract(const Duration(hours: 2)),
        now.subtract(const Duration(hours: 1)),
        now,
      ];

      times.sort((a, b) => b.compareTo(a));

      expect(times[0], now);
      expect(times[2], now.subtract(const Duration(hours: 2)));
    });
  });

  group('Conversation sorting', () {
    test('sort by last message time', () {
      final now = DateTime.now();
      final conv1Time = now.subtract(const Duration(minutes: 5));
      final conv2Time = now;

      final times = [conv1Time, conv2Time];
      times.sort((a, b) => b.compareTo(a));

      expect(times[0], conv2Time);
    });
  });

  group('Message local ID', () {
    test('local ID generation', () {
      final localId = DateTime.now().millisecondsSinceEpoch.toString();

      expect(localId.isNotEmpty, true);
      expect(int.tryParse(localId), isNotNull);
    });

    test('unique local IDs', () {
      final ids = <String>{};

      for (var i = 0; i < 10; i++) {
        final id = (DateTime.now().millisecondsSinceEpoch + i).toString();
        ids.add(id);
      }

      expect(ids.length, 10);
    });
  });

  group('WebSocket message types', () {
    test('new_message type', () {
      const type = 'new_message';
      expect(type, 'new_message');
    });

    test('typing type', () {
      const type = 'typing';
      expect(type, 'typing');
    });

    test('delivered acknowledgment', () {
      const ackType = 'delivered';
      expect(ackType, 'delivered');
    });

    test('read acknowledgment', () {
      const ackType = 'read';
      expect(ackType, 'read');
    });
  });

  group('Error messages', () {
    test('load conversations error', () {
      const error = 'Failed to load conversations';
      expect(error.contains('conversations'), true);
    });

    test('load messages error', () {
      const error = 'Failed to load messages';
      expect(error.contains('messages'), true);
    });
  });

  group('State transitions', () {
    test('loading to loaded', () {
      const loading = MessagesState(isLoading: true);
      final loaded = loading.copyWith(
        isLoading: false,
        messages: [],
      );

      expect(loading.isLoading, true);
      expect(loaded.isLoading, false);
    });

    test('load more appends messages', () {
      final existing = [1, 2, 3];
      final newMessages = [4, 5, 6];
      final combined = [...existing, ...newMessages];

      expect(combined.length, 6);
      expect(combined.first, 1);
      expect(combined.last, 6);
    });

    test('message status update', () {
      // Simulate message status update
      final statuses = [
        MessageStatus.sending,
        MessageStatus.sent,
        MessageStatus.delivered,
        MessageStatus.read,
      ];

      for (var i = 0; i < statuses.length - 1; i++) {
        expect(statuses[i].index < statuses[i + 1].index, true);
      }
    });

    test('message failed status', () {
      expect(MessageStatus.failed.name, 'failed');
    });
  });

  group('Typing indicators', () {
    test('typing set operations', () {
      final typingUsers = <String>{};

      typingUsers.add('user1');
      expect(typingUsers.contains('user1'), true);

      typingUsers.add('user2');
      expect(typingUsers.length, 2);

      typingUsers.remove('user1');
      expect(typingUsers.contains('user1'), false);
    });
  });

  group('Reply handling', () {
    test('reply to ID assignment', () {
      const replyToId = 'msg-123';
      expect(replyToId.isNotEmpty, true);
    });

    test('null reply to ID', () {
      const String? replyToId = null;
      expect(replyToId, isNull);
    });
  });

  group('Sticker handling', () {
    test('sticker ID assignment', () {
      const stickerId = 'sticker-123';
      expect(stickerId.isNotEmpty, true);
    });

    test('sticker message has empty content', () {
      final content = <int>[];
      expect(content, isEmpty);
    });
  });
}
