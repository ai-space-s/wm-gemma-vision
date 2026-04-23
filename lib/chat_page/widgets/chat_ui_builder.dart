// lib/chat_page/widgets/chat_ui_builder.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_settings.dart';
import '../models/message_models.dart';
import 'chat_bubble.dart';
import 'prompt_bar.dart';
import 'semantic_material_button.dart';

enum _ChatMenuAction { save, saveAs, load }

class ChatUIBuilder {
  static PreferredSizeWidget buildCleanAppBar({
    required VoidCallback onNewChat,
    required VoidCallback onToggleSettings,
    required bool isResetting,
    VoidCallback? onSaveChat,
    VoidCallback? onSaveChatAs,
    VoidCallback? onLoadChat,
  }) {
    final highContrast = AppSettings.instance.highContrastEnabled;
    final menuColor = highContrast ? Colors.white : Colors.blue.shade700;
    final bgColor = highContrast ? Colors.black : Colors.white;
    final textColor = highContrast ? Colors.white : Colors.black87;

    return AppBar(
      elevation: 0,
      backgroundColor: bgColor,
      systemOverlayStyle: highContrast
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: Text(
        'Gemma Vision',
        style: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: IconThemeData(color: textColor),
      actions: [
        if (onSaveChat != null && onSaveChatAs != null && onLoadChat != null)
          PopupMenuButton<_ChatMenuAction>(
            tooltip: 'Chat actions',
            color: highContrast ? Colors.grey.shade900 : Colors.white,
            onSelected: (action) {
              switch (action) {
                case _ChatMenuAction.save:
                  onSaveChat();
                  break;
                case _ChatMenuAction.saveAs:
                  onSaveChatAs();
                  break;
                case _ChatMenuAction.load:
                  onLoadChat();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ChatMenuAction.save,
                child: Text('Save chat', style: TextStyle(color: textColor)),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.saveAs,
                child: Text(
                  'Save chat as...',
                  style: TextStyle(color: textColor),
                ),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.load,
                child: Text('Load chat', style: TextStyle(color: textColor)),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_rounded, size: 18, color: menuColor),
                  const SizedBox(width: 4),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: menuColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        SemanticMaterialButton(
          label: 'Settings',
          hint: 'Double-tap to open settings page',
          onPressed: onToggleSettings,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 18, color: menuColor),
                const SizedBox(width: 4),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: menuColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  static Widget buildViewToggleButtons({
    required bool showMessages,
    required VoidCallback onToggleMessages,
    required VoidCallback onNewChat,
    required bool isResetting,
  }) {
    final highContrast = AppSettings.instance.highContrastEnabled;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Row(
          children: [
            Expanded(
              child: _buildToggleButton(
                icon: Icons.refresh_rounded,
                label: 'New Chat',
                hint: isResetting
                    ? 'New chat is currently processing'
                    : 'Double-tap to start a new chat conversation',
                isActive: true,
                activeColor: highContrast ? Colors.white : Colors.teal,
                inactiveColor: highContrast
                    ? Colors.black
                    : const Color(0xFFE8F5E8),
                onPressed: isResetting ? null : onNewChat,
                disabled: isResetting,
                highContrast: highContrast,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildToggleButton(
                icon: showMessages
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                label: showMessages ? 'Hide Messages' : 'Show Messages',
                hint: showMessages
                    ? 'Double-tap to hide the conversation messages'
                    : 'Double-tap to show the conversation messages',
                isActive: showMessages,
                activeColor: highContrast ? Colors.white : Colors.blueAccent,
                inactiveColor: highContrast
                    ? Colors.black
                    : const Color(0xFFE3F2FD),
                onPressed: onToggleMessages,
                disabled: false,
                highContrast: highContrast,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback? onPressed,
    required String hint,
    required bool highContrast,
    bool disabled = false,
  }) {
    Color backgroundColor;
    Color textColor;
    Color iconColor;

    if (disabled) {
      backgroundColor = highContrast
          ? Colors.grey.shade900
          : const Color(0xFFE0E7FF);
      textColor = const Color(0xFF9CA3AF);
      iconColor = const Color(0xFF9CA3AF);
    } else if (isActive) {
      backgroundColor = activeColor;
      textColor = highContrast ? Colors.black : Colors.white;
      iconColor = highContrast ? Colors.black : Colors.white;
    } else {
      backgroundColor = inactiveColor;
      textColor = activeColor;
      iconColor = activeColor;
      if (highContrast) {
        backgroundColor = Colors.black;
        textColor = Colors.white;
        iconColor = Colors.white;
      }
    }

    return SemanticMaterialButton(
      label: label,
      hint: hint,
      onPressed: disabled ? null : onPressed,
      disabled: disabled,
      child: SizedBox(
        height: 56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: null,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: highContrast ? Border.all(color: Colors.white) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget buildMessagesContainer(
    List<ChatMessage> messages,
    ScrollController scrollController,
  ) {
    return Expanded(
      child: Semantics(
        label: 'Chat messages',
        hint: 'Swipe to scroll through conversation history',
        child: ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: messages.length,
          semanticChildCount: messages.length,
          itemBuilder: (_, i) => Semantics(
            label: messages[i].isUser
                ? 'Your message ${i + 1} of ${messages.length}'
                : 'AI response ${i + 1} of ${messages.length}',
            child: ChatBubble(msg: messages[i]),
          ),
        ),
      ),
    );
  }

  // [수정] PromptBar API 변경 사항 반영 (onPromptWithCamera, onPromptWithGallery)
  static Widget buildPromptBarContainer({
    required GlobalKey<PromptBarState> promptBarKey,
    required Future<void> Function(String) onPromptWithCamera, // New
    required Future<void> Function(String) onPromptWithGallery, // New
    required Future<void> Function(String) onPromptTextOnly,
    required bool disabled,
    required bool speechEnabled,
    required bool listening,
    required VoidCallback onToggleListening,
    required bool isGenerating,
    required bool isSpeaking,
    Future<void> Function()? onStopTts,
  }) {
    final highContrast = AppSettings.instance.highContrastEnabled;
    if (isGenerating || isSpeaking) {
      return _buildStatusWidget(
        isGenerating: isGenerating,
        isSpeaking: isSpeaking,
        onStopTts: onStopTts,
      );
    }

    return Container(
      color: highContrast ? Colors.black : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PromptBar(
            key: promptBarKey,
            onPromptWithCamera: onPromptWithCamera, // New
            onPromptWithGallery: onPromptWithGallery, // New
            onPromptTextOnly: onPromptTextOnly,
            disabled: disabled,
            speechEnabled: speechEnabled,
            listening: listening,
            onToggleListening: onToggleListening,
            onStopTts: onStopTts,
          ),
        ),
      ),
    );
  }

  static Widget _buildStatusWidget({
    required bool isGenerating,
    required bool isSpeaking,
    Future<void> Function()? onStopTts,
  }) {
    final highContrast = AppSettings.instance.highContrastEnabled;

    final content = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
              ),
        color: highContrast ? Colors.grey.shade900 : null,
        border: highContrast
            ? Border(top: BorderSide(color: Colors.white, width: 2))
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 80,
          padding: const EdgeInsets.only(bottom: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isGenerating)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              const SizedBox(width: 16),
              Text(
                isGenerating
                    ? (isSpeaking
                          ? 'Generating and Speaking...'
                          : 'Generating Response...')
                    : 'Speaking... (Double Tap to Stop)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      onDoubleTap: () {
        if (isSpeaking && onStopTts != null) {
          onStopTts();
          HapticFeedback.lightImpact();
        }
      },
      child: Semantics(
        label: isGenerating
            ? 'Generating response. Please wait.'
            : 'Speaking response. Double tap to stop speaking.',
        button: true,
        onTap: isSpeaking && onStopTts != null
            ? () {
                onStopTts();
              }
            : null,
        child: content,
      ),
    );
  }

  static Widget buildLoadingScreen() {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF2196F3)),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}
