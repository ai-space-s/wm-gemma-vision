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
  bool _hasFirstSentence =
      false; // Track if we have at least one complete sentence

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
    // ── 1. Discard tokens that are *only* a period ──────────── ★
    if (newToken.trim() == '.') return;

    _buffer = currentFullText;
    _tokensSinceLastSpeak++;

    // Check if we now have at least one complete sentence
    if (!_hasFirstSentence) {
      final cleanText = _cleanMarkdownForTts(_buffer);
      _hasFirstSentence = RegExp(r'[.!?]+\s+').hasMatch(cleanText);
    }

    // Debounce with longer delay to avoid premature speaking
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 300), _processBuffer);

    // Only use fallback if we have a complete sentence OR message is getting very long
    if (_hasFirstSentence &&
        (_tokensSinceLastSpeak >= 8 || _getUnspokenText().length > 40) &&
        !_isProcessing &&
        !isSpeaking.value) {
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(milliseconds: 400), _forceSpeak);
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

    // Give a moment for any ongoing speech to complete before final speech
    await Future.delayed(const Duration(milliseconds: 100));
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
    } else if (_hasFirstSentence && newContent.length > 25) {
      // Only force speak if we have at least one sentence and accumulated enough text
      _forceSpeak();
    }
  }

  void _forceSpeak() {
    if (_buffer.isEmpty || _isProcessing) return;

    final unspoken = _getUnspokenText();
    // Increase minimum threshold and require first sentence
    if (_hasFirstSentence && unspoken.isNotEmpty && unspoken.length > 5) {
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

      // ── 2. Skip duplicates and pure punctuation ──────────── ★
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

    // Fixed: Check if we need to continue speaking
    if (_pendingSegments.isEmpty) {
      if (_messageComplete) {
        // Message is complete, speak any remaining text
        await _speakRemainingText();
      } else if (_buffer.isEmpty) {
        // No more content, stop speaking
        isSpeaking.value = false;
        if (_isLoading) {
          await SoundManager.instance.resumeLoading();
        }
      } else if (_isLoading) {
        // Still generating, pause speaking but keep loading sound
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
      // If it's a very short response (less than a sentence), speak it anyway
      final cleanBuffer = _cleanMarkdownForTts(_buffer);
      final isShortResponse =
          cleanBuffer.length < 50 &&
          !RegExp(r'[.!?]+\s+').hasMatch(cleanBuffer);

      if (isShortResponse || _hasFirstSentence) {
        _pendingSegments.add(unspoken);
        _lastSpokenLength = _cleanMarkdownForTts(_buffer).length;
        if (!_isProcessing) await _processNextSegment();
      } else {
        isSpeaking.value = false;
      }
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

    // Only use clause-level breaks if we already have a complete sentence
    if (_hasFirstSentence && text.length > 15) {
      final breakRx = RegExp(
        r'[,;:]\s+|\s+(?:and|but|or|however|therefore|meanwhile|also|then|next|first|second|finally)\s+',
      );
      last = 0;
      for (final m in breakRx.allMatches(text)) {
        final chunk = text.substring(last, m.end).trim();
        if (chunk.length > 8) out.add(chunk);
        last = m.end;
      }
    }

    // Word-count fallback - only if we have first sentence and sufficient content
    if (out.isEmpty && _hasFirstSentence && text.length > 35) {
      final words = text.split(' ');
      var buf = '';
      for (final w in words) {
        if ((buf + ' ' + w).trim().length <= 40) {
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
    _hasFirstSentence = false; // Reset first sentence tracking
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
