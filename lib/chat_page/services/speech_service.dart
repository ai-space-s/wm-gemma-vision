// lib/chat_page/services/speech_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../widgets/prompt_bar.dart';
import 'sound_manager.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts;
  final VoidCallback _onStateChanged;
  final GlobalKey<PromptBarState> _promptBarKey;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool Function()? _isGeneratingCallback;
  bool _speechEnabled = false;
  bool _listening = false;
  bool _sendButtonPressed = false;
  bool _isStoppingDictation = false; // ✅ Prevent multiple stops

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
          // ✅ Only restart if we're actively listening and not in the process of stopping
          if (_listening && !_isStoppingDictation && status == 'notListening') {
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
    }
  }

  /// Start dictation
  Future<void> startDictation() async {
    if (!_speechEnabled || _checkIsGenerating()) return;

    if (!_listening) {
      _listening = true;
      _sendButtonPressed = false;
      _isStoppingDictation = false; // ✅ Reset stopping flag
      _onStateChanged();
    }

    await _playDictationStartSound();
    _listenAgain();
  }

  /// Stop dictation
  Future<void> stopDictation() async {
    // ✅ Prevent multiple simultaneous stops
    if (!_listening || _isStoppingDictation) return;

    _isStoppingDictation = true;

    try {
      _listening = false;
      await _speech.stop();

      // ✅ Play stop sound first
      await _playDictationStopSound();

      // ✅ Wait for the sound to finish before TTS (dictation sounds are usually ~500ms)
      // await Future.delayed(const Duration(milliseconds: 600));

      // Get the current text from the prompt bar (more reliable than _dictationText)
      final currentText = _promptBarKey.currentState?.currentText ?? '';

      // Only read back if there's text and send button wasn't pressed
      if (!_sendButtonPressed && currentText.trim().isNotEmpty) {
        await _tts.speak(currentText.trim());
      }
    } finally {
      // ✅ Always reset flags
      _sendButtonPressed = false;
      _isStoppingDictation = false;
      _onStateChanged();
    }
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

  /// Start listening again (internal)
  void _listenAgain() {
    if (_isStoppingDictation || !_listening) return;

    _speech.listen(
      onResult: (val) {
        if (!_listening || _isStoppingDictation) return;

        final transcript = val.recognizedWords.trim(); // <- use as‑is
        _promptBarKey.currentState?.updateText(transcript);
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 60),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  /// Play dictation start sound
  Future<void> _playDictationStartSound() async {
    try {
      await _audioPlayer.play(AssetSource('dictation_start.mp3'));
    } catch (e) {
      debugPrint('Error playing dictation start sound: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Play dictation stop sound
  Future<void> _playDictationStopSound() async {
    try {
      await _audioPlayer.play(AssetSource('dictation_stop.mp3'));
    } catch (e) {
      debugPrint('Error playing dictation stop sound: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Handle key events
  KeyEventResult handleFocusKey(FocusNode _, KeyEvent e) {
    return KeyEventResult.ignored;
  }

  /// Dispose resources
  void dispose() {
    _speech.stop();
    _speech.cancel();
    _audioPlayer.dispose();
  }
}
