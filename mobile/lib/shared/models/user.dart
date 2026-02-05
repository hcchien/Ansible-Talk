import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class User with _$User {
  const factory User({
    required String id,
    String? phone,
    String? email,
    required String username,
    required String displayName,
    String? avatarUrl,
    String? bio,
    @Default('offline') String status,
    DateTime? lastSeenAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

@freezed
class Device with _$Device {
  const factory Device({
    required String id,
    required String userId,
    required int deviceId,
    required String name,
    required String platform,
    required DateTime lastActiveAt,
    required DateTime createdAt,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
}

@freezed
class Contact with _$Contact {
  const factory Contact({
    required String id,
    required String userId,
    required String contactId,
    String? nickname,
    @Default(false) bool isBlocked,
    @Default(false) bool isFavorite,
    required DateTime createdAt,
    required DateTime updatedAt,
    User? contact,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) => _$ContactFromJson(json);
}

@freezed
class TokenPair with _$TokenPair {
  const factory TokenPair({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) = _TokenPair;

  factory TokenPair.fromJson(Map<String, dynamic> json) => _$TokenPairFromJson(json);
}
