import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../providers/chat_provider.dart';
import '../../../shared/models/message.dart';
import '../../auth/providers/auth_provider.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsState = ref.watch(conversationsProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('New Group'),
                onTap: () {
                  // TODO: Implement group creation
                },
              ),
              PopupMenuItem(
                child: const Text('Settings'),
                onTap: () {
                  // TODO: Navigate to settings
                },
              ),
              PopupMenuItem(
                child: const Text('Logout'),
                onTap: () {
                  ref.read(authStateProvider.notifier).logout();
                },
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(conversationsProvider.notifier).loadConversations(),
        child: conversationsState.isLoading && conversationsState.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : conversationsState.conversations.isEmpty
                ? _buildEmptyState(context)
                : _buildConversationsList(
                    context,
                    conversationsState.conversations,
                    currentUser?.id,
                  ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
            'No conversations yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Start chatting with your contacts',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationsList(
    BuildContext context,
    List<Conversation> conversations,
    String? currentUserId,
  ) {
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return _buildConversationTile(context, conversation, currentUserId);
      },
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    Conversation conversation,
    String? currentUserId,
  ) {
    // Get display info
    String title;
    String? avatarUrl;

    if (conversation.type == ConversationType.direct) {
      // Find the other participant
      final otherParticipant = conversation.participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => conversation.participants.first,
      );
      title = otherParticipant.user?.displayName ?? 'Unknown';
      avatarUrl = otherParticipant.user?.avatarUrl;
    } else {
      title = conversation.name ?? 'Group';
      avatarUrl = conversation.avatarUrl;
    }

    // Format last message
    String? lastMessageText;
    if (conversation.lastMessage != null) {
      final msg = conversation.lastMessage!;
      if (msg.type == MessageType.text) {
        try {
          lastMessageText = utf8.decode(msg.content);
        } catch (e) {
          lastMessageText = 'Message';
        }
      } else if (msg.type == MessageType.sticker) {
        lastMessageText = 'Sticker';
      } else if (msg.type == MessageType.image) {
        lastMessageText = 'Photo';
      } else {
        lastMessageText = 'Message';
      }

      // Prefix with sender name if not from current user
      if (msg.senderId != currentUserId && msg.sender != null) {
        lastMessageText = '${msg.sender!.displayName}: $lastMessageText';
      }
    }

    // Format time
    String? timeText;
    if (conversation.lastMessageAt != null) {
      timeText = timeago.format(conversation.lastMessageAt!, locale: 'en_short');
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundImage: avatarUrl != null
            ? CachedNetworkImageProvider(avatarUrl)
            : null,
        child: avatarUrl == null
            ? Text(
                title[0].toUpperCase(),
                style: const TextStyle(fontSize: 20),
              )
            : null,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: lastMessageText != null
          ? Text(
              lastMessageText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: timeText != null
          ? Text(
              timeText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: () {
        context.pushNamed('chat', pathParameters: {
          'conversationId': conversation.id,
        });
      },
    );
  }
}
