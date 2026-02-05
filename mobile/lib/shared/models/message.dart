import 'package:freezed_annotation/freezed_annotation.dart';
import 'user.dart';

part 'message.freezed.dart';
part 'message.g.dart';

enum ConversationType { direct, group }

enum MessageType { text, image, video, audio, file, sticker, system }

enum MessageStatus { sending, sent, delivered, read, failed }

@freezed
class Conversation with _$Conversation {
  const factory Conversation({
    required String id,
    required ConversationType type,
    String? name,
    String? avatarUrl,
    required String createdBy,
    DateTime? lastMessageAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default([]) List<Participant> participants,
    Message? lastMessage,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
}

@freezed
class Participant with _$Participant {
  const factory Participant({
    required String id,
    required String conversationId,
    required String userId,
    @Default('member') String role,
    required DateTime joinedAt,
    DateTime? leftAt,
    DateTime? mutedUntil,
    User? user,
  }) = _Participant;

  factory Participant.fromJson(Map<String, dynamic> json) =>
      _$ParticipantFromJson(json);
}

@freezed
class Message with _$Message {
  const factory Message({
    required String id,
    required String conversationId,
    required String senderId,
    required MessageType type,
    required List<int> content, // Encrypted content
    String? stickerId,
    String? replyToId,
    @Default(MessageStatus.sending) MessageStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    User? sender,
    Message? replyTo,
    @Default([]) List<Receipt> receipts,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);
}

@freezed
class Receipt with _$Receipt {
  const factory Receipt({
    required String id,
    required String messageId,
    required String userId,
    required String type, // 'delivered' or 'read'
    required DateTime createdAt,
  }) = _Receipt;

  factory Receipt.fromJson(Map<String, dynamic> json) => _$ReceiptFromJson(json);
}

// Decrypted message content
@freezed
class DecryptedContent with _$DecryptedContent {
  const factory DecryptedContent.text({
    required String text,
  }) = TextContent;

  const factory DecryptedContent.image({
    required String url,
    String? caption,
    int? width,
    int? height,
  }) = ImageContent;

  const factory DecryptedContent.file({
    required String url,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) = FileContent;

  const factory DecryptedContent.sticker({
    required String stickerId,
    required String packId,
    required String imageUrl,
  }) = StickerContent;
}
