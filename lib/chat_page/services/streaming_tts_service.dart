// lib/chat_page/services/streaming_tts_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:remove_markdown/remove_markdown.dart';
import 'sound_manager.dart';

/// Streaming TTS Service for reading AI responses as they're generated.
class StreamingTtsService {
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final FlutterTts _tts;

  // Buffers & state
  final List<String> _pendingSegments = [];
  String _buffer = '';
  String _previousSegment = '';

  // Timers
  Timer? _bufferTimer;
  Timer? _fallbackTimer;

  // Counters & flags
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _messageComplete = false;
  int _lastSpokenLength = 0; // position in the *cleaned* text
  int _tokensSinceLastSpeak = 0;

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
  // PUBLIC API
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
  /// Starts speaking as soon as a **complete sentence** is available.
  void addText(String newToken, String currentFullText) {
    _buffer = currentFullText;
    _tokensSinceLastSpeak++;

    // 1️⃣  If the token itself contains sentence‑ending punctuation,
    //     try to process the buffer *right now*.
    if (RegExp(r'[.!?]').hasMatch(newToken)) {
      _processBuffer();
    }

    // 2️⃣  Make sure _processBuffer() runs at least every 150 ms while streaming.
    _bufferTimer ??= Timer(const Duration(milliseconds: 150), () {
      _bufferTimer = null; // allow the next schedule
      _processBuffer();
    });

    // 3️⃣  Fallback: if nothing was spoken for a while, force partial output.
    if (_tokensSinceLastSpeak >= 6 || _getUnspokenText().length > 30) {
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(milliseconds: 200), _forceSpeak);
    }
  }

  Future<void> onMessageComplete() async {
    _messageComplete = true;
    await stopLoading();
    _bufferTimer?.cancel();
    _fallbackTimer?.cancel();

    // Ensure natural ending punctuation.
    if (_buffer.trim().isNotEmpty && !RegExp(r'[.!?]\s*$').hasMatch(_buffer)) {
      _buffer += '.';
    }

    await _forceCompleteReading();
  }

  void stop() => _hardReset();
  void reset() => _hardReset();
  void dispose() {
    _hardReset();
    isSpeaking.dispose();
  }

  // ───────────────────────────────────────────────────────────
  // BUFFER HANDLING
  // ───────────────────────────────────────────────────────────
  void _processBuffer() {
    if (_buffer.isEmpty || _isProcessing) return;

    final cleanText = _cleanTextForTts(_buffer);
    if (cleanText.length <= _lastSpokenLength) return;

    final newContent = cleanText.substring(_lastSpokenLength);
    if (newContent.trim().isEmpty) return;

    // Detect complete sentences.
    final sentences = _findCompleteSentences(newContent);

    if (sentences.isNotEmpty) {
      final slice = sentences.join(' ');
      _pendingSegments.addAll(sentences);
      _lastSpokenLength += slice.length;
      _tokensSinceLastSpeak = 0;
      if (!_isProcessing) _processNextSegment();
    }
  }

  void _forceSpeak() {
    if (_buffer.isEmpty || _isProcessing) return;

    final unspoken = _getUnspokenText();
    if (unspoken.isNotEmpty && unspoken.length > 5) {
      _pendingSegments.add(unspoken);
      _lastSpokenLength = _cleanTextForTts(_buffer).length;
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
      if (segment.isEmpty || segment == _previousSegment) continue;

      final isPurePunctuation = RegExp(r'^[.!?,;:]+$').hasMatch(segment);
      if (isPurePunctuation && _pendingSegments.isNotEmpty) continue;

      try {
        await _tts.speak(segment);
        _previousSegment = segment;
      } catch (e) {
        debugPrint('[TTS] TTS error: $e');
        break;
      }
    }

    _isProcessing = false;

    if (_pendingSegments.isEmpty) {
      if (_messageComplete) {
        await _forceCompleteReading();
      } else if (_buffer.isEmpty) {
        isSpeaking.value = false;
        if (_isLoading) await SoundManager.instance.resumeLoading();
      } else {
        final unspoken = _getUnspokenText();
        if (unspoken.trim().isEmpty) {
          isSpeaking.value = false;
          if (_isLoading) await SoundManager.instance.resumeLoading();
        }
      }
    }
  }

  // ───────────────────────────────────────────────────────────
  // FORCE COMPLETE
  // ───────────────────────────────────────────────────────────
  Future<void> _forceCompleteReading() async {
    final cleanBuffer = _cleanTextForTts(_buffer);
    if (cleanBuffer.trim().isEmpty) {
      isSpeaking.value = false;
      return;
    }

    final unspoken = cleanBuffer.length > _lastSpokenLength
        ? cleanBuffer.substring(_lastSpokenLength).trim()
        : '';

    if (unspoken.isNotEmpty) {
      _pendingSegments.add(unspoken);
      _lastSpokenLength = cleanBuffer.length;
      if (!_isProcessing) await _processNextSegment();
    } else {
      isSpeaking.value = false;
    }
  }

  // ───────────────────────────────────────────────────────────
  // TEXT UTILITIES
  // ───────────────────────────────────────────────────────────
  String _getUnspokenText() {
    final cleaned = _cleanTextForTts(_buffer);
    if (cleaned.length <= _lastSpokenLength) return '';
    return cleaned.substring(_lastSpokenLength).trim();
  }

  List<String> _findCompleteSentences(String text) {
    final out = <String>[];

    // 1. Full sentences
    final endRx = RegExp(r'[.!?]+(?:\s+|$)');
    int last = 0;
    for (final m in endRx.allMatches(text)) {
      final chunk = text.substring(last, m.end).trim();
      if (chunk.length > 2) out.add(chunk);
      last = m.end;
    }
    if (out.isNotEmpty) return out;

    // 2. Clause breaks
    final breakRx = RegExp(
      r'[,;:]\s+|\s+(?:and|but|or|however|therefore|meanwhile|also|then|next|first|second|finally|because|since|while|when|where|after|before)\s+',
    );
    last = 0;
    for (final m in breakRx.allMatches(text)) {
      final chunk = text.substring(last, m.end).trim();
      if (chunk.length > 4) out.add(chunk);
      last = m.end;
    }
    if (out.isNotEmpty) return out;

    // 3. Word‑count fallback
    if (text.length > 8) {
      final words = text.split(' ');
      var buf = '';
      for (final w in words) {
        if ((buf + ' ' + w).trim().length <= 25) {
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

  /// Strip Markdown & normalise whitespace but **keep single `. ! ?`**.
  String _cleanTextForTts(String text) {
    String cleanedText = text
        .removeMarkdown()
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        // Collapse runs of punctuation without deleting the mark
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'([!?]){2,}'), r'$1')
        .replaceAll(RegExp(r'[,;:]{2,}'), ',');
    return cleanedText.trim();
  }

  // ───────────────────────────────────────────────────────────
  // RESET & CLEANUP
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
