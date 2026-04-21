// lib/chat_page/widgets/semantic_button_registry.dart
import 'package:flutter/foundation.dart';

/// Global registry for managing iOS VoiceOver button activation
/// Handles the pattern where iOS VoiceOver focuses a button but activation comes through keyboard shortcuts
class SemanticButtonRegistry {
  /// Currently focused button's callback - only one button can be "current" at a time
  static VoidCallback? currentSemanticTap;

  /// Check if there's a currently registered semantic tap target
  static bool get hasSemanticTap => currentSemanticTap != null;

  /// Register a button as the current semantic target (when it gains accessibility focus)
  static void registerSemanticTap(VoidCallback callback) {
    currentSemanticTap = callback;
  }

  /// Unregister a specific button when it loses focus (safety check)
  static void unregisterSemanticTap(VoidCallback callback) {
    if (currentSemanticTap == callback) {
      currentSemanticTap = null;
    }
  }

  /// Invoke the currently registered semantic tap and return success status
  static bool invokeCurrentSemanticTap() {
    final hasCallback = currentSemanticTap != null;
    if (hasCallback) {
      currentSemanticTap!.call();
    }
    return hasCallback;
  }

  /// Clear all registrations (called during cleanup or app state reset)
  static void clear() {
    currentSemanticTap = null;
  }
}
