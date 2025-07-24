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
  bool _sendButtonPressed = false; // Track if send was pressed while listening

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

  /// Initialize speech recognition
  Future<void> initialize() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          // Restart if recognizer auto‑stops while key still held - no delay needed
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

  /// Speak text using TTS (for errors and notifications)
  Future<void> speak(String text) async {
    try {
      if (text.trim().isEmpty) return;

      // Stop any ongoing speech first
      await _tts.stop();

      // Wait a moment to ensure it's stopped
      await Future.delayed(const Duration(milliseconds: 100));

      // Speak the text
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Error speaking text: $e');
      // Don't rethrow - TTS errors shouldn't break the app
    }
  }

  /// Start dictation
  Future<void> startDictation() async {
    if (!_speechEnabled || _checkIsGenerating()) return;

    if (!_listening) {
      _dictationText = ''; // new session
      _listening = true;
      _sendButtonPressed = false; // Reset send button flag
      _onStateChanged();
    }

    _click();
    _listenAgain();
  }

  /// Stop dictation
  Future<void> stopDictation() async {
    if (!_listening) return;
    _click();
    _listening = false;
    await _speech.stop();

    // Always read back if there's text and send button wasn't pressed
    if (!_sendButtonPressed && _dictationText.trim().isNotEmpty) {
      await _tts.speak(_dictationText.trim());
    }

    // Reset flag for next session
    _sendButtonPressed = false;
    _onStateChanged();
  }

  /// Stop any ongoing TTS speech (used when send buttons are pressed)
  Future<void> stopTts() async {
    try {
      // Mark that send button was pressed while listening
      if (_listening) {
        _sendButtonPressed = true;
      }

      await _tts.stop();
      // Wait a moment to ensure it's actually stopped
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
  }

  /// Toggle dictation on/off
  Future<void> toggleDictation() async =>
      _listening ? stopDictation() : startDictation();

  /// Start listening again (internal) - using your original approach
  void _listenAgain() {
    _speech.listen(
      onResult: (val) {
        if (!_listening) return;

        final full = (_dictationText + ' ' + val.recognizedWords).trim();
        _promptBarKey.currentState?.updateText(full);

        if (val.finalResult) _dictationText = full;
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(
        seconds: 60,
      ), // Your original setting - this handles pauses well
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  /// Play click sound
  void _click() => SystemSound.play(SystemSoundType.click);

  /// Handle F2 key events for push-to-talk
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

  /// Dispose resources
  void dispose() {
    _speech.stop();
    _speech.cancel();
  }
}
