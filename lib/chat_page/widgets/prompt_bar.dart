import 'package:flutter/material.dart';

/// Modern light theme prompt bar widget
class PromptBar extends StatefulWidget {
  final Future<void> Function(String) onPromptWithPhoto;
  final Future<void> Function(String) onPromptTextOnly;
  final bool disabled;

  // Speech‑to‑text control flags
  final bool speechEnabled;
  final bool listening;
  final VoidCallback onToggleListening;

  const PromptBar({
    Key? key,
    required this.onPromptWithPhoto,
    required this.onPromptTextOnly,
    this.disabled = false,
    required this.speechEnabled,
    required this.listening,
    required this.onToggleListening,
  }) : super(key: key);

  @override
  State<PromptBar> createState() => PromptBarState();
}

class PromptBarState extends State<PromptBar> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  bool _sending = false;

  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    // Very subtle pulse animation (1.0 to 1.02 instead of 1.1)
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Very subtle scale animation (1.0 to 0.98 instead of 0.95)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    if (widget.listening) {
      _pulseController.repeat(reverse: true);
    }

    // Listen to text changes to update button states
    _ctrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(PromptBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !oldWidget.listening) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.listening && oldWidget.listening) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  /* --------------- external helpers --------------- */
  String get currentText => _ctrl.text;
  void clear() => _ctrl.clear();

  Future<void> sendTextOnly() async => _sendText(_ctrl.text);
  Future<void> sendWithPhoto() async => _sendWithPhoto(_ctrl.text);

  void updateText(String text) {
    setState(() {
      _ctrl.text = text;
      _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _ctrl.text.length),
      );
    });
  }

  /* --------------- voice control helper --------------- */
  void _stopVoiceIfListening() {
    if (widget.listening) {
      widget.onToggleListening();
    }
  }

  /* --------------- internal send helpers ---------- */
  Future<void> _sendWithPhoto(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;

    // Stop voice input if it's active
    _stopVoiceIfListening();

    _ctrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      await widget.onPromptWithPhoto(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;

    // Stop voice input if it's active
    _stopVoiceIfListening();

    _ctrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      await widget.onPromptTextOnly(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildModernButton({
    required String label,
    required VoidCallback? onPressed,
    required List<Color> gradientColors,
    bool isExpanded = true,
    bool showPulse = false,
    bool isEnabled = true,
    IconData? icon,
  }) {
    Widget button = AnimatedBuilder(
      animation: showPulse ? _pulseAnimation : _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: showPulse ? _pulseAnimation.value : 1.0,
          child: GestureDetector(
            onTapDown: isEnabled ? (_) => _scaleController.forward() : null,
            onTapUp: isEnabled ? (_) => _scaleController.reverse() : null,
            onTapCancel: isEnabled ? () => _scaleController.reverse() : null,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: isEnabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradientColors,
                      )
                    : null,
                color: isEnabled ? null : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: gradientColors.first.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? onPressed : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_sending)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        else if (icon != null)
                          Icon(
                            icon,
                            color: isEnabled
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 22,
                          ),
                        if (icon != null && !_sending)
                          const SizedBox(width: 12),
                        Text(
                          label,
                          style: TextStyle(
                            color: isEnabled
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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

    return isExpanded ? Expanded(child: button) : button;
  }

  /* ------------------------------- UI ------------------------------- */
  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled || _sending;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          /* Modern text field */
          _buildModernContainer(
            backgroundColor: Colors.white,
            child: TextField(
              controller: _ctrl,
              enabled: !disabled,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Type your message here…',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
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
              // Remove onChanged since we're using controller listener
              // Stop voice input when user submits via keyboard
              onSubmitted: hasText ? (t) => _sendWithPhoto(t) : null,
            ),
          ),

          const SizedBox(height: 16),

          /* Voice button (full width when available) */
          if (widget.speechEnabled)
            _buildModernButton(
              label: widget.listening
                  ? 'Stop Voice Input'
                  : 'Start Voice Input',
              icon: widget.listening
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              onPressed: disabled ? null : widget.onToggleListening,
              gradientColors: widget.listening
                  ? [Colors.red.shade400, Colors.red.shade600]
                  : [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
              isExpanded: false,
              showPulse: widget.listening,
              isEnabled: !disabled,
            ),

          if (widget.speechEnabled) const SizedBox(height: 16),

          /* Send buttons row */
          Row(
            children: [
              /* Text only button */
              _buildModernButton(
                label: 'Send Text Only',
                onPressed: (disabled || !hasText)
                    ? null
                    : () => _sendText(_ctrl.text),
                gradientColors: [
                  const Color(0xFF2196F3),
                  const Color(0xFF1976D2),
                ],
                isEnabled: !disabled && hasText,
              ),

              const SizedBox(width: 12),

              /* With photo button */
              _buildModernButton(
                label: 'Send with Photo',
                onPressed: (disabled || !hasText)
                    ? null
                    : () => _sendWithPhoto(_ctrl.text),
                gradientColors: [
                  const Color(0xFFFF6B6B),
                  const Color(0xFFEE5A52),
                ],
                isEnabled: !disabled && hasText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
