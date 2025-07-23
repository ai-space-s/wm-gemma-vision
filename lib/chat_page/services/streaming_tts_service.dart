// lib/chat_page/services/streaming_tts_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'sound_manager.dart';

/// Streaming TTS Service for reading AI responses as they're generated.
class StreamingTtsService {
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final FlutterTts _tts;
  final List<String> _pendingSegments = [];
  bool _isLoading = false;
  String _buffer = '';
  int _lastSpokenLength = 0; // position in the *cleaned* text
  Timer? _bufferTimer;
  Timer? _fallbackTimer;
  bool _messageComplete = false;
  int _tokensSinceLastSpeak = 0;
  bool _isProcessing = false;
  String _previousSegment = ''; // ── duplicate filter ★

  StreamingTtsService(this._tts) {
    _configureTts();
  }

  void _configureTts() {
    _tts.setSpeechRate(0.5);
    _tts.setVolume(0.9);
    _tts.setPitch(1.0);
    _tts.awaitSpeakCompletion(true);
  }

  // ───────────────────────────────────────────────────────────
  // PUBLIC API
  // ───────────────────────────────────────────────────────────
  Future<void> startLoading() async {
    if (_isLoading) return;
    _isLoading = true;
    _resetState();
    await SoundManager.instance.playLoading();
  }

  Future<void> stopLoading() async {
    if (!_isLoading) return;
    _isLoading = false;
    await SoundManager.instance.stopLoading();
  }

  /// Consume one streaming token.
  void addText(String newToken, String currentFullText) {
    // ── 1. Discard tokens that are *only* a period ──────────── ★
    if (newToken.trim() == '.') return;

    _buffer = currentFullText;
    _tokensSinceLastSpeak++;

    // Debounce
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 150), _processBuffer);

    // Fallback if we haven't spoken for a while
    if ((_tokensSinceLastSpeak >= 5 || _getUnspokenText().length > 15) &&
        !_isProcessing &&
        !isSpeaking.value) {
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(milliseconds: 200), _forceSpeak);
    }
  }

  Future<void> onMessageComplete() async {
    _messageComplete = true;
    await stopLoading();
    _bufferTimer?.cancel();
    _fallbackTimer?.cancel();

    // Ensure the final text ends with punctuation for natural cadence ★
    if (_buffer.trim().isNotEmpty && !RegExp(r'[.!?]\s*$').hasMatch(_buffer)) {
      _buffer += '.';
    }

    await _speakRemainingText();
  }

  void stop() => _hardReset();
  void reset() => _hardReset();
  void dispose() {
    _hardReset();
    isSpeaking.dispose();
  }

  // ───────────────────────────────────────────────────────────
  // INTERNAL – BUFFER HANDLING
  // ───────────────────────────────────────────────────────────
  void _processBuffer() {
    if (_buffer.isEmpty || _isProcessing) return;

    final cleanText = _cleanMarkdownForTts(_buffer);
    if (cleanText.length <= _lastSpokenLength) return;

    final newContent = cleanText.substring(_lastSpokenLength);
    if (newContent.trim().isEmpty) return;

    final sentences = _findCompleteSentences(newContent);

    if (sentences.isNotEmpty) {
      final slice = sentences.join(' ');
      _pendingSegments.addAll(sentences);
      _lastSpokenLength += slice.length;
      _tokensSinceLastSpeak = 0;

      if (!_isProcessing) _processNextSegment();
    } else if (newContent.length > 10) {
      _forceSpeak();
    }
  }

  void _forceSpeak() {
    if (_buffer.isEmpty || _isProcessing) return;

    final unspoken = _getUnspokenText();
    if (unspoken.isNotEmpty && unspoken.length > 2) {
      _pendingSegments.add(unspoken);
      _lastSpokenLength = _cleanMarkdownForTts(_buffer).length;
      _tokensSinceLastSpeak = 0;
      if (!_isProcessing) _processNextSegment();
    }
  }

  Future<void> _processNextSegment() async {
    if (_isProcessing) return;

    while (_pendingSegments.isNotEmpty) {
      _isProcessing = true;

      if (!isSpeaking.value) {
        if (_isLoading) await SoundManager.instance.pauseLoading();
        isSpeaking.value = true;
      }

      final segment = _pendingSegments.removeAt(0).trim();

      // ── 2. Skip duplicates and pure punctuation ──────────── ★
      if (segment.isEmpty ||
          segment == _previousSegment ||
          RegExp(r'^[.!?,;:]+$').hasMatch(segment)) {
        continue;
      }

      try {
        await _tts.speak(segment);
        _previousSegment = segment; // remember last spoken ★
      } catch (e) {
        print('TTS error: $e');
        break;
      }
    }

    _isProcessing = false;

    if (_pendingSegments.isEmpty) {
      if (_messageComplete || _buffer.isEmpty) {
        isSpeaking.value = false;
        if (_messageComplete) await _speakRemainingText();
      } else if (_isLoading) {
        isSpeaking.value = false;
        await SoundManager.instance.resumeLoading();
      }
    }
  }

  Future<void> _speakRemainingText() async {
    if (_buffer.isEmpty) {
      isSpeaking.value = false;
      return;
    }
    final unspoken = _getUnspokenText();
    if (unspoken.isNotEmpty &&
        !RegExp(r'^[.!?,;:]+$').hasMatch(unspoken.trim())) {
      _pendingSegments.add(unspoken);
      _lastSpokenLength = _cleanMarkdownForTts(_buffer).length;
      if (!_isProcessing) await _processNextSegment();
    } else {
      isSpeaking.value = false;
    }
  }

  // ───────────────────────────────────────────────────────────
  // TEXT HELPERS
  // ───────────────────────────────────────────────────────────
  String _getUnspokenText() {
    final cleaned = _cleanMarkdownForTts(_buffer);
    if (cleaned.length <= _lastSpokenLength) return '';
    return cleaned.substring(_lastSpokenLength).trim();
  }

  List<String> _findCompleteSentences(String text) {
    final out = <String>[];
    final endRx = RegExp(r'[.!?]+(?:\s+|$)');
    int last = 0;
    for (final m in endRx.allMatches(text)) {
      final chunk = text.substring(last, m.end).trim();
      if (chunk.length > 2) out.add(chunk);
      last = m.end;
    }
    if (out.isNotEmpty) return out;

    // Clause‑level breaks
    if (text.length > 10) {
      final breakRx = RegExp(
        r'[,;:]\s+|\s+(?:and|but|or|however|therefore|meanwhile|also|then|next|first|second|finally)\s+',
      );
      last = 0;
      for (final m in breakRx.allMatches(text)) {
        final chunk = text.substring(last, m.end).trim();
        if (chunk.length > 5) out.add(chunk);
        last = m.end;
      }
    }

    // Word-count fallback
    if (out.isEmpty && text.length > 20) {
      final words = text.split(' ');
      var buf = '';
      for (final w in words) {
        if ((buf + ' ' + w).trim().length <= 30) {
          buf = [buf, w].where((s) => s.isNotEmpty).join(' ');
        } else {
          if (buf.isNotEmpty) out.add(buf);
          buf = w;
        }
      }
      if (buf.isNotEmpty) out.add(buf);
    }

    return out;
  }

  // Remove markdown & tame punctuation
  String _cleanMarkdownForTts(String text) {
    String t = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'#{1,6}\s+'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'>\s+'), '')
        .replaceAll(RegExp(r'[-*+]\s+'), '')
        .replaceAll(RegExp(r'\d+\.\s+'), '')
        .replaceAll(RegExp(r'---+'), '')
        .replaceAll(RegExp(r'\|[^|]*\|'), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    // punctuation normalisation
    t = t.replaceAll(RegExp(r'(^|\s)[.!?](?=\s|$)'), ' ');
    t = t.replaceAll(RegExp(r'\s+(?=[.!?,;:])'), '');
    t = t.replaceAll(RegExp(r'\.{2,}'), '');
    t = t.replaceAll(RegExp(r'[.!?]{2,}'), '.');
    t = t.replaceAll(RegExp(r'[,;:]{2,}'), ',');
    return t.trim();
  }

  // ───────────────────────────────────────────────────────────
  // BOOKKEEPING & CLEANUP
  // ───────────────────────────────────────────────────────────
  void _resetState() {
    _messageComplete = false;
    _buffer = '';
    _lastSpokenLength = 0;
    _tokensSinceLastSpeak = 0;
    _pendingSegments.clear();
    _isProcessing = false;
    _previousSegment = '';
    isSpeaking.value = false;
  }

  void _hardReset() {
    _bufferTimer?.cancel();
    _fallbackTimer?.cancel();
    _tts.stop();
    _resetState();
    stopLoading();
  }
}
