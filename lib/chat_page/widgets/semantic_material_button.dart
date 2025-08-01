// lib/chat_page/widgets/semantic_material_button.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'semantic_button_registry.dart';

/// Universal button based on working cross-platform demo pattern
class SemanticMaterialButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool disabled;
  final String? hint;

  const SemanticMaterialButton({
    Key? key,
    required this.label,
    required this.child,
    this.onPressed,
    this.disabled = false,
    this.hint,
  }) : super(key: key);

  @override
  State<SemanticMaterialButton> createState() => _SemanticMaterialButtonState();
}

class _SemanticMaterialButtonState extends State<SemanticMaterialButton> {
  late final FocusNode _focusNode;
  bool _hasAccessibilityFocus = false;

  // Platform detection
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    // Clean up registry if this was the current target
    if (SemanticButtonRegistry.currentSemanticTap == _handlePressed) {
      SemanticButtonRegistry.currentSemanticTap = null;
    }
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    debugPrint(
      _focusNode.hasFocus
          ? 'FLUTTER-FOCUS-GAINED: ${widget.label}'
          : 'FLUTTER-FOCUS-LOST  : ${widget.label}',
    );
  }

  void _handlePressed() {
    debugPrint('BUTTON-PRESSED: ${widget.label}');
    if (!widget.disabled) {
      widget.onPressed?.call();
    }
  }

  // ✅ PUBLIC METHODS: Allow external focus management (like in working demo)
  void gainAccessibilityFocus() {
    setState(() {
      _hasAccessibilityFocus = true;
    });

    // Platform-specific focus handling (matching working demo pattern)
    if (_isIOS) {
      // iOS: Register for static tap and request Flutter focus
      SemanticButtonRegistry.currentSemanticTap = _handlePressed;
      _focusNode.requestFocus();
    } else {
      // Android: Request Flutter focus
      _focusNode.requestFocus();
    }

    debugPrint('ACCESSIBILITY-FOCUS-GAINED: ${widget.label}');
  }

  void loseAccessibilityFocus() {
    setState(() {
      _hasAccessibilityFocus = false;
    });

    // Clear iOS static registry if this was the current target
    if (_isIOS && SemanticButtonRegistry.currentSemanticTap == _handlePressed) {
      SemanticButtonRegistry.currentSemanticTap = null;
    }

    debugPrint('ACCESSIBILITY-FOCUS-LOST: ${widget.label}');
  }

  void simulatePress() {
    _handlePressed();
  }

  @override
  Widget build(BuildContext context) {
    final canPress = !widget.disabled && widget.onPressed != null;

    return Semantics(
      // ✅ MATCHING WORKING DEMO: Platform-agnostic semantics structure
      excludeSemantics: _isIOS, // iOS uses custom semantics
      container: true,
      button: true,
      enabled: canPress,
      focusable: true,
      focused: _hasAccessibilityFocus,
      label: widget.label,
      hint: _isIOS ? 'Double tap to activate' : widget.hint,
      onTap: canPress ? _handlePressed : null,
      onDidGainAccessibilityFocus: canPress
          ? () {
              debugPrint('SEMANTICS-FOCUS-GAINED: ${widget.label}');
              if (_isIOS) {
                SemanticButtonRegistry.currentSemanticTap = _handlePressed;
                _focusNode.requestFocus();
              }
              setState(() {
                _hasAccessibilityFocus = true;
              });
            }
          : null,
      onDidLoseAccessibilityFocus: canPress
          ? () {
              debugPrint('SEMANTICS-FOCUS-LOST: ${widget.label}');
              if (_isIOS &&
                  SemanticButtonRegistry.currentSemanticTap == _handlePressed) {
                SemanticButtonRegistry.currentSemanticTap = null;
              }
              setState(() {
                _hasAccessibilityFocus = false;
              });
            }
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: _focusNode,
          onTap: canPress ? _handlePressed : null,
          borderRadius: BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}
