// services/streaming_tts_service.dart
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Streaming TTS Service for reading AI responses as they're generated
class StreamingTtsService {
  final FlutterTts _tts;
  final List<String> _pendingSegments = [];
  bool _isSpeaking = false;
  String _buffer = '';
  String _lastSpokenText = '';
  Timer? _bufferTimer;

  StreamingTtsService(this._tts);

  void addText(String newText, String previousText) {
    // Extract new content by comparing with previous text
    if (newText.length <= previousText.length) return;

    // Add new content to buffer
    _buffer = newText;

    // Reset timer - we'll wait for a pause in updates before processing
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 500), () {
      _processBuffer();
    });
  }

  void _processBuffer() {
    if (_buffer.isEmpty || _buffer == _lastSpokenText) return;

    // Clean the text for TTS
    final cleanText = _cleanMarkdownForTts(_buffer);

    // Find complete sentences that we haven't spoken yet
    final newSentences = _findNewCompleteSentences(cleanText, _lastSpokenText);

    if (newSentences.isNotEmpty) {
      _pendingSegments.addAll(newSentences);

      // Update what we've processed
      _lastSpokenText = cleanText;

      // Start speaking if not already speaking
      if (!_isSpeaking) {
        _processNextSegment();
      }
    }
  }

  List<String> _findNewCompleteSentences(String fullText, String spokenText) {
    final sentences = <String>[];

    // Remove what we've already spoken
    String newContent = fullText;
    if (spokenText.isNotEmpty && fullText.startsWith(spokenText)) {
      newContent = fullText.substring(spokenText.length);
    }

    // Look for complete phrases (ending with comma, period, exclamation, or question mark)
    final phraseRegex = RegExp(r'[,.!?]+(?:\s+|$)');
    final matches = phraseRegex.allMatches(newContent);

    int lastEnd = 0;
    for (final match in matches) {
      final phrase = newContent.substring(lastEnd, match.end).trim();
      if (phrase.isNotEmpty && phrase.length > 3) {
        sentences.add(phrase);
        lastEnd = match.end;
      }
    }

    return sentences;
  }

  void _processNextSegment() async {
    if (_pendingSegments.isEmpty) {
      _isSpeaking = false;
      return;
    }

    _isSpeaking = true;
    final segment = _pendingSegments.removeAt(0);

    // Speak the segment
    await _tts.speak(segment);

    // Use TTS completion callback instead of timer
    _tts.setCompletionHandler(() {
      if (_pendingSegments.isNotEmpty) {
        _processNextSegment();
      } else {
        _isSpeaking = false;
      }
    });
  }

  String _cleanMarkdownForTts(String text) {
    // Remove markdown formatting for better TTS
    return text
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1') // Bold
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1') // Italic
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1') // Inline code
        .replaceAll(RegExp(r'#{1,6}\s+'), '') // Headers
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1') // Links
        .replaceAll(RegExp(r'>\s+'), '') // Blockquotes
        .replaceAll(RegExp(r'[-*+]\s+'), '') // List markers
        .replaceAll(RegExp(r'\d+\.\s+'), '') // Numbered list markers
        .replaceAll(RegExp(r'\n+'), ' ') // Replace newlines with spaces
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  void stop() {
    _bufferTimer?.cancel();
    _tts.stop();
    _pendingSegments.clear();
    _isSpeaking = false;
    _buffer = '';
    _lastSpokenText = '';
  }

  void reset() {
    stop();
  }
}
