// lib/chat_page/widgets/prompt_bar.dart
import 'package:flutter/foundation.dart'; // kIsWeb, defaultTargetPlatform
import 'package:flutter/material.dart';
import '../services/sound_manager.dart';
import 'semantic_material_button.dart';

/// Interactive prompt input bar with text field, voice input, and send buttons
/// Handles both text-only and photo+text message composition with accessibility support
class PromptBar extends StatefulWidget {
  final Future<void> Function(String) onPromptWithCamera;
  final Future<void> Function(String) onPromptWithGallery;
  final Future<void> Function(String) onPromptTextOnly;
  final bool disabled;
  final bool speechEnabled;
  final bool listening;
  final VoidCallback onToggleListening;
  final Future<void> Function()? onStopTts;

  const PromptBar({
    super.key,
    required this.onPromptWithCamera,
    required this.onPromptWithGallery,
    required this.onPromptTextOnly,
    this.disabled = false,
    required this.speechEnabled,
    required this.listening,
    required this.onToggleListening,
    this.onStopTts,
  });

  @override
  State<PromptBar> createState() => PromptBarState();
}

class PromptBarState extends State<PromptBar> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  bool _sending = false;

  // Button press animation for tactile feedback
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Setup button press animation
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // Rebuild UI when text changes (enables/disables send buttons)
    _ctrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // Public API for external access
  String get currentText => _ctrl.text;
  void clear() => _ctrl.clear();

  /// External API: Send current text without photo (used by keyboard shortcuts)
  Future<void> sendTextOnly() async => _sendText(_ctrl.text);

  /// External API: Send current text with camera (used by keyboard shortcuts)
  Future<void> sendWithCamera() async => _sendWithCamera(_ctrl.text);

  /// Update text content programmatically (used by speech recognition)
  void updateText(String text) {
    setState(() {
      _ctrl.text = text;
      // Move cursor to end of text
      _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _ctrl.text.length),
      );
    });
  }

  /// Stop voice input if currently listening (before sending messages)
  void _stopVoiceIfListening() {
    if (widget.listening) {
      widget.onToggleListening();
    }
  }

  /// Handle dictation button with audio feedback and state management
  Future<void> _handleDictationToggle() async {
    if (widget.disabled || _sending) return;

    if (widget.listening) {
      // Stop dictation
      widget.onToggleListening();
      await SoundManager.instance.playDictationStop();
    } else {
      // Start dictation with audio feedback
      await SoundManager.instance.playDictationStart();
      widget.onToggleListening();
    }
  }

  /// Send message with camera capture
  Future<void> _sendWithCamera(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;

    if (widget.onStopTts != null) await widget.onStopTts!();
    _stopVoiceIfListening();
    _ctrl.clear();

    setState(() => _sending = true);
    try {
      await widget.onPromptWithCamera(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Send message with gallery image
  Future<void> _sendWithGallery(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;

    if (widget.onStopTts != null) await widget.onStopTts!();
    _stopVoiceIfListening();
    _ctrl.clear();

    setState(() => _sending = true);
    try {
      await widget.onPromptWithGallery(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Send text-only message
  Future<void> _sendText(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;

    if (widget.onStopTts != null) await widget.onStopTts!();
    _stopVoiceIfListening();
    _ctrl.clear();

    setState(() => _sending = true);
    try {
      await widget.onPromptTextOnly(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Reusable modern container styling
  Widget _buildModernContainer({
    required Widget child,
    EdgeInsets? padding,
    double? height,
    Color? backgroundColor,
  }) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Platform-aware gradient button with accessibility integration
  Widget _buildModernButton({
    required String label,
    required VoidCallback? onPressed,
    required List<Color> gradientColors,
    bool isExpanded = true,
    bool isEnabled = true,
    IconData? icon,
    String? hint,
  }) {
    // Disabled button styling
    if (!isEnabled || onPressed == null) {
      final disabledButton = Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_sending) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(icon, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      );
      return isExpanded ? Expanded(child: disabledButton) : disabledButton;
    }

    Widget button;

    // Platform-specific button implementation
    // [수정] Web 지원 및 Platform.isAndroid 에러 방지
    bool isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      // Android: Direct approach without semantic wrapper
      button = AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors.first.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Semantics(
                  button: true,
                  enabled: true,
                  label: label,
                  hint: hint,
                  onTap: onPressed,
                  child: InkWell(
                    onTap: () {
                      _scaleController.forward().then((_) {
                        _scaleController.reverse();
                      });
                      onPressed();
                    },
                    onTapDown: (_) => _scaleController.forward(),
                    onTapUp: (_) => _scaleController.reverse(),
                    onTapCancel: () => _scaleController.reverse(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_sending) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      // iOS & Web: Use SemanticMaterialButton for VoiceOver/ScreenReader compatibility
      final buttonContent = AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors.first.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _scaleController.forward().then((_) {
                      _scaleController.reverse();
                    });
                    onPressed();
                  },
                  onTapDown: (_) => _scaleController.forward(),
                  onTapUp: (_) => _scaleController.reverse(),
                  onTapCancel: () => _scaleController.reverse(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_sending) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

      // Wrap with semantic accessibility layer for iOS/Web
      button = SemanticMaterialButton(
        label: label,
        hint: hint,
        onPressed: onPressed,
        disabled: false,
        child: buttonContent,
      );
    }

    return isExpanded ? Expanded(child: button) : button;
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled || _sending;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return SafeArea(
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Multi-line text input with clear button
            _buildModernContainer(
              backgroundColor: Colors.white,
              child: Focus(
                canRequestFocus: true,
                child: TextField(
                  controller: _ctrl,
                  enabled: !disabled,
                  minLines: 1,
                  maxLines: 4, // Allow multi-line input
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Type your message here…',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(20),
                    // Show clear button when text is present
                    suffixIcon: hasText
                        ? IconButton(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() {});
                            },
                            icon: Icon(
                              Icons.clear_rounded,
                              color: Colors.grey.shade500,
                            ),
                          )
                        : null,
                  ),
                  // Enter key sends message with camera
                  onSubmitted: hasText ? (t) => _sendWithCamera(t) : null,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // [수정] Row 1: Voice and Text Buttons (짧은 레이블 적용)
            Row(
              children: [
                if (widget.speechEnabled)
                  _buildModernButton(
                    label: widget.listening ? 'Stop Voice' : 'Start Voice',
                    hint: widget.listening
                        ? 'Double-tap to stop recording'
                        : 'Double-tap to start recording',
                    icon: widget.listening
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    onPressed: _handleDictationToggle,
                    gradientColors: widget.listening
                        ? [Colors.red.shade400, Colors.red.shade600]
                        : [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
                    isEnabled: !widget.disabled,
                  ),

                if (widget.speechEnabled) const SizedBox(width: 12),

                _buildModernButton(
                  label: 'Text', // [수정] Send Text Only -> Text
                  hint: hasText
                      ? 'Double-tap to send text only'
                      : 'Type a message first',
                  onPressed: hasText ? () => _sendText(_ctrl.text) : null,
                  gradientColors: [
                    const Color(0xFF2196F3),
                    const Color(0xFF1976D2),
                  ],
                  isEnabled: hasText && !widget.disabled,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // [수정] Row 2: Photo (Gallery) and Camera Buttons (짧은 레이블 적용)
            Row(
              children: [
                _buildModernButton(
                  label: 'Photo', // [수정] Send with Photo -> Photo (Gallery)
                  hint: hasText
                      ? 'Double-tap to choose photo from gallery'
                      : 'Type a message first',
                  onPressed: hasText
                      ? () => _sendWithGallery(_ctrl.text)
                      : null,
                  icon: Icons.photo_library_rounded,
                  gradientColors: [
                    Colors.orange.shade400,
                    Colors.orange.shade600,
                  ],
                  isEnabled: hasText && !widget.disabled,
                ),
                const SizedBox(width: 12),
                _buildModernButton(
                  label: 'Camera', // [수정] Send with Camera -> Camera
                  hint: hasText
                      ? 'Double-tap to take a photo'
                      : 'Type a message first',
                  onPressed: hasText ? () => _sendWithCamera(_ctrl.text) : null,
                  icon: Icons.camera_alt_rounded,
                  gradientColors: [
                    const Color(0xFFFF6B6B),
                    const Color(0xFFEE5A52),
                  ],
                  isEnabled: hasText && !widget.disabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
