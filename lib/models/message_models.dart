// models/message_models.dart

/// Camera source enum
enum CameraSource { phone, ip }

/// Performance statistics for each message
class MessageStats {
  final double? timeToFirstToken;
  final double? totalLatency;
  final double? prefillSpeed;
  final double? decodeSpeed;
  final int? tokenCount;

  MessageStats({
    this.timeToFirstToken,
    this.totalLatency,
    this.prefillSpeed,
    this.decodeSpeed,
    this.tokenCount,
  });
}

/// Chat message model
class ChatMessage {
  String text;
  final bool isUser;
  bool isStreaming;
  MessageStats? stats;

  ChatMessage(
    this.text, {
    required this.isUser,
    this.isStreaming = false,
    this.stats,
  });
}
