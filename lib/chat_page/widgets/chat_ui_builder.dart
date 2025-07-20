// lib/chat_page/widgets/chat_ui_builder.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/camera_service.dart';
import '../models/message_models.dart';
import 'camera_preview.dart';
import 'chat_bubble.dart';
import 'prompt_bar.dart';

/// Updated to:
/// • Remove **all** shadows across the UI.
/// • Extend the orange status bar full‑width (already done in previous commit).
/// • Add extra bottom padding beneath the generating / speaking text for breathing room.
class ChatUIBuilder {
  // ——————————————————— APP BAR ——————————————————— //
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
          onPressed: isResetting ? null : onNewChat,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('New'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
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

  // ———————————————— VIEW‑TOGGLE BUTTONS ———————————————— //
  static Widget buildViewToggleButtons({
    required bool showCamera,
    required bool showMessages,
    required VoidCallback onToggleCamera,
    required VoidCallback onToggleMessages,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleButton(
              icon: showCamera
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              label: showCamera ? 'Hide Camera' : 'Show Camera',
              isActive: showCamera,
              colors: [const Color(0xFF2196F3), const Color(0xFF1976D2)],
              onPressed: onToggleCamera,
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
  }) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: isActive ? LinearGradient(colors: colors) : null,
              color: isActive ? null : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? Colors.transparent : Colors.grey.shade300,
                width: 2,
              ),
              // Shadows completely removed.
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? Colors.white : Colors.grey.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.grey.shade700,
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

  // —————————————————— CAMERA PREVIEW —————————————————— //
  static Widget buildCameraPreview() {
    final cameraService = CameraService.instance;

    if (cameraService.cameraInitialized &&
        !cameraService.cameraError &&
        cameraService.camera != null) {
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: CameraPreviewBox(camera: cameraService.camera!),
        ),
      );
    }
    return _buildCameraPlaceholder(
      cameraService.cameraError ? 'Camera Error' : 'Camera Initializing…',
    );
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
        // Shadow removed.
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ChatBubble(msg: messages[i]),
          ),
        ),
      ),
    );
  }

  // ———————————————————— PROMPT BAR ———————————————————— //
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
        padding: const EdgeInsets.only(bottom: 10), // extra bottom spacing
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
