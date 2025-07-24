// lib/chat_page/widgets/chat_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/message_models.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;

  const ChatBubble({Key? key, required this.msg}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If message has both image and text, show them as separate bubbles
    if (msg.imageFile != null && msg.text.isNotEmpty) {
      return Column(
        crossAxisAlignment: msg.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Image bubble
          _buildImageBubble(context),
          const SizedBox(
            height: 2,
          ), // Reduced spacing to make them feel connected
          // Text bubble
          _buildTextBubble(context),
        ],
      );
    }

    // If only image, show centered image bubble
    if (msg.imageFile != null) {
      return _buildImageBubble(context);
    }

    // If only text, show regular text bubble
    return _buildTextBubble(context);
  }

  Widget _buildImageBubble(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: msg.isUser ? 60.0 : 8.0,
        right: msg.isUser ? 8.0 : 60.0,
        top: 2.0,
        bottom: 2.0,
      ),
      child: Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: GestureDetector(
              onTap: () => _showFullScreenImage(context, msg.imageFile!),
              child: Hero(
                tag: 'image_${msg.text}_${msg.imageFile!.path}',
                child: Image.file(
                  msg.imageFile!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Could not load image',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextBubble(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: msg.isUser ? 60.0 : 8.0, // Reduced horizontal padding
        right: msg.isUser ? 8.0 : 60.0, // Reduced horizontal padding
        top: 4.0,
        bottom: 4.0,
      ),
      child: Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: msg.isUser ? Colors.blueAccent : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.text.isNotEmpty) _buildMessageContent(context),

                // Show stats if available
                if (msg.stats != null &&
                    !msg.isStreaming &&
                    msg.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: _buildStatsWidget(msg.stats!),
                  ),

                // Show streaming indicator
                if (msg.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          msg.isUser ? Colors.white : Colors.blueAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    // For user messages or simple text without markdown, use regular Text widget
    // For AI messages that might contain markdown/LaTeX, use GptMarkdown
    return GptMarkdown(
      msg.text,
      style: TextStyle(
        color: msg.isUser ? Colors.white : Colors.black87,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.3,
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, File imageFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Image', style: TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: Hero(
              tag: 'image_${msg.text}_${imageFile.path}',
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load image',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsWidget(MessageStats stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 10,
            color: msg.isUser ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 3),
          Text(
            '${stats.tokenCount} tokens • ${stats.totalLatency!.toStringAsFixed(1)}s',
            style: TextStyle(
              color: msg.isUser ? Colors.white70 : Colors.black54,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (stats.timeToFirstToken != null) ...[
            Text(
              ' • TTFT ${stats.timeToFirstToken!.toStringAsFixed(1)}s',
              style: TextStyle(
                color: msg.isUser ? Colors.white70 : Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (stats.decodeSpeed != null) ...[
            Text(
              ' • ${stats.decodeSpeed!.toStringAsFixed(1)} tok/s',
              style: TextStyle(
                color: msg.isUser ? Colors.white70 : Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
