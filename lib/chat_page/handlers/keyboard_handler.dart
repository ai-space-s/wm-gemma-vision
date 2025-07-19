// lib/chat_page/handlers/keyboard_handler.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/prompt_bar.dart';

/// Intent so controller keys win even when a TextField has focus.
class GameIntent extends Intent {
  const GameIntent(this.key);
  final LogicalKeyboardKey key;
}

/// Handles all keyboard shortcuts and actions
class KeyboardHandler {
  final BuildContext _context;
  final GlobalKey<PromptBarState> _promptBarKey;
  final VoidCallback _onToggleMessages;
  final VoidCallback _onToggleCamera;
  final VoidCallback _onToggleSettings;
  final VoidCallback _onNewChat;
  final VoidCallback _onQuickAction1;
  final VoidCallback _onQuickAction2;
  final VoidCallback _onQuickAction3;
  final VoidCallback _onQuickAction4;

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
  }) : _context = context,
       _promptBarKey = promptBarKey,
       _onToggleMessages = onToggleMessages,
       _onToggleCamera = onToggleCamera,
       _onToggleSettings = onToggleSettings,
       _onNewChat = onNewChat,
       _onQuickAction1 = onQuickAction1,
       _onQuickAction2 = onQuickAction2,
       _onQuickAction3 = onQuickAction3,
       _onQuickAction4 = onQuickAction4;

  /// Handle keyboard shortcuts
  void onShortcut(LogicalKeyboardKey key) {
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
        Actions.invoke(_context, const ActivateIntent());
        break;
    }
  }

  /// Get keyboard shortcuts map
  Map<LogicalKeySet, Intent> get shortcuts => {
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
    // F2 handled via press‑and‑hold listener in SpeechService
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
    LogicalKeySet(LogicalKeyboardKey.arrowUp): const GameIntent(
      LogicalKeyboardKey.arrowUp,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowDown): const GameIntent(
      LogicalKeyboardKey.arrowDown,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowLeft): const GameIntent(
      LogicalKeyboardKey.arrowLeft,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowRight): const GameIntent(
      LogicalKeyboardKey.arrowRight,
    ),
    LogicalKeySet(LogicalKeyboardKey.enter): const GameIntent(
      LogicalKeyboardKey.enter,
    ),
    LogicalKeySet(LogicalKeyboardKey.select): const GameIntent(
      LogicalKeyboardKey.select,
    ),
  };

  /// Get keyboard actions map
  Map<Type, Action<Intent>> get actions => {
    GameIntent: CallbackAction<GameIntent>(
      onInvoke: (intent) => onShortcut(intent.key),
    ),
  };
}

/// Keyboard shortcuts reference for users
class KeyboardShortcuts {
  static const Map<String, String> shortcuts = {
    'F1': 'Send message with photo',
    'F2': 'Push-to-talk (hold)',
    'F3': 'New chat',
    'F4': 'Quick action: Find exit',
    'F5': 'Quick action: Describe room',
    'F6': 'Quick action: Read text',
    'F7': 'Quick action: Tell me what you see',
    'F8': 'Toggle settings',
    'F9': 'Send text-only message',
    'F10': 'Toggle message visibility',
    'Arrow Keys': 'Navigate focus',
    'Enter/Select': 'Activate focused element',
  };

  static Widget buildHelpDialog(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: shortcuts.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
