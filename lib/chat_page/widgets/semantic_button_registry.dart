// lib/chat_page/widgets/semantic_button_registry.dart
import 'package:flutter/foundation.dart';

/// Simplified semantic button registry following the working cross-platform pattern
class SemanticButtonRegistry {
  static VoidCallback? _currentSemanticTap;

  // Public getter for accessing current semantic tap (needed by semantic buttons)
  static VoidCallback? get currentSemanticTap => _currentSemanticTap;

  // Public setter for updating current semantic tap (needed by semantic buttons)
  static set currentSemanticTap(VoidCallback? callback) {
    _currentSemanticTap = callback;
  }

  /// Check if there's a currently registered semantic tap
  static bool get hasSemanticTap => _currentSemanticTap != null;

  /// Register a button as the current semantic target
  static void registerSemanticTap(VoidCallback callback) {
    _currentSemanticTap = callback;
  }

  /// Unregister a button when it loses focus
  static void unregisterSemanticTap(VoidCallback callback) {
    if (_currentSemanticTap == callback) {
      _currentSemanticTap = null;
    }
  }

  /// Invoke the currently registered semantic tap and return whether it was invoked
  /// This mimics the pattern from the working demo
  static bool invokeCurrentSemanticTap() {
    final hasCallback = _currentSemanticTap != null;
    if (hasCallback) {
      _currentSemanticTap!.call();
    }
    return hasCallback;
  }

  /// Clear all registrations (useful for cleanup)
  static void clear() {
    _currentSemanticTap = null;
  }
}
