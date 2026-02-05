import 'package:freezed_annotation/freezed_annotation.dart';

part 'sticker.freezed.dart';
part 'sticker.g.dart';

@freezed
class StickerPack with _$StickerPack {
  const factory StickerPack({
    required String id,
    required String name,
    required String author,
    String? description,
    required String coverUrl,
    @Default(false) bool isOfficial,
    @Default(false) bool isAnimated,
    @Default(0) int price,
    @Default(0) int downloads,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default([]) List<Sticker> stickers,
  }) = _StickerPack;

  factory StickerPack.fromJson(Map<String, dynamic> json) =>
      _$StickerPackFromJson(json);
}

@freezed
class Sticker with _$Sticker {
  const factory Sticker({
    required String id,
    required String packId,
    required String emoji,
    required String imageUrl,
    required int position,
    required DateTime createdAt,
  }) = _Sticker;

  factory Sticker.fromJson(Map<String, dynamic> json) => _$StickerFromJson(json);
}

@freezed
class UserStickerPack with _$UserStickerPack {
  const factory UserStickerPack({
    required String id,
    required String userId,
    required String packId,
    required int position,
    required DateTime createdAt,
    StickerPack? pack,
  }) = _UserStickerPack;

  factory UserStickerPack.fromJson(Map<String, dynamic> json) =>
      _$UserStickerPackFromJson(json);
}
