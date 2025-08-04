// lib/chat_page/services/speech_service.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../widgets/prompt_bar.dart';
import 'sound_manager.dart';

/// Handles dictation, playback sounds, and accessibility announcements.
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts; // still useful for long‑form playback elsewhere
  final VoidCallback _onStateChanged;
  final GlobalKey<PromptBarState> _promptBarKey;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool Function()? _isGeneratingCallback;
  bool _speechEnabled = false;
  bool _listening = false;
  bool _sendButtonPressed = false;
  bool _isStoppingDictation = false;

  SpeechService({
    required FlutterTts tts,
    required VoidCallback onStateChanged,
    required GlobalKey<PromptBarState> promptBarKey,
    required bool Function() isGenerating,
  }) : _tts = tts,
       _onStateChanged = onStateChanged,
       _promptBarKey = promptBarKey {
    updateIsGeneratingCallback(isGenerating);
  }

  // ───────────────────────────────── Public state ────────────────────────────
  bool get speechEnabled => _speechEnabled;
  bool get listening => _listening;

  // ───────────────────────────────── Internals ──────────────────────────────
  void updateIsGeneratingCallback(bool Function() callback) {
    _isGeneratingCallback = callback;
  }

  bool _checkIsGenerating() => _isGeneratingCallback?.call() ?? false;

  /// One‑time speech‑recognition init.
  Future<void> initialize() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          if (_listening && !_isStoppingDictation && status == 'notListening') {
            _listenAgain();
          }
        },
        onError: (error) => debugPrint('Speech error: $error'),
      );
    } catch (e) {
      debugPrint('Speech initialization error: $e');
    } finally {
      _onStateChanged();
    }
  }

  // ───────────────────────────────── Sounds ─────────────────────────────────
  Future<void> playWooshSound() => SoundManager.instance.playWoosh();

  /// Short announcement describing what will be sent.
  Future<void> announceMessageType(bool hasPhoto) async {
    final msg = hasPhoto ? 'Sending text with photo' : 'Sending text only';
    _announce(msg);
  }

  /// Convenience wrapper for brief notifications.
  Future<void> speak(String message) async => _announce(message.trim());

  void _announce(String message) {
    if (message.isEmpty) return;
    SemanticsService.announce(message, ui.TextDirection.ltr);
  }

  // ───────────────────────────────── Dictation ──────────────────────────────
  Future<void> startDictation() async {
    if (!_speechEnabled || _checkIsGenerating()) return;

    if (!_listening) {
      _listening = true;
      _sendButtonPressed = false;
      _isStoppingDictation = false;
      _onStateChanged();
    }

    await _playDictationStartSound();
    _listenAgain();
  }

  Future<void> stopDictation() async {
    if (!_listening || _isStoppingDictation) return;
    _isStoppingDictation = true;

    try {
      _listening = false;
      await _speech.stop();
      await _playDictationStopSound();

      final currentText = _promptBarKey.currentState?.currentText ?? '';
      if (!_sendButtonPressed && currentText.trim().isNotEmpty) {
        _announce(currentText.trim());
      }
    } finally {
      _sendButtonPressed = false;
      _isStoppingDictation = false;
      _onStateChanged();
    }
  }

  /// Stops any playing TTS that might still be active from other parts of the app.
  Future<void> stopTts() async {
    try {
      if (_listening) _sendButtonPressed = true;
      await _tts.stop();
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
  }

  Future<void> toggleDictation() =>
      _listening ? stopDictation() : startDictation();

  // ───────────────────────────────── Speech‑to‑text engine ──────────────────
  void _listenAgain() {
    if (_isStoppingDictation || !_listening) return;

    _speech.listen(
      onResult: (val) {
        if (!_listening || _isStoppingDictation) return;
        _promptBarKey.currentState?.updateText(val.recognizedWords.trim());
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 60),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  // ───────────────────────────────── Asset sounds ───────────────────────────
  Future<void> _playDictationStartSound() async {
    try {
      await _audioPlayer.play(AssetSource('dictation_start.mp3'));
    } catch (e) {
      debugPrint('Error playing dictation start sound: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _playDictationStopSound() async {
    try {
      await _audioPlayer.play(AssetSource('dictation_stop.mp3'));
    } catch (e) {
      debugPrint('Error playing dictation stop sound: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }

  // ───────────────────────────────── Misc ───────────────────────────────────
  KeyEventResult handleFocusKey(FocusNode _, KeyEvent __) =>
      KeyEventResult.ignored;

  void dispose() {
    _speech.stop();
    _speech.cancel();
    _audioPlayer.dispose();
  }
}
