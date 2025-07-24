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
              isActive: false, // Always styled as inactive button
              colors: [const Color(0xFF2196F3), const Color(0xFF1976D2)],
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
              colors: [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
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
    required List<Color> colors,
    required VoidCallback onPressed,
    bool disabled = false,
  }) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: isActive ? LinearGradient(colors: colors) : null,
              color: isActive
                  ? null
                  : (disabled ? Colors.grey.shade100 : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? Colors.transparent : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: disabled
                      ? Colors.grey.shade400
                      : (isActive ? Colors.white : Colors.grey.shade700),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: disabled
                        ? Colors.grey.shade400
                        : (isActive ? Colors.white : Colors.grey.shade700),
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

  // —————————————————— CAMERA PLACEHOLDER —————————————————— //
  static Widget buildCameraPreview() {
    // Since we're using on-demand camera, just show a placeholder
    return _buildCameraPlaceholder('Camera captures on photo messages');
  }

  static Widget _buildCameraPlaceholder(String msg) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey.shade50, Colors.grey.shade100],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 32,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              msg,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ———————————————————— MESSAGES LIST ———————————————————— //
  static Widget buildMessagesContainer(List<ChatMessage> messages) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Semantics(
          label: 'Chat messages',
          hint: 'Swipe to scroll through conversation history',
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            semanticChildCount: messages.length,
            itemBuilder: (_, i) => Semantics(
              label: messages[i].isUser
                  ? 'Your message ${i + 1} of ${messages.length}'
                  : 'AI response ${i + 1} of ${messages.length}',
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ChatBubble(msg: messages[i]),
              ),
            ),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
          ),
        ),
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
