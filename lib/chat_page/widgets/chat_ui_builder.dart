// lib/chat_page/widgets/chat_ui_builder.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message_models.dart';
import 'chat_bubble.dart';
import 'prompt_bar.dart';

/// Updated to remove camera service dependency
class ChatUIBuilder {
  // ——————————————————— APP BAR ——————————————————— //
  static PreferredSizeWidget buildCleanAppBar({
    required VoidCallback onNewChat,
    required VoidCallback onToggleSettings,
    required bool isResetting,
  }) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      title: const Text(
        'Gemma Vision',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: onToggleSettings,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Settings'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  // ———————————————— VIEW‑TOGGLE BUTTONS ———————————————— //
  static Widget buildViewToggleButtons({
    required bool showMessages,
    required VoidCallback onToggleMessages,
    required VoidCallback onNewChat,
    required bool isResetting,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleButton(
              icon: Icons.refresh_rounded,
              label: 'New Chat',
              isActive: true,
              activeColor: Colors.teal, // Green
              inactiveColor: const Color(0xFFE8F5E8), // Light green
              onPressed: isResetting ? () {} : onNewChat,
              disabled: isResetting,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildToggleButton(
              icon: showMessages
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
              label: showMessages ? 'Hide Messages' : 'Show Messages',
              isActive: showMessages,
              activeColor: Colors.blueAccent, // Blue
              inactiveColor: const Color(0xFFE3F2FD), // Light blue
              onPressed: onToggleMessages,
              disabled: false,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onPressed,
    bool disabled = false,
  }) {
    Color backgroundColor;
    Color textColor;
    Color iconColor;

    if (disabled) {
      backgroundColor = const Color(0xFFE0E7FF);
      textColor = const Color(0xFF9CA3AF);
      iconColor = const Color(0xFF9CA3AF);
    } else if (isActive) {
      backgroundColor = activeColor;
      textColor = Colors.white;
      iconColor = Colors.white;
    } else {
      backgroundColor = inactiveColor;
      textColor = activeColor;
      iconColor = activeColor;
    }

    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
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
    );
  }

  // ———————————————————— MESSAGES LIST ———————————————————— //
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

  // ———————————————————— PROMPT BAR ———————————————————— //
  static Widget buildPromptBarContainer({
    required GlobalKey<PromptBarState> promptBarKey,
    required Future<void> Function(String) onPromptWithPhoto,
    required Future<void> Function(String) onPromptTextOnly,
    required bool disabled,
    required bool speechEnabled,
    required bool listening,
    required VoidCallback onToggleListening,
    required bool isGenerating,
    required bool isSpeaking,
    Future<void> Function()? onStopTts, // Add TTS stop callback
  }) {
    // Full‑width orange bar when busy; plain white strip when idle.
    if (isGenerating || isSpeaking) {
      return _buildStatusWidget(
        isGenerating: isGenerating,
        isSpeaking: isSpeaking,
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: PromptBar(
        key: promptBarKey,
        onPromptWithPhoto: onPromptWithPhoto,
        onPromptTextOnly: onPromptTextOnly,
        disabled: disabled,
        speechEnabled: speechEnabled,
        listening: listening,
        onToggleListening: onToggleListening,
        onStopTts: onStopTts, // Pass the TTS stop callback
      ),
    );
  }

  static Widget _buildStatusWidget({
    required bool isGenerating,
    required bool isSpeaking,
  }) {
    return Container(
      height: 80,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              isGenerating
                  ? (isSpeaking
                        ? 'Generating and Speaking…'
                        : 'Generating Response…')
                  : 'Speaking…',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ———————————————————— LOADING SCREEN ———————————————————— //
  static Widget buildLoadingScreen() {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF2196F3)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Initializing Gemma…',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
