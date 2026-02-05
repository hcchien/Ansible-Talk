import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/contacts_provider.dart';
import '../../../shared/models/user.dart';
import '../../../core/network/api_client.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsState = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => context.pushNamed('addContact'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(contactsProvider.notifier).loadContacts(),
        child: contactsState.isLoading && contactsState.contacts.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : contactsState.contacts.isEmpty
                ? _buildEmptyState(context)
                : _buildContactsList(context, ref, contactsState),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.contacts_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add contacts to start chatting',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.pushNamed('addContact'),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsList(
    BuildContext context,
    WidgetRef ref,
    ContactsState contactsState,
  ) {
    final favorites = contactsState.favorites;
    final regular = contactsState.regular;

    return ListView(
      children: [
        if (favorites.isNotEmpty) ...[
          _buildSectionHeader(context, 'Favorites'),
          ...favorites.map((contact) => _buildContactTile(context, ref, contact)),
        ],
        if (regular.isNotEmpty) ...[
          _buildSectionHeader(context, 'Contacts'),
          ...regular.map((contact) => _buildContactTile(context, ref, contact)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildContactTile(BuildContext context, WidgetRef ref, Contact contact) {
    final user = contact.contact;
    if (user == null) return const SizedBox.shrink();

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null
            ? Text(user.displayName[0].toUpperCase())
            : null,
      ),
      title: Text(contact.nickname ?? user.displayName),
      subtitle: Text('@${user.username}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              contact.isFavorite ? Icons.star : Icons.star_outline,
              color: contact.isFavorite
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () {
              ref.read(contactsProvider.notifier).toggleFavorite(contact.contactId);
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () async {
              // Create or get existing conversation
              final apiClient = ref.read(apiClientProvider);
              final response = await apiClient.createDirectConversation(user.id);
              final conversationId = response.data['id'];
              if (context.mounted) {
                context.pushNamed('chat', pathParameters: {
                  'conversationId': conversationId,
                });
              }
            },
          ),
        ],
      ),
      onTap: () {
        _showContactDetails(context, ref, contact);
      },
    );
  }

  void _showContactDetails(BuildContext context, WidgetRef ref, Contact contact) {
    final user = contact.contact!;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.displayName[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineLarge,
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              contact.nickname ?? user.displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '@${user.username}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (user.bio != null) ...[
              const SizedBox(height: 8),
              Text(
                user.bio!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.chat,
                  label: 'Message',
                  onPressed: () async {
                    Navigator.pop(context);
                    final apiClient = ref.read(apiClientProvider);
                    final response = await apiClient.createDirectConversation(user.id);
                    final conversationId = response.data['id'];
                    if (context.mounted) {
                      context.pushNamed('chat', pathParameters: {
                        'conversationId': conversationId,
                      });
                    }
                  },
                ),
                _buildActionButton(
                  context,
                  icon: contact.isFavorite ? Icons.star : Icons.star_outline,
                  label: contact.isFavorite ? 'Unfavorite' : 'Favorite',
                  onPressed: () {
                    ref.read(contactsProvider.notifier).toggleFavorite(contact.contactId);
                    Navigator.pop(context);
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.block,
                  label: 'Block',
                  onPressed: () {
                    ref.read(contactsProvider.notifier).blockContact(contact.contactId);
                    Navigator.pop(context);
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.delete_outline,
                  label: 'Remove',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () {
                    ref.read(contactsProvider.notifier).deleteContact(contact.contactId);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
