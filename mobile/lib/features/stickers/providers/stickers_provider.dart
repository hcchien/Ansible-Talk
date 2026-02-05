import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/sticker.dart';

// User's downloaded sticker packs
class UserStickersState {
  final List<StickerPack> packs;
  final bool isLoading;
  final String? error;

  const UserStickersState({
    this.packs = const [],
    this.isLoading = false,
    this.error,
  });

  UserStickersState copyWith({
    List<StickerPack>? packs,
    bool? isLoading,
    String? error,
  }) {
    return UserStickersState(
      packs: packs ?? this.packs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class UserStickersNotifier extends StateNotifier<UserStickersState> {
  final ApiClient _apiClient;

  UserStickersNotifier(this._apiClient) : super(const UserStickersState()) {
    loadUserPacks();
  }

  Future<void> loadUserPacks() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.getUserStickerPacks();
      final packs = (response.data as List)
          .map((json) => StickerPack.fromJson(json))
          .toList();

      state = state.copyWith(packs: packs, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load sticker packs',
      );
    }
  }

  Future<void> downloadPack(String packId) async {
    try {
      await _apiClient.downloadStickerPack(packId);

      // Reload packs
      await loadUserPacks();
    } catch (e) {
      state = state.copyWith(error: 'Failed to download pack');
    }
  }

  Future<void> removePack(String packId) async {
    try {
      await _apiClient.removeStickerPack(packId);

      state = state.copyWith(
        packs: state.packs.where((p) => p.id != packId).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to remove pack');
    }
  }

  Future<void> reorderPacks(List<String> packIds) async {
    try {
      await _apiClient.reorderStickerPacks(packIds);

      // Reorder locally
      final reordered = packIds
          .map((id) => state.packs.firstWhere((p) => p.id == id))
          .toList();
      state = state.copyWith(packs: reordered);
    } catch (e) {
      state = state.copyWith(error: 'Failed to reorder packs');
    }
  }
}

// Sticker store catalog
class StickerCatalogState {
  final List<StickerPack> packs;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const StickerCatalogState({
    this.packs = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  StickerCatalogState copyWith({
    List<StickerPack>? packs,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return StickerCatalogState(
      packs: packs ?? this.packs,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class StickerCatalogNotifier extends StateNotifier<StickerCatalogState> {
  final ApiClient _apiClient;

  StickerCatalogNotifier(this._apiClient) : super(const StickerCatalogState()) {
    loadCatalog();
  }

  Future<void> loadCatalog({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final offset = loadMore ? state.packs.length : 0;
      final response = await _apiClient.getStickerCatalog(
        limit: 20,
        offset: offset,
      );

      final packs = (response.data as List)
          .map((json) => StickerPack.fromJson(json))
          .toList();

      state = state.copyWith(
        packs: loadMore ? [...state.packs, ...packs] : packs,
        isLoading: false,
        hasMore: packs.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load catalog',
      );
    }
  }

  Future<void> searchPacks(String query) async {
    if (query.isEmpty) {
      loadCatalog();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.searchStickers(query);
      final packs = (response.data as List)
          .map((json) => StickerPack.fromJson(json))
          .toList();

      state = state.copyWith(
        packs: packs,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Search failed',
      );
    }
  }
}

// Providers
final userStickersProvider =
    StateNotifierProvider<UserStickersNotifier, UserStickersState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UserStickersNotifier(apiClient);
});

final stickerCatalogProvider =
    StateNotifierProvider<StickerCatalogNotifier, StickerCatalogState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return StickerCatalogNotifier(apiClient);
});

// Single pack provider
final stickerPackProvider =
    FutureProvider.family<StickerPack, String>((ref, packId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.getStickerPack(packId);
  return StickerPack.fromJson(response.data);
});
