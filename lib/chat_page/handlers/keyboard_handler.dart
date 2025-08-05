// lib/chat_page/handlers/keyboard_handler.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../widgets/prompt_bar.dart';
import '../widgets/semantic_button_registry.dart';

/// Intent so controller keys win even when a TextField has focus.
class GameIntent extends Intent {
  const GameIntent(this.key);
  final LogicalKeyboardKey key;
}

/// Handles all keyboard shortcuts and actions with cross-platform support
/// Based on working cross-platform demo pattern
class KeyboardHandler {
  final BuildContext _context;
  final GlobalKey<PromptBarState> _promptBarKey;
  final VoidCallback _onToggleMessages;
  final VoidCallback _onToggleSettings;
  final VoidCallback _onNewChat;
  final VoidCallback _onQuickAction1;
  final VoidCallback _onQuickAction2;
  final VoidCallback _onQuickAction3;
  final VoidCallback _onQuickAction4;
  final VoidCallback _onToggleVoice;

  // Track key state to prevent duplicate events
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};

  // Platform detection
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  KeyboardHandler({
    required BuildContext context,
    required GlobalKey<PromptBarState> promptBarKey,
    required VoidCallback onToggleMessages,
    required VoidCallback onToggleCamera,
    required VoidCallback onToggleSettings,
    required VoidCallback onNewChat,
    required VoidCallback onQuickAction1,
    required VoidCallback onQuickAction2,
    required VoidCallback onQuickAction3,
    required VoidCallback onQuickAction4,
    required VoidCallback onToggleVoice,
  }) : _context = context,
       _promptBarKey = promptBarKey,
       _onToggleMessages = onToggleMessages,
       _onToggleSettings = onToggleSettings,
       _onNewChat = onNewChat,
       _onQuickAction1 = onQuickAction1,
       _onQuickAction2 = onQuickAction2,
       _onQuickAction3 = onQuickAction3,
       _onQuickAction4 = onQuickAction4,
       _onToggleVoice = onToggleVoice;

  /// Handle keyboard shortcuts with state validation
  void onShortcut(LogicalKeyboardKey key) {
    // Check if the key is actually pressed to prevent ghost events
    if (!HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
      debugPrint('KeyboardHandler: Ignoring ghost key event for $key');
      return;
    }

    // Prevent duplicate key handling
    if (_pressedKeys.contains(key)) {
      debugPrint('KeyboardHandler: Key $key already being processed');
      return;
    }

    _pressedKeys.add(key);

    try {
      switch (key) {
        case LogicalKeyboardKey.f10:
          _onToggleMessages();
          break;
        case LogicalKeyboardKey.f9:
          _promptBarKey.currentState?.sendTextOnly();
          break;
        case LogicalKeyboardKey.f8:
          _onToggleSettings();
          break;
        case LogicalKeyboardKey.f1:
          _promptBarKey.currentState?.sendWithPhoto();
          break;
        case LogicalKeyboardKey.f2:
          _onToggleVoice();
          break;
        case LogicalKeyboardKey.f3:
          _onNewChat();
          break;
        case LogicalKeyboardKey.f5:
          _onQuickAction1();
          break;
        case LogicalKeyboardKey.f7:
          _onQuickAction2();
          break;
        case LogicalKeyboardKey.f4:
          _onQuickAction3();
          break;
        case LogicalKeyboardKey.f6:
          _onQuickAction4();
          break;
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.arrowLeft:
          FocusScope.of(_context).previousFocus();
          break;
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.arrowRight:
          FocusScope.of(_context).nextFocus();
          break;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.space:
          // ✅ MATCHING WORKING DEMO: Handle activation with platform awareness
          if (_shouldActivateButton()) {
            _activateCurrentButton();
          }
          break;
      }
    } finally {
      // Remove key from pressed set after a short delay to prevent rapid re-triggering
      Future.delayed(const Duration(milliseconds: 100), () {
        _pressedKeys.remove(key);
      });
    }
  }

  /// ✅ MATCHING WORKING DEMO: Platform-specific activation logic
  bool _shouldActivateButton() {
    // For iOS VoiceOver: Ctrl + Alt + Space
    // For Android TalkBack: Enter, Space, or Select
    // For regular use: Enter, Space, or Select

    if (_isIOS) {
      return HardwareKeyboard.instance.isControlPressed &&
          HardwareKeyboard.instance.isAltPressed;
    } else {
      return true; // Android and other platforms
    }
  }

  void _activateCurrentButton() {
    SemanticButtonRegistry.invokeCurrentSemanticTap();
  }

  /// Enhanced action handler that validates key events
  CallbackAction<GameIntent> _createGameAction() {
    return CallbackAction<GameIntent>(
      onInvoke: (intent) {
        try {
          // Additional validation for the intent key
          final key = intent.key;

          // Check if this is a valid key press event
          if (!HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
            debugPrint('GameIntent: Ignoring invalid key event for $key');
            return null;
          }

          onShortcut(key);
          return null;
        } catch (e) {
          debugPrint('GameIntent error: $e');
          return null;
        }
      },
    );
  }

  /// Get keyboard shortcuts map with cross-platform support
  Map<LogicalKeySet, Intent> get shortcuts => {
    if (_isIOS) ...{
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
      LogicalKeySet(
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.space,
      ): const ActivateIntent(),
    } else ...{
      // Android: Standard focus intents
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
    },

    // Function key shortcuts (platform-agnostic)
    LogicalKeySet(LogicalKeyboardKey.f9): const GameIntent(
      LogicalKeyboardKey.f9,
    ),
    LogicalKeySet(LogicalKeyboardKey.f10): const GameIntent(
      LogicalKeyboardKey.f10,
    ),
    LogicalKeySet(LogicalKeyboardKey.f8): const GameIntent(
      LogicalKeyboardKey.f8,
    ),
    LogicalKeySet(LogicalKeyboardKey.f1): const GameIntent(
      LogicalKeyboardKey.f1,
    ),
    LogicalKeySet(LogicalKeyboardKey.f2): const GameIntent(
      LogicalKeyboardKey.f2,
    ),
    LogicalKeySet(LogicalKeyboardKey.f5): const GameIntent(
      LogicalKeyboardKey.f5,
    ),
    LogicalKeySet(LogicalKeyboardKey.f7): const GameIntent(
      LogicalKeyboardKey.f7,
    ),
    LogicalKeySet(LogicalKeyboardKey.f4): const GameIntent(
      LogicalKeyboardKey.f4,
    ),
    LogicalKeySet(LogicalKeyboardKey.f6): const GameIntent(
      LogicalKeyboardKey.f6,
    ),
    LogicalKeySet(LogicalKeyboardKey.f3): const GameIntent(
      LogicalKeyboardKey.f3,
    ),
  };

  /// Get keyboard actions map with platform-specific ActivateIntent handler
  Map<Type, Action<Intent>> get actions => {
    // ✅ MATCHING WORKING DEMO: iOS-specific ActivateIntent handler
    if (_isIOS)
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          try {
            SemanticButtonRegistry.invokeCurrentSemanticTap();
          } catch (e) {
            debugPrint('ActivateIntent error: $e');
          }
          return null;
        },
      )
    else
      // Android: Let the system handle ActivateIntent naturally
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          try {
            // For Android, the semantic onTap should handle this naturally
            // But we can also use the registry as fallback
            final activated = SemanticButtonRegistry.invokeCurrentSemanticTap();
            if (!activated) {
              debugPrint('No semantic tap registered, letting system handle');
            }
          } catch (e) {
            debugPrint('ActivateIntent error: $e');
          }
          return null;
        },
      ),

    GameIntent: _createGameAction(),
  };

  /// Clean up resources
  void dispose() {
    _pressedKeys.clear();
  }
}
