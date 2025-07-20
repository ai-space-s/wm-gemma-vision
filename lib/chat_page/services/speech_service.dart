// lib/chat_page/services/speech_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../widgets/prompt_bar.dart';
import 'sound_manager.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts;
  final VoidCallback _onStateChanged;
  final GlobalKey<PromptBarState> _promptBarKey;

  bool Function()? _isGeneratingCallback;
  bool _speechEnabled = false;
  bool _listening = false;
  String _dictationText = '';

  SpeechService({
    required FlutterTts tts,
    required VoidCallback onStateChanged,
    required GlobalKey<PromptBarState> promptBarKey,
    required bool Function() isGenerating,
  }) : _tts = tts,
       _onStateChanged = onStateChanged,
       _promptBarKey = promptBarKey;

  // Getters
  bool get speechEnabled => _speechEnabled;
  bool get listening => _listening;

  void updateIsGeneratingCallback(bool Function() callback) {
    _isGeneratingCallback = callback;
  }

  bool _checkIsGenerating() {
    return _isGeneratingCallback?.call() ?? false;
  }

  Future<void> initialize() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          if (_listening && status == 'notListening') {
            _listenAgain();
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');
        },
      );
      _onStateChanged();
    } catch (e) {
      debugPrint('Speech initialization error: $e');
    }
  }

  Future<void> playWooshSound() async {
    await SoundManager.instance.playWoosh();
  }

  Future<void> announceMessageType(bool hasPhoto) async {
    try {
      final message = hasPhoto
          ? "Sending text with photo"
          : "Sending text only";
      await _tts.speak(message);
    } catch (e) {
      debugPrint('Error announcing message type: $e');
    }
  }

  Future<void> startDictation() async {
    if (!_speechEnabled || _checkIsGenerating()) return;

    if (!_listening) {
      _dictationText = '';
      _listening = true;
      _onStateChanged();
    }

    _click();
    _listenAgain();
  }

  Future<void> stopDictation() async {
    if (!_listening) return;
    _click();
    _listening = false;
    await _speech.stop();
    if (_dictationText.trim().isNotEmpty) {
      await _tts.speak(_dictationText.trim());
    }
    _onStateChanged();
  }

  Future<void> toggleDictation() async =>
      _listening ? stopDictation() : startDictation();

  void _listenAgain() {
    _speech.listen(
      onResult: (val) {
        if (!_listening) return;

        final full = (_dictationText + ' ' + val.recognizedWords).trim();
        _promptBarKey.currentState?.updateText(full);

        if (val.finalResult) _dictationText = full;
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 60),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  void _click() => SystemSound.play(SystemSoundType.click);

  KeyEventResult handleFocusKey(FocusNode _, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.f2) {
      if (e is KeyDownEvent) {
        startDictation();
        return KeyEventResult.handled;
      } else if (e is KeyUpEvent) {
        stopDictation();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void dispose() {
    _speech.stop();
    _speech.cancel();
  }
}
