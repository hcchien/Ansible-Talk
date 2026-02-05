import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/stickers_provider.dart';
import '../../../shared/models/sticker.dart';

class StickerPicker extends ConsumerStatefulWidget {
  final Function(String stickerId) onStickerSelected;
  final VoidCallback onClose;

  const StickerPicker({
    super.key,
    required this.onStickerSelected,
    required this.onClose,
  });

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  int _selectedPackIndex = 0;

  @override
  Widget build(BuildContext context) {
    final stickersState = ref.watch(userStickersProvider);
    final packs = stickersState.packs;

    if (packs.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              const Text('No sticker packs'),
              TextButton(
                onPressed: widget.onClose,
                child: const Text('Get Stickers'),
              ),
            ],
          ),
        ),
      );
    }

    final selectedPack = packs[_selectedPackIndex];

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          // Pack tabs
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: packs.length,
                    itemBuilder: (context, index) {
                      final pack = packs[index];
                      final isSelected = index == _selectedPackIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedPackIndex = index);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(
                                      color: Theme.of(context).colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: pack.coverUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.broken_image, size: 20),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Stickers grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: selectedPack.stickers.length,
              itemBuilder: (context, index) {
                final sticker = selectedPack.stickers[index];
                return _buildStickerItem(sticker);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerItem(Sticker sticker) {
    return InkWell(
      onTap: () => widget.onStickerSelected(sticker.id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CachedNetworkImage(
          imageUrl: sticker.imageUrl,
          placeholder: (_, __) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.broken_image, size: 24),
          ),
        ),
      ),
    );
  }
}
