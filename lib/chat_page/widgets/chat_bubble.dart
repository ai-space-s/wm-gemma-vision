// lib/chat_page/widgets/chat_bubble.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/message_models.dart';
import '../../app_settings.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;

  const ChatBubble({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    if (msg.imageFile != null && msg.text.isNotEmpty) {
      return Column(
        crossAxisAlignment: msg.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          _buildImageBubble(context),
          const SizedBox(height: 2),
          _buildTextBubble(context),
        ],
      );
    }

    if (msg.imageFile != null) {
      return _buildImageBubble(context);
    }

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
    final highContrast = AppSettings.instance.highContrastEnabled;

    // [수정] 고대비 모드 및 Function Call 색상 로직 개선
    // 기본 AI 배경색
    Color aiNormalColor = highContrast ? Colors.black : Colors.grey.shade200;
    // Function Call 결과 배경색 (연한 인디고/파랑 계열)
    Color aiFunctionColor = highContrast ? Colors.black : Colors.indigo.shade50;

    final userBubbleColor = highContrast ? Colors.black : Colors.blueAccent;
    // msg.isFunctionResult가 true이면 다른 색 사용
    final aiBubbleColor = msg.isFunctionResult ? aiFunctionColor : aiNormalColor;

    // 고대비일 경우 테두리로 구분
    final border = highContrast
        ? Border.all(color: Colors.white, width: 2)
        : (msg.isUser ? null : (msg.isFunctionResult ? Border.all(color: Colors.indigo.shade100) : null));

    final textColor = highContrast
        ? Colors.white
        : (msg.isUser ? Colors.white : Colors.black87);

    return Padding(
      padding: EdgeInsets.only(
        left: msg.isUser ? 60.0 : 8.0,
        right: msg.isUser ? 8.0 : 60.0,
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
            color: msg.isUser ? userBubbleColor : aiBubbleColor,
            border: border,
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
                if (msg.text.isNotEmpty) _buildMessageContent(context, textColor),

                if (msg.stats != null &&
                    !msg.isStreaming &&
                    msg.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: _buildStatsWidget(msg.stats!, textColor),
                  ),

                if (msg.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(textColor),
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

  Widget _buildMessageContent(BuildContext context, Color textColor) {
    return GptMarkdown(
      msg.text,
      style: TextStyle(
        color: textColor,
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

  Widget _buildStatsWidget(MessageStats stats, Color textColor) {
    final opacityColor = textColor.withOpacity(0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 10,
            color: opacityColor,
          ),
          const SizedBox(width: 3),
          Text(
            '${stats.tokenCount} tokens • ${stats.totalLatency!.toStringAsFixed(1)}s',
            style: TextStyle(
              color: opacityColor,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}