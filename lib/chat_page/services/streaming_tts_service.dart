// lib/chat_page/services/streaming_tts_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'sound_manager.dart';

class StreamingTtsService {
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final FlutterTts _tts;

  bool _isLoading = false;
  String _completeMessage = '';

  StreamingTtsService(this._tts) {
    _configureTts();
  }

  void _configureTts() {
    _tts.setSpeechRate(0.5);
    _tts.setVolume(0.9);
    _tts.setPitch(1.0);
    _tts.awaitSpeakCompletion(true);
  }

  Future<void> startLoading() async {
    if (_isLoading) return;
    _isLoading = true;
    await SoundManager.instance.playLoading();
  }

  Future<void> stopLoading() async {
    if (!_isLoading) return;
    _isLoading = false;
    await SoundManager.instance.stopLoading();
  }

  void addText(String newText, String _) {
    _completeMessage = newText;
  }

  Future<void> onMessageComplete() async {
    await stopLoading();
    await _speakOnce();
  }

  Future<void> _speakOnce() async {
    final text = _cleanMarkdown(_completeMessage);
    if (text.isEmpty) return;

    // Pause loading sound while speaking
    await SoundManager.instance.pauseLoading();
    isSpeaking.value = true;

    try {
      await _tts.speak(text);
      // When speak() completes, TTS is done
      isSpeaking.value = false;
    } catch (e) {
      debugPrint('TTS error: $e');
      isSpeaking.value = false;
    }

    // Resume loading sound if still in loading state
    if (_isLoading && !isSpeaking.value) {
      await SoundManager.instance.resumeLoading();
    }
  }

  String _cleanMarkdown(String text) => text
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
      .replaceAll(RegExp(r'#{1,6}\s+'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'>\s+'), '')
      .replaceAll(RegExp(r'[-*+]\s+'), '')
      .replaceAll(RegExp(r'\d+\.\s+'), '')
      .replaceAll(RegExp(r'---+'), '')
      .replaceAll(RegExp(r'\|[^|]*\|'), '')
      .replaceAll(RegExp(r'\n+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void stop() {
    _tts.stop();
    isSpeaking.value = false;
    _completeMessage = '';
    stopLoading();
  }

  void reset() => stop();

  void dispose() {
    stop();
    isSpeaking.dispose();
  }
}
