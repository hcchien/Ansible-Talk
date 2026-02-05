import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/stickers_provider.dart';
import '../../../shared/models/sticker.dart';

class MyStickersScreen extends ConsumerWidget {
  const MyStickersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stickersState = ref.watch(userStickersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stickers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.pushNamed('stickerStore'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(userStickersProvider.notifier).loadUserPacks(),
        child: stickersState.isLoading && stickersState.packs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : stickersState.packs.isEmpty
                ? _buildEmptyState(context)
                : _buildPacksList(context, ref, stickersState.packs),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_emotions_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No sticker packs yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Download sticker packs from the store',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.pushNamed('stickerStore'),
            icon: const Icon(Icons.store),
            label: const Text('Browse Store'),
          ),
        ],
      ),
    );
  }

  Widget _buildPacksList(
    BuildContext context,
    WidgetRef ref,
    List<StickerPack> packs,
  ) {
    return ReorderableListView.builder(
      itemCount: packs.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final packIds = packs.map((p) => p.id).toList();
        final movedId = packIds.removeAt(oldIndex);
        packIds.insert(newIndex, movedId);
        ref.read(userStickersProvider.notifier).reorderPacks(packIds);
      },
      itemBuilder: (context, index) {
        final pack = packs[index];
        return _buildPackTile(context, ref, pack, Key(pack.id));
      },
    );
  }

  Widget _buildPackTile(
    BuildContext context,
    WidgetRef ref,
    StickerPack pack,
    Key key,
  ) {
    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Sticker Pack'),
            content: Text('Remove "${pack.name}" from your collection?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(userStickersProvider.notifier).removePack(pack.id);
      },
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: pack.coverUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 56,
              height: 56,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            errorWidget: (_, __, ___) => Container(
              width: 56,
              height: 56,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        title: Text(pack.name),
        subtitle: Text(
          '${pack.author} • ${pack.stickers.length} stickers',
        ),
        trailing: const Icon(Icons.drag_handle),
        onTap: () => _showPackDetails(context, ref, pack),
      ),
    );
  }

  void _showPackDetails(BuildContext context, WidgetRef ref, StickerPack pack) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: pack.coverUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          pack.author,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      Navigator.pop(context);
                      ref.read(userStickersProvider.notifier).removePack(pack.id);
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            // Stickers grid
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: pack.stickers.length,
                itemBuilder: (context, index) {
                  final sticker = pack.stickers[index];
                  return CachedNetworkImage(
                    imageUrl: sticker.imageUrl,
                    placeholder: (_, __) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
