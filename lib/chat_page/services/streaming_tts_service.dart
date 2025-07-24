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
  final List<String> _pendingSegments = [];
  bool _isLoading = false;
  String _buffer = '';
  int _lastSpokenLength = 0; // position in the *cleaned* text
  Timer? _bufferTimer;
  Timer? _fallbackTimer;
  bool _messageComplete = false;
  int _tokensSinceLastSpeak = 0;
  bool _isProcessing = false;
  String _previousSegment = '';
  bool _hasStartedSpeaking = false; // Track if we've started speaking at all
  int _totalTokensReceived = 0; // Track total tokens for early speaking

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

  /// Consume one streaming token - AGGRESSIVE early speaking
  void addText(String newToken, String currentFullText) {
    _buffer = currentFullText;
    _tokensSinceLastSpeak++;
    _totalTokensReceived++;

    // Clean the current text for analysis
    final cleanText = _cleanTextForTts(_buffer);

    // VERY AGGRESSIVE: Start speaking after just 3-5 tokens if we have meaningful content
    if (!_hasStartedSpeaking && _totalTokensReceived >= 3) {
      final trimmed = cleanText.trim();
      // Start speaking if we have at least 10 characters and it's not just punctuation
      if (trimmed.length >= 10 && !RegExp(r'^[.!?,;:\s]+$').hasMatch(trimmed)) {
        _hasStartedSpeaking = true;
        _forceEarlySpeaking();
        return;
      }
    }

    // EARLY TRIGGERS: Look for natural break points very early
    if (!_hasStartedSpeaking && _totalTokensReceived >= 2) {
      // Start if we hit a comma, colon, or other natural pause
      if (RegExp(r'[,;:]').hasMatch(cleanText) &&
          cleanText.trim().length >= 8) {
        _hasStartedSpeaking = true;
        _forceEarlySpeaking();
        return;
      }
    }

    // FALLBACK: If we have 15+ characters and still haven't started, force it
    if (!_hasStartedSpeaking && cleanText.trim().length >= 15) {
      _hasStartedSpeaking = true;
      _forceEarlySpeaking();
      return;
    }

    // Regular processing with much shorter delays
    _bufferTimer?.cancel();
    _bufferTimer = Timer(
      const Duration(milliseconds: 150),
      _processBuffer,
    ); // Reduced from 300ms

    // More aggressive fallback timing
    if (_tokensSinceLastSpeak >= 3 || _getUnspokenText().length > 15) {
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(
        const Duration(milliseconds: 200),
        _forceSpeak,
      ); // Reduced from 400ms
    }
  }

  /// Force early speaking with minimal content
  void _forceEarlySpeaking() {
    if (_buffer.isEmpty || _isProcessing) return;

    final cleanText = _cleanTextForTts(_buffer).trim();
    if (cleanText.length >= 8) {
      // Very low threshold
      // Just speak what we have so far, even if it's incomplete
      _pendingSegments.add(cleanText);
      _lastSpokenLength = cleanText.length;
      _tokensSinceLastSpeak = 0;
      if (!_isProcessing) _processNextSegment();
    }
  }

  Future<void> onMessageComplete() async {
    _messageComplete = true;
    await stopLoading();
    _bufferTimer?.cancel();
    _fallbackTimer?.cancel();

    // CRITICAL: Always ensure we speak the complete final text
    debugPrint(
      '[TTS] Message complete. Buffer length: ${_buffer.length}, Last spoken: $_lastSpokenLength',
    );

    // Add punctuation if missing for natural ending
    if (_buffer.trim().isNotEmpty && !RegExp(r'[.!?]\s*$').hasMatch(_buffer)) {
      _buffer += '.';
    }

    // Give a moment for any ongoing speech to complete
    await Future.delayed(const Duration(milliseconds: 100));

    // GUARANTEE: Speak everything remaining
    await _forceCompleteReading();
  }

  /// GUARANTEE complete reading of all text
  Future<void> _forceCompleteReading() async {
    final cleanBuffer = _cleanTextForTts(_buffer);

    if (cleanBuffer.trim().isEmpty) {
      isSpeaking.value = false;
      return;
    }

    // Calculate what we haven't spoken yet
    final unspoken = cleanBuffer.length > _lastSpokenLength
        ? cleanBuffer.substring(_lastSpokenLength).trim()
        : '';

    debugPrint(
      '[TTS] Force complete reading. Unspoken: "${unspoken}" (${unspoken.length} chars)',
    );

    if (unspoken.isNotEmpty) {
      // Force speak the remaining text, regardless of punctuation or length
      _pendingSegments.add(unspoken);
      _lastSpokenLength = cleanBuffer.length;

      if (!_isProcessing) {
        await _processNextSegment();
      }
    } else {
      // If nothing unspoken, but we have very short total response, speak it all
      if (cleanBuffer.length < 100 && _lastSpokenLength == 0) {
        debugPrint(
          '[TTS] Very short response, speaking entire buffer: "$cleanBuffer"',
        );
        _pendingSegments.add(cleanBuffer);
        _lastSpokenLength = cleanBuffer.length;
        if (!_isProcessing) {
          await _processNextSegment();
        }
      } else {
        isSpeaking.value = false;
      }
    }
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

    final cleanText = _cleanTextForTts(_buffer);
    if (cleanText.length <= _lastSpokenLength) return;

    final newContent = cleanText.substring(_lastSpokenLength);
    if (newContent.trim().isEmpty) return;

    // More aggressive sentence detection
    final sentences = _findCompleteSentences(newContent);

    if (sentences.isNotEmpty) {
      final slice = sentences.join(' ');
      _pendingSegments.addAll(sentences);
      _lastSpokenLength += slice.length;
      _tokensSinceLastSpeak = 0;

      if (!_isProcessing) _processNextSegment();
    } else if (newContent.length > 12) {
      // Reduced from 25
      // Much more aggressive - speak partial content sooner
      _forceSpeak();
    }
  }

  void _forceSpeak() {
    if (_buffer.isEmpty || _isProcessing) return;

    final unspoken = _getUnspokenText();
    // Much lower threshold - speak almost anything
    if (unspoken.isNotEmpty && unspoken.length > 3) {
      // Reduced from 5
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

      // More lenient filtering - speak almost everything
      if (segment.isEmpty || segment == _previousSegment) {
        continue;
      }

      // Don't skip segments that are ONLY punctuation if they're at the end
      final isPurePunctuation = RegExp(r'^[.!?,;:]+$').hasMatch(segment);
      if (isPurePunctuation && _pendingSegments.isNotEmpty) {
        continue; // Skip only if more segments are coming
      }

      try {
        debugPrint('[TTS] Speaking segment: "$segment"');
        await _tts.speak(segment);
        _previousSegment = segment;
      } catch (e) {
        debugPrint('[TTS] TTS error: $e');
        break;
      }
    }

    _isProcessing = false;

    // Enhanced continuation logic
    if (_pendingSegments.isEmpty) {
      if (_messageComplete) {
        // Double-check we've spoken everything
        await _forceCompleteReading();
      } else if (_buffer.isEmpty) {
        isSpeaking.value = false;
        if (_isLoading) {
          await SoundManager.instance.resumeLoading();
        }
      } else {
        // Still generating - check if there's more to speak
        final unspoken = _getUnspokenText();
        if (unspoken.trim().isEmpty) {
          isSpeaking.value = false;
          if (_isLoading) {
            await SoundManager.instance.resumeLoading();
          }
        }
      }
    }
  }

  // ───────────────────────────────────────────────────────────
  // TEXT HELPERS - More aggressive breaking
  // ───────────────────────────────────────────────────────────
  String _getUnspokenText() {
    final cleaned = _cleanTextForTts(_buffer);
    if (cleaned.length <= _lastSpokenLength) return '';
    return cleaned.substring(_lastSpokenLength).trim();
  }

  List<String> _findCompleteSentences(String text) {
    final out = <String>[];

    // 1. Look for complete sentences first
    final endRx = RegExp(r'[.!?]+(?:\s+|$)');
    int last = 0;
    for (final m in endRx.allMatches(text)) {
      final chunk = text.substring(last, m.end).trim();
      if (chunk.length > 2) out.add(chunk);
      last = m.end;
    }
    if (out.isNotEmpty) return out;

    // 2. Look for clause breaks - much more aggressive
    final breakRx = RegExp(
      r'[,;:]\s+|\s+(?:and|but|or|however|therefore|meanwhile|also|then|next|first|second|finally|because|since|while|when|where|after|before)\s+',
    );
    last = 0;
    for (final m in breakRx.allMatches(text)) {
      final chunk = text.substring(last, m.end).trim();
      if (chunk.length > 4) out.add(chunk); // Reduced from 8
      last = m.end;
    }
    if (out.isNotEmpty) return out;

    // 3. Word-count fallback - much more aggressive
    if (text.length > 8) {
      // Reduced from 35
      final words = text.split(' ');
      var buf = '';
      for (final w in words) {
        if ((buf + ' ' + w).trim().length <= 25) {
          // Reduced from 40
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

  /// Clean text for TTS using the remove_markdown package and additional normalization
  String _cleanTextForTts(String text) {
    // First, remove markdown using the package
    String cleanedText = text.removeMarkdown();

    // Additional text normalization for better TTS
    cleanedText = cleanedText
        // Normalize whitespace
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        // Clean up punctuation
        .replaceAll(RegExp(r'(^|\s)[.!?](?=\s|$)'), ' ')
        .replaceAll(RegExp(r'\s+(?=[.!?,;:])'), '')
        .replaceAll(RegExp(r'\.{2,}'), '')
        .replaceAll(RegExp(r'[.!?]{2,}'), '.')
        .replaceAll(RegExp(r'[,;:]{2,}'), ',');

    return cleanedText.trim();
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
    _hasStartedSpeaking = false; // Reset early speaking tracking
    _totalTokensReceived = 0; // Reset token counter
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
