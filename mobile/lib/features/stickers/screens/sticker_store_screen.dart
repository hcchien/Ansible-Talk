import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/stickers_provider.dart';
import '../../../shared/models/sticker.dart';

class StickerStoreScreen extends ConsumerStatefulWidget {
  const StickerStoreScreen({super.key});

  @override
  ConsumerState<StickerStoreScreen> createState() => _StickerStoreScreenState();
}

class _StickerStoreScreenState extends ConsumerState<StickerStoreScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(stickerCatalogProvider.notifier).loadCatalog(loadMore: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(stickerCatalogProvider);
    final userPacks = ref.watch(userStickersProvider).packs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Store'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sticker packs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(stickerCatalogProvider.notifier).loadCatalog();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                ref.read(stickerCatalogProvider.notifier).searchPacks(value);
              },
            ),
          ),

          // Packs list
          Expanded(
            child: catalogState.isLoading && catalogState.packs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : catalogState.packs.isEmpty
                    ? _buildEmptyState(context)
                    : _buildPacksGrid(context, ref, catalogState.packs, userPacks),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No sticker packs found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildPacksGrid(
    BuildContext context,
    WidgetRef ref,
    List<StickerPack> packs,
    List<StickerPack> userPacks,
  ) {
    final userPackIds = userPacks.map((p) => p.id).toSet();

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: packs.length,
      itemBuilder: (context, index) {
        final pack = packs[index];
        final isOwned = userPackIds.contains(pack.id);
        return _buildPackCard(context, ref, pack, isOwned);
      },
    );
  }

  Widget _buildPackCard(
    BuildContext context,
    WidgetRef ref,
    StickerPack pack,
    bool isOwned,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPackPreview(context, ref, pack, isOwned),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: pack.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                  if (pack.isOfficial)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Official',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (isOwned)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    pack.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPackPreview(
    BuildContext context,
    WidgetRef ref,
    StickerPack pack,
    bool isOwned,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
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
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                pack.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (pack.isOfficial)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Official',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pack.author,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (pack.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            pack.description!,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Action button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: isOwned
                    ? OutlinedButton.icon(
                        onPressed: () {
                          ref.read(userStickersProvider.notifier).removePack(pack.id);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.remove),
                        label: const Text('Remove'),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          ref.read(userStickersProvider.notifier).downloadPack(pack.id);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${pack.name} added to your collection'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: Text(pack.price > 0 ? 'Buy' : 'Add'),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            // Preview stickers
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
