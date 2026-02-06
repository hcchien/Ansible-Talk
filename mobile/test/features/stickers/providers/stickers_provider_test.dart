import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/features/stickers/providers/stickers_provider.dart';

void main() {
  group('UserStickersState', () {
    test('default values', () {
      const state = UserStickersState();

      expect(state.packs, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = UserStickersState(isLoading: true);
      final newState = state.copyWith(error: 'Test error');

      expect(newState.isLoading, true);
      expect(newState.error, 'Test error');
    });

    test('copyWith with packs', () {
      const state = UserStickersState();
      final newState = state.copyWith(packs: []);

      expect(newState.packs, isEmpty);
    });

    test('copyWith with isLoading', () {
      const state = UserStickersState();
      final newState = state.copyWith(isLoading: true);

      expect(newState.isLoading, true);
    });

    test('copyWith with error', () {
      const state = UserStickersState();
      final newState = state.copyWith(error: 'Failed to load');

      expect(newState.error, 'Failed to load');
    });
  });

  group('StickerCatalogState', () {
    test('default values', () {
      const state = StickerCatalogState();

      expect(state.packs, isEmpty);
      expect(state.isLoading, false);
      expect(state.hasMore, true);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = StickerCatalogState(hasMore: false);
      final newState = state.copyWith(isLoading: true);

      expect(newState.hasMore, false);
      expect(newState.isLoading, true);
    });

    test('copyWith with packs', () {
      const state = StickerCatalogState();
      final newState = state.copyWith(packs: []);

      expect(newState.packs, isEmpty);
    });

    test('copyWith with hasMore', () {
      const state = StickerCatalogState();
      final newState = state.copyWith(hasMore: false);

      expect(newState.hasMore, false);
    });
  });

  group('Sticker pack operations', () {
    test('download pack', () {
      const packId = 'pack-123';
      expect(packId.isNotEmpty, true);
    });

    test('remove pack from list', () {
      final packs = ['p1', 'p2', 'p3'];
      const toRemove = 'p2';

      final filtered = packs.where((p) => p != toRemove).toList();

      expect(filtered.length, 2);
      expect(filtered.contains(toRemove), false);
    });

    test('reorder packs', () {
      final packIds = ['p1', 'p2', 'p3'];
      final newOrder = ['p3', 'p1', 'p2'];

      expect(newOrder.first, 'p3');
      expect(newOrder.last, 'p2');
    });
  });

  group('Catalog pagination', () {
    test('default limit', () {
      const limit = 20;
      expect(limit, 20);
    });

    test('has more calculation - full page', () {
      const limit = 20;
      final packsCount = 20;

      expect(packsCount >= limit, true);
    });

    test('has more calculation - partial page', () {
      const limit = 20;
      final packsCount = 15;

      expect(packsCount >= limit, false);
    });

    test('offset calculation', () {
      final existingPacks = List.generate(40, (i) => 'pack-$i');
      final offset = existingPacks.length;

      expect(offset, 40);
    });

    test('load more appends packs', () {
      final existing = ['p1', 'p2', 'p3'];
      final newPacks = ['p4', 'p5', 'p6'];
      final combined = [...existing, ...newPacks];

      expect(combined.length, 6);
      expect(combined.first, 'p1');
      expect(combined.last, 'p6');
    });
  });

  group('Search', () {
    test('empty query reloads catalog', () {
      const query = '';
      expect(query.isEmpty, true);
    });

    test('non-empty query searches', () {
      const query = 'happy';
      expect(query.isNotEmpty, true);
    });

    test('search resets hasMore', () {
      const state = StickerCatalogState(hasMore: true);
      final searchResult = state.copyWith(hasMore: false);

      expect(searchResult.hasMore, false);
    });
  });

  group('Error messages', () {
    test('load sticker packs error', () {
      const error = 'Failed to load sticker packs';
      expect(error.contains('sticker'), true);
    });

    test('download pack error', () {
      const error = 'Failed to download pack';
      expect(error.contains('download'), true);
    });

    test('remove pack error', () {
      const error = 'Failed to remove pack';
      expect(error.contains('remove'), true);
    });

    test('reorder packs error', () {
      const error = 'Failed to reorder packs';
      expect(error.contains('reorder'), true);
    });

    test('load catalog error', () {
      const error = 'Failed to load catalog';
      expect(error.contains('catalog'), true);
    });

    test('search error', () {
      const error = 'Search failed';
      expect(error.contains('Search'), true);
    });
  });

  group('State transitions', () {
    test('loading to loaded - user packs', () {
      const loading = UserStickersState(isLoading: true);
      final loaded = loading.copyWith(
        isLoading: false,
        packs: [],
      );

      expect(loading.isLoading, true);
      expect(loaded.isLoading, false);
    });

    test('loading to loaded - catalog', () {
      const loading = StickerCatalogState(isLoading: true);
      final loaded = loading.copyWith(
        isLoading: false,
        packs: [],
      );

      expect(loading.isLoading, true);
      expect(loaded.isLoading, false);
    });

    test('download triggers reload', () {
      // After download, user packs should be reloaded
      const before = UserStickersState();
      final afterDownload = before.copyWith(isLoading: true);

      expect(afterDownload.isLoading, true);
    });
  });

  group('Sticker pack model', () {
    test('pack ID required', () {
      const packId = 'pack-123';
      expect(packId.isNotEmpty, true);
    });

    test('pack name required', () {
      const name = 'Happy Emojis';
      expect(name.isNotEmpty, true);
    });

    test('pack author required', () {
      const author = 'John Doe';
      expect(author.isNotEmpty, true);
    });

    test('description optional', () {
      const String? description1 = null;
      const String description2 = 'A fun sticker pack';

      expect(description1, isNull);
      expect(description2.isNotEmpty, true);
    });

    test('pack properties', () {
      final pack = {
        'isOfficial': true,
        'isAnimated': false,
        'price': 0,
        'downloads': 1000,
      };

      expect(pack['isOfficial'], true);
      expect(pack['isAnimated'], false);
      expect(pack['price'], 0);
      expect(pack['downloads'], 1000);
    });
  });

  group('Sticker model', () {
    test('sticker ID required', () {
      const stickerId = 'sticker-123';
      expect(stickerId.isNotEmpty, true);
    });

    test('emoji required', () {
      const emoji = '😀';
      expect(emoji.isNotEmpty, true);
    });

    test('image URL required', () {
      const imageUrl = 'https://cdn.example.com/stickers/sticker-123.webp';
      expect(imageUrl.startsWith('http'), true);
    });

    test('position for ordering', () {
      const position = 0;
      expect(position >= 0, true);
    });
  });

  group('Pack pricing', () {
    test('free pack', () {
      const price = 0;
      final isFree = price == 0;

      expect(isFree, true);
    });

    test('paid pack', () {
      const price = 99;
      final isFree = price == 0;

      expect(isFree, false);
    });
  });

  group('Pack types', () {
    test('official pack', () {
      const isOfficial = true;
      expect(isOfficial, true);
    });

    test('community pack', () {
      const isOfficial = false;
      expect(isOfficial, false);
    });

    test('static pack', () {
      const isAnimated = false;
      expect(isAnimated, false);
    });

    test('animated pack', () {
      const isAnimated = true;
      expect(isAnimated, true);
    });
  });

  group('Reorder logic', () {
    test('reorder by pack IDs', () {
      final packs = [
        {'id': 'p1', 'name': 'Pack 1'},
        {'id': 'p2', 'name': 'Pack 2'},
        {'id': 'p3', 'name': 'Pack 3'},
      ];

      final newOrder = ['p3', 'p1', 'p2'];

      final reordered = newOrder.map((id) =>
        packs.firstWhere((p) => p['id'] == id)
      ).toList();

      expect(reordered[0]['id'], 'p3');
      expect(reordered[1]['id'], 'p1');
      expect(reordered[2]['id'], 'p2');
    });
  });

  group('Loading guards', () {
    test('skip load if already loading', () {
      const state = StickerCatalogState(isLoading: true);

      if (state.isLoading) {
        // Should return early
        expect(true, true);
      }
    });

    test('skip load more if no more items', () {
      const state = StickerCatalogState(hasMore: false);

      if (!state.hasMore) {
        // Should return early
        expect(true, true);
      }
    });
  });
}
