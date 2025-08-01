// lib/chat_page/widgets/semantic_elevated_button.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'semantic_button_registry.dart';

/// ElevatedButton with cross-platform semantic integration
/// Based on your demo's _UniversalButton pattern
class SemanticElevatedButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? child;
  final ButtonStyle? style;
  final bool autofocus;

  const SemanticElevatedButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.child,
    this.style,
    this.autofocus = false,
  }) : super(key: key);

  @override
  State<SemanticElevatedButton> createState() => _SemanticElevatedButtonState();
}

class _SemanticElevatedButtonState extends State<SemanticElevatedButton> {
  late final FocusNode _focusNode;
  bool _hasAccessibilityFocus = false;

  // Platform detection
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    // Clean up registry if this was the current target
    if (SemanticButtonRegistry.currentSemanticTap == _handlePressed) {
      SemanticButtonRegistry.currentSemanticTap = null;
    }
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    debugPrint(
      _focusNode.hasFocus
          ? 'FLUTTER-FOCUS-GAINED: ${widget.label}'
          : 'FLUTTER-FOCUS-LOST  : ${widget.label}',
    );
  }

  void _handlePressed() {
    debugPrint('BUTTON-PRESSED: ${widget.label}');
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canPress = widget.onPressed != null;

    return Semantics(
      // Platform-agnostic semantics
      excludeSemantics: _isIOS, // iOS uses custom semantics
      container: true,
      button: true,
      enabled: canPress,
      focusable: true,
      focused: _hasAccessibilityFocus,
      label: widget.label,
      hint: _isIOS ? 'Double tap to activate' : null,
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
      child: ElevatedButton(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onPressed: canPress ? _handlePressed : null,
        style: widget.style,
        child: widget.child ?? Text(widget.label),
      ),
    );
  }
}
