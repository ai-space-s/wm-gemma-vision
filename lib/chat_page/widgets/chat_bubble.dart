// widgets/chat_bubble.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../models/message_models.dart';

/// Chat bubble widget for displaying messages with image support
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;

  const ChatBubble({Key? key, required this.msg}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: msg.isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: msg.isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show image if present
                if (msg.imageFile != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      msg.imageFile!,
                      width: 150, // Smaller fixed width
                      height: 120, // Fixed height for consistency
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (msg.imageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      msg.imageBytes!,
                      width: 150, // Smaller fixed width
                      height: 120, // Fixed height for consistency
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Show text content
                if (msg.text.isNotEmpty) ...[
                  // Use GptMarkdown widget for AI responses, plain text for user messages
                  if (msg.isUser)
                    Text(msg.text)
                  else
                    GptMarkdown(msg.text, style: const TextStyle(fontSize: 14)),
                ],
                if (msg.isStreaming && !msg.isUser)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Show stats for AI messages
        if (!msg.isUser && msg.stats != null && !msg.isStreaming)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: StatsWidget(stats: msg.stats!),
          ),
      ],
    );
  }
}

/// Widget for displaying performance statistics (now wrapping)
class StatsWidget extends StatelessWidget {
  final MessageStats stats;

  const StatsWidget({Key? key, required this.stats}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // assemble each piece separately
    final parts = <String>[];
    if (stats.timeToFirstToken != null) {
      parts.add('TTFT: ${stats.timeToFirstToken!.toStringAsFixed(2)}s');
    }
    if (stats.totalLatency != null) {
      parts.add('Total: ${stats.totalLatency!.toStringAsFixed(2)}s');
    }
    if (stats.prefillSpeed != null) {
      parts.add('Prefill: ${stats.prefillSpeed!.toStringAsFixed(1)} t/s');
    }
    if (stats.decodeSpeed != null) {
      parts.add('Decode: ${stats.decodeSpeed!.toStringAsFixed(1)} t/s');
    }
    if (stats.tokenCount != null) {
      parts.add('${stats.tokenCount} tokens');
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          const Icon(Icons.speed, size: 12, color: Colors.grey),
          // interleave bullets and parts
          for (var i = 0; i < parts.length; i++) ...[
            Text(
              parts[i],
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (i < parts.length - 1)
              const Text(
                '•',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ],
      ),
    );
  }
}
