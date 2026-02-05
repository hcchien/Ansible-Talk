import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../providers/chat_provider.dart';
import '../../../shared/models/message.dart';
import '../../auth/providers/auth_provider.dart';
import '../../stickers/widgets/sticker_picker.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showStickerPicker = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Send typing stopped
    ref.read(messagesProvider(widget.conversationId).notifier).sendTyping(false);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(messagesProvider(widget.conversationId).notifier)
          .loadMessages(loadMore: true);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendMessage(text);
    _messageController.clear();

    // Send typing stopped
    ref.read(messagesProvider(widget.conversationId).notifier).sendTyping(false);
  }

  void _onTextChanged(String text) {
    // Send typing indicator
    final isTyping = text.isNotEmpty;
    ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendTyping(isTyping);
  }

  void _sendSticker(String stickerId) {
    ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendSticker(stickerId);
    setState(() => _showStickerPicker = false);
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(messagesProvider(widget.conversationId));
    final conversations = ref.watch(conversationsProvider).conversations;
    final currentUser = ref.watch(currentUserProvider);

    final conversation = conversations.firstWhere(
      (c) => c.id == widget.conversationId,
      orElse: () => throw Exception('Conversation not found'),
    );

    // Get display info
    String title;
    String? subtitle;
    String? avatarUrl;

    if (conversation.type == ConversationType.direct) {
      final otherParticipant = conversation.participants.firstWhere(
        (p) => p.userId != currentUser?.id,
        orElse: () => conversation.participants.first,
      );
      title = otherParticipant.user?.displayName ?? 'Unknown';
      subtitle = otherParticipant.user?.status == 'online'
          ? 'Online'
          : otherParticipant.user?.lastSeenAt != null
              ? 'Last seen ${timeago.format(otherParticipant.user!.lastSeenAt!)}'
              : null;
      avatarUrl = otherParticipant.user?.avatarUrl;
    } else {
      title = conversation.name ?? 'Group';
      subtitle = '${conversation.participants.length} members';
      avatarUrl = conversation.avatarUrl;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: avatarUrl != null
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl == null ? Text(title[0].toUpperCase()) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: Show conversation options
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesState.isLoading && messagesState.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messagesState.messages.isEmpty
                    ? _buildEmptyChat(context)
                    : _buildMessagesList(
                        context,
                        messagesState.messages,
                        currentUser?.id,
                      ),
          ),

          // Sticker picker
          if (_showStickerPicker)
            StickerPicker(
              onStickerSelected: _sendSticker,
              onClose: () => setState(() => _showStickerPicker = false),
            ),

          // Input area
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildEmptyChat(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to start the conversation',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    List<Message> messages,
    String? currentUserId,
  ) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMe = message.senderId == currentUserId;

        // Check if we should show date separator
        bool showDate = false;
        if (index == messages.length - 1) {
          showDate = true;
        } else {
          final prevMessage = messages[index + 1];
          showDate = !_isSameDay(message.createdAt, prevMessage.createdAt);
        }

        return Column(
          children: [
            if (showDate) _buildDateSeparator(context, message.createdAt),
            _buildMessageBubble(context, message, isMe),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(BuildContext context, DateTime date) {
    String text;
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      text = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = 'Yesterday';
    } else {
      text = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message message, bool isMe) {
    final bubbleColor = isMe
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isMe
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    Widget content;
    if (message.type == MessageType.sticker && message.stickerId != null) {
      content = CachedNetworkImage(
        imageUrl: 'http://localhost:9000/stickers/${message.stickerId}',
        width: 120,
        height: 120,
        placeholder: (_, __) => const SizedBox(
          width: 120,
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      );
    } else {
      String text;
      try {
        text = utf8.decode(message.content);
      } catch (e) {
        text = 'Unable to decrypt message';
      }

      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(color: textColor),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withOpacity(0.7),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.read
                        ? Icons.done_all
                        : message.status == MessageStatus.delivered
                            ? Icons.done_all
                            : message.status == MessageStatus.sent
                                ? Icons.done
                                : message.status == MessageStatus.failed
                                    ? Icons.error_outline
                                    : Icons.schedule,
                    size: 14,
                    color: message.status == MessageStatus.read
                        ? Colors.blue
                        : textColor.withOpacity(0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _showStickerPicker
                  ? Icons.keyboard
                  : Icons.emoji_emotions_outlined,
            ),
            onPressed: () {
              setState(() => _showStickerPicker = !_showStickerPicker);
            },
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Message',
                border: InputBorder.none,
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
