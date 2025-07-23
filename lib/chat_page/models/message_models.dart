// models/message_models.dart
import 'dart:io';
import 'dart:typed_data';

/// Chat message model with image support
class ChatMessage {
  String text;
  final bool isUser;
  bool isStreaming;
  MessageStats? stats;
  File? imageFile; // For camera captured images
  Uint8List? imageBytes; // For in-memory images

  ChatMessage(
    this.text, {
    required this.isUser,
    this.isStreaming = false,
    this.stats,
    this.imageFile,
    this.imageBytes,
  });

  /// Create a text-only message
  ChatMessage.text(
    this.text, {
    required this.isUser,
    this.isStreaming = false,
    this.stats,
  }) : imageFile = null,
       imageBytes = null;

  /// Create a message with image file
  ChatMessage.withImageFile(
    this.text, {
    required this.isUser,
    required this.imageFile,
    this.isStreaming = false,
    this.stats,
  }) : imageBytes = null;

  /// Create a message with image bytes
  ChatMessage.withImageBytes(
    this.text, {
    required this.isUser,
    required this.imageBytes,
    this.isStreaming = false,
    this.stats,
  }) : imageFile = null;

  /// Check if this message has any image
  bool get hasImage => imageFile != null || imageBytes != null;

  /// Get image data as bytes (useful for API calls)
  Future<Uint8List?> getImageBytes() async {
    if (imageBytes != null) return imageBytes;
    if (imageFile != null) return await imageFile!.readAsBytes();
    return null;
  }
}

/// Performance statistics for AI responses
class MessageStats {
  final double? timeToFirstToken;
  final double? totalLatency;
  final double? prefillSpeed;
  final double? decodeSpeed;
  final int? tokenCount;

  const MessageStats({
    this.timeToFirstToken,
    this.totalLatency,
    this.prefillSpeed,
    this.decodeSpeed,
    this.tokenCount,
  });
}
