// lib/chat_page/handlers/keyboard_handler.dart
import 'package:flutter/foundation.dart'; // [수정] kIsWeb 사용을 위해 Foundation 임포트
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/prompt_bar.dart';
import '../widgets/semantic_button_registry.dart';

class GameIntent extends Intent {
  const GameIntent(this.key);
  final LogicalKeyboardKey key;
}

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
  final VoidCallback _onConnectionTest;

  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  bool _globalHandlerAttached = false;

  // [수정] Web 호환성을 위해 Platform.isIOS 대신 defaultTargetPlatform 사용 권장
  // 하지만 여기서는 기존 로직 유지하되, kIsWeb 체크가 이미 있으므로 안전함.
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  KeyboardHandler({
    required BuildContext context,
    required GlobalKey<PromptBarState> promptBarKey,
    required VoidCallback onToggleMessages,
    required VoidCallback onToggleCamera, // Note: 사용되지 않지만 인터페이스 유지를 위해 남겨둠
    required VoidCallback onToggleSettings,
    required VoidCallback onNewChat,
    required VoidCallback onQuickAction1,
    required VoidCallback onQuickAction2,
    required VoidCallback onQuickAction3,
    required VoidCallback onQuickAction4,
    required VoidCallback onToggleVoice,
    required VoidCallback onConnectionTest,
  })  : _context = context,
        _promptBarKey = promptBarKey,
        _onToggleMessages = onToggleMessages,
        _onToggleSettings = onToggleSettings,
        _onNewChat = onNewChat,
        _onQuickAction1 = onQuickAction1,
        _onQuickAction2 = onQuickAction2,
        _onQuickAction3 = onQuickAction3,
        _onQuickAction4 = onQuickAction4,
        _onToggleVoice = onToggleVoice,
        _onConnectionTest = onConnectionTest;

  void onShortcut(
    LogicalKeyboardKey key, {
    bool requirePressedState = true,
  }) {
    if (requirePressedState &&
        !HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
      return;
    }

    if (_pressedKeys.contains(key)) {
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
        // [수정] 기존 sendWithPhoto() -> sendWithCamera()로 변경
          _promptBarKey.currentState?.sendWithCamera();
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

        case LogicalKeyboardKey.f11:
          _onConnectionTest();
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
          if (_shouldActivateButton()) {
            _activateCurrentButton();
          }
          break;
        default:
          break;
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        _pressedKeys.remove(key);
      });
    }
  }

  void attachGlobalHandler() {
    if (_globalHandlerAttached) {
      return;
    }

    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _globalHandlerAttached = true;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!_isCurrentRouteActive()) {
      return false;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    final key = event.logicalKey;
    if (!_isControllerShortcut(key)) {
      return false;
    }

    onShortcut(key, requirePressedState: false);
    return true;
  }

  bool _isCurrentRouteActive() {
    final route = ModalRoute.of(_context);
    return route == null || route.isCurrent;
  }

  bool _isControllerShortcut(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.f1:
      case LogicalKeyboardKey.f2:
      case LogicalKeyboardKey.f3:
      case LogicalKeyboardKey.f4:
      case LogicalKeyboardKey.f5:
      case LogicalKeyboardKey.f6:
      case LogicalKeyboardKey.f7:
      case LogicalKeyboardKey.f8:
      case LogicalKeyboardKey.f9:
      case LogicalKeyboardKey.f10:
      case LogicalKeyboardKey.f11:
        return true;
      default:
        return false;
    }
  }

  bool _shouldActivateButton() {
    if (_isIOS) {
      return HardwareKeyboard.instance.isControlPressed &&
          HardwareKeyboard.instance.isAltPressed;
    } else {
      return true;
    }
  }

  void _activateCurrentButton() {
    SemanticButtonRegistry.invokeCurrentSemanticTap();
  }

  CallbackAction<GameIntent> _createGameAction() {
    return CallbackAction<GameIntent>(
      onInvoke: (intent) {
        try {
          final key = intent.key;
          if (!HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
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

  Map<LogicalKeySet, Intent> get shortcuts => {
    if (_isIOS) ...{
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp):
      const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft):
      const PreviousFocusIntent(),
      LogicalKeySet(
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.space,
      ): const ActivateIntent(),
    } else ...{
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp):
      const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft):
      const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
    },

    LogicalKeySet(LogicalKeyboardKey.f9):
    const GameIntent(LogicalKeyboardKey.f9),
    LogicalKeySet(LogicalKeyboardKey.f10):
    const GameIntent(LogicalKeyboardKey.f10),
    LogicalKeySet(LogicalKeyboardKey.f8):
    const GameIntent(LogicalKeyboardKey.f8),
    LogicalKeySet(LogicalKeyboardKey.f1):
    const GameIntent(LogicalKeyboardKey.f1),
    LogicalKeySet(LogicalKeyboardKey.f2):
    const GameIntent(LogicalKeyboardKey.f2),
    LogicalKeySet(LogicalKeyboardKey.f5):
    const GameIntent(LogicalKeyboardKey.f5),
    LogicalKeySet(LogicalKeyboardKey.f7):
    const GameIntent(LogicalKeyboardKey.f7),
    LogicalKeySet(LogicalKeyboardKey.f4):
    const GameIntent(LogicalKeyboardKey.f4),
    LogicalKeySet(LogicalKeyboardKey.f6):
    const GameIntent(LogicalKeyboardKey.f6),
    LogicalKeySet(LogicalKeyboardKey.f3):
    const GameIntent(LogicalKeyboardKey.f3),
    LogicalKeySet(LogicalKeyboardKey.f11):
    const GameIntent(LogicalKeyboardKey.f11),
  };

  Map<Type, Action<Intent>> get actions => {
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
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          try {
            final activated =
            SemanticButtonRegistry.invokeCurrentSemanticTap();
            if (!activated) {
              debugPrint('No semantic tap registered');
            }
          } catch (e) {
            debugPrint('ActivateIntent error: $e');
          }
          return null;
        },
      ),
    GameIntent: _createGameAction(),
  };

  void dispose() {
    if (_globalHandlerAttached) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
      _globalHandlerAttached = false;
    }
    _pressedKeys.clear();
  }
}
