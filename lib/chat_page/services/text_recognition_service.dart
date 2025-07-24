// lib/chat_page/services/text_recognition_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service for on-device text recognition using Google ML Kit
class TextRecognitionService {
  static final TextRecognitionService _instance =
      TextRecognitionService._internal();
  static TextRecognitionService get instance => _instance;

  TextRecognitionService._internal();

  late final TextRecognizer _textRecognizer;
  bool _initialized = false;

  /// Initialize the text recognizer
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _textRecognizer = TextRecognizer(
        script: TextRecognitionScript
            .latin, // You can change this based on your needs
      );
      _initialized = true;
      debugPrint('[TextRecognitionService] Initialized successfully');
    } catch (e) {
      debugPrint('[TextRecognitionService] Initialization error: $e');
      rethrow;
    }
  }

  /// Extract text from an image file
  Future<String> extractTextFromImage(File imageFile) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        debugPrint('[TextRecognitionService] No text detected in image');
        return '';
      }

      debugPrint(
        '[TextRecognitionService] Extracted text: ${recognizedText.text}',
      );
      return recognizedText.text;
    } catch (e) {
      debugPrint('[TextRecognitionService] Text extraction error: $e');
      // Don't throw error - just return empty string so the app continues to work
      return '';
    }
  }

  /// Extract text with additional metadata (blocks, lines, elements)
  Future<TextExtractionResult> extractTextWithMetadata(File imageFile) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final blocks = <String>[];
      final lines = <String>[];

      for (TextBlock block in recognizedText.blocks) {
        blocks.add(block.text);
        for (TextLine line in block.lines) {
          lines.add(line.text);
        }
      }

      return TextExtractionResult(
        fullText: recognizedText.text,
        blocks: blocks,
        lines: lines,
        confidence: _calculateAverageConfidence(recognizedText),
      );
    } catch (e) {
      debugPrint(
        '[TextRecognitionService] Text extraction with metadata error: $e',
      );
      return TextExtractionResult(
        fullText: '',
        blocks: [],
        lines: [],
        confidence: 0.0,
      );
    }
  }

  /// Calculate average confidence score
  double _calculateAverageConfidence(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) return 0.0;

    double totalConfidence = 0.0;
    int elementCount = 0;

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) {
          // Note: ML Kit doesn't provide confidence scores in the current version
          // This is a placeholder for future versions or custom implementation
          totalConfidence += 1.0; // Assume 100% confidence for now
          elementCount++;
        }
      }
    }

    return elementCount > 0 ? totalConfidence / elementCount : 0.0;
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_initialized) {
      await _textRecognizer.close();
      _initialized = false;
      debugPrint('[TextRecognitionService] Disposed');
    }
  }
}

/// Result class for text extraction with metadata
class TextExtractionResult {
  final String fullText;
  final List<String> blocks;
  final List<String> lines;
  final double confidence;

  TextExtractionResult({
    required this.fullText,
    required this.blocks,
    required this.lines,
    required this.confidence,
  });

  bool get hasText => fullText.isNotEmpty;

  @override
  String toString() {
    return 'TextExtractionResult(text: "${fullText.length > 50 ? '${fullText.substring(0, 50)}...' : fullText}", blocks: ${blocks.length}, lines: ${lines.length}, confidence: ${confidence.toStringAsFixed(2)})';
  }
}
