import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/websocket_client.dart';
import '../../../core/crypto/signal_client.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';
import '../../auth/providers/auth_provider.dart';

// Conversations state
class ConversationsState {
  final List<Conversation> conversations;
  final bool isLoading;
  final String? error;

  const ConversationsState({
    this.conversations = const [],
    this.isLoading = false,
    this.error,
  });

  ConversationsState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    String? error,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ConversationsNotifier extends StateNotifier<ConversationsState> {
  final ApiClient _apiClient;
  final WebSocketClient _wsClient;

  ConversationsNotifier(this._apiClient, this._wsClient)
      : super(const ConversationsState()) {
    loadConversations();
    _listenToMessages();
  }

  void _listenToMessages() {
    _wsClient.messages.listen((message) {
      if (message.type == 'new_message') {
        final payload = message.payload as Map<String, dynamic>;
        final newMessage = Message.fromJson(payload['message']);
        _updateConversationWithMessage(newMessage);
      }
    });
  }

  void _updateConversationWithMessage(Message message) {
    final updated = state.conversations.map((conv) {
      if (conv.id == message.conversationId) {
        return Conversation(
          id: conv.id,
          type: conv.type,
          name: conv.name,
          avatarUrl: conv.avatarUrl,
          createdBy: conv.createdBy,
          lastMessageAt: message.createdAt,
          createdAt: conv.createdAt,
          updatedAt: DateTime.now(),
          participants: conv.participants,
          lastMessage: message,
        );
      }
      return conv;
    }).toList();

    // Sort by last message time
    updated.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    state = state.copyWith(conversations: updated);
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.getConversations();
      final conversations = (response.data as List)
          .map((json) => Conversation.fromJson(json))
          .toList();

      state = state.copyWith(conversations: conversations, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load conversations',
      );
    }
  }

  Future<Conversation?> createDirectConversation(String userId) async {
    try {
      final response = await _apiClient.createDirectConversation(userId);
      final conversation = Conversation.fromJson(response.data);

      // Check if already exists
      final exists = state.conversations.any((c) => c.id == conversation.id);
      if (!exists) {
        state = state.copyWith(
          conversations: [conversation, ...state.conversations],
        );
      }

      return conversation;
    } catch (e) {
      return null;
    }
  }

  Future<Conversation?> createGroupConversation(
    String name,
    List<String> memberIds,
  ) async {
    try {
      final response = await _apiClient.createGroupConversation(name, memberIds);
      final conversation = Conversation.fromJson(response.data);

      state = state.copyWith(
        conversations: [conversation, ...state.conversations],
      );

      return conversation;
    } catch (e) {
      return null;
    }
  }
}

// Messages state for a specific conversation
class MessagesState {
  final List<Message> messages;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  MessagesState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  final ApiClient _apiClient;
  final WebSocketClient _wsClient;
  final SignalClient _signalClient;
  final String conversationId;
  final User? currentUser;

  MessagesNotifier(
    this._apiClient,
    this._wsClient,
    this._signalClient,
    this.conversationId,
    this.currentUser,
  ) : super(const MessagesState()) {
    loadMessages();
    _listenToMessages();
  }

  void _listenToMessages() {
    _wsClient.messages.listen((message) async {
      if (message.type == 'new_message') {
        final payload = message.payload as Map<String, dynamic>;
        final newMessage = Message.fromJson(payload['message']);

        if (newMessage.conversationId == conversationId) {
          // Decrypt message
          final decrypted = await _decryptMessage(newMessage);

          // Send delivery receipt
          _wsClient.sendAck(newMessage.id, 'delivered');

          state = state.copyWith(
            messages: [decrypted, ...state.messages],
          );
        }
      } else if (message.type == 'typing') {
        // Handle typing indicator
        final payload = message.payload as Map<String, dynamic>;
        if (payload['conversation_id'] == conversationId) {
          // Emit typing state through a separate provider if needed
        }
      }
    });
  }

  Future<void> loadMessages({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final offset = loadMore ? state.messages.length : 0;
      final response = await _apiClient.getMessages(
        conversationId,
        limit: 50,
        offset: offset,
      );

      var messages = (response.data as List)
          .map((json) => Message.fromJson(json))
          .toList();

      // Decrypt messages
      messages = await Future.wait(
        messages.map((m) => _decryptMessage(m)),
      );

      state = state.copyWith(
        messages: loadMore ? [...state.messages, ...messages] : messages,
        isLoading: false,
        hasMore: messages.length >= 50,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load messages',
      );
    }
  }

  Future<void> sendMessage(String text, {String? replyToId}) async {
    if (currentUser == null) return;

    // Create local message
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final localMessage = Message(
      id: localId,
      conversationId: conversationId,
      senderId: currentUser!.id,
      type: MessageType.text,
      content: utf8.encode(text),
      replyToId: replyToId,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sender: currentUser,
    );

    // Add to local state
    state = state.copyWith(messages: [localMessage, ...state.messages]);

    try {
      // Encrypt message (for now, just encode as we'd need the recipient's keys)
      final encryptedContent = utf8.encode(text);

      // Send to server
      final response = await _apiClient.sendMessage(
        conversationId,
        type: 'text',
        content: encryptedContent,
        replyToId: replyToId,
      );

      final sentMessage = Message.fromJson(response.data);

      // Update local message with server response
      state = state.copyWith(
        messages: state.messages.map((m) {
          if (m.id == localId) {
            return Message(
              id: sentMessage.id,
              conversationId: sentMessage.conversationId,
              senderId: sentMessage.senderId,
              type: sentMessage.type,
              content: sentMessage.content,
              replyToId: sentMessage.replyToId,
              status: MessageStatus.sent,
              createdAt: sentMessage.createdAt,
              updatedAt: sentMessage.updatedAt,
              sender: currentUser,
            );
          }
          return m;
        }).toList(),
      );
    } catch (e) {
      // Mark as failed
      state = state.copyWith(
        messages: state.messages.map((m) {
          if (m.id == localId) {
            return Message(
              id: m.id,
              conversationId: m.conversationId,
              senderId: m.senderId,
              type: m.type,
              content: m.content,
              replyToId: m.replyToId,
              status: MessageStatus.failed,
              createdAt: m.createdAt,
              updatedAt: m.updatedAt,
              sender: m.sender,
            );
          }
          return m;
        }).toList(),
      );
    }
  }

  Future<void> sendSticker(String stickerId) async {
    if (currentUser == null) return;

    try {
      final response = await _apiClient.sendMessage(
        conversationId,
        type: 'sticker',
        content: [],
        stickerId: stickerId,
      );

      final sentMessage = Message.fromJson(response.data);
      state = state.copyWith(
        messages: [
          Message(
            id: sentMessage.id,
            conversationId: sentMessage.conversationId,
            senderId: sentMessage.senderId,
            type: sentMessage.type,
            content: sentMessage.content,
            stickerId: sentMessage.stickerId,
            status: MessageStatus.sent,
            createdAt: sentMessage.createdAt,
            updatedAt: sentMessage.updatedAt,
            sender: currentUser,
          ),
          ...state.messages,
        ],
      );
    } catch (e) {
      // Handle error
    }
  }

  void sendTyping(bool isTyping) {
    _wsClient.sendTyping(conversationId, isTyping);
  }

  Future<void> markAsRead(String messageId) async {
    _wsClient.sendAck(messageId, 'read');
  }

  Future<Message> _decryptMessage(Message message) async {
    // For now, just decode the content
    // In production, use Signal protocol decryption
    try {
      final decryptedText = utf8.decode(message.content);
      return Message(
        id: message.id,
        conversationId: message.conversationId,
        senderId: message.senderId,
        type: message.type,
        content: utf8.encode(decryptedText),
        stickerId: message.stickerId,
        replyToId: message.replyToId,
        status: message.status,
        createdAt: message.createdAt,
        updatedAt: message.updatedAt,
        deletedAt: message.deletedAt,
        sender: message.sender,
        replyTo: message.replyTo,
        receipts: message.receipts,
      );
    } catch (e) {
      return message;
    }
  }
}

// Providers
final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final wsClient = ref.watch(webSocketClientProvider);
  return ConversationsNotifier(apiClient, wsClient);
});

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    MessagesState, String>((ref, conversationId) {
  final apiClient = ref.watch(apiClientProvider);
  final wsClient = ref.watch(webSocketClientProvider);
  final signalClient = ref.watch(signalClientProvider);
  final currentUser = ref.watch(currentUserProvider);
  return MessagesNotifier(
    apiClient,
    wsClient,
    signalClient,
    conversationId,
    currentUser,
  );
});

// Typing indicator provider
final typingUsersProvider = StateProvider.family<Set<String>, String>(
  (ref, conversationId) => {},
);
