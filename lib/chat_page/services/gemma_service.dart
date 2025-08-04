// services/gemma_service.dart - Further Optimized Version
import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_models.dart';

/// Gemma Service (singleton) – loads model once, keeps chat alive.
/// This version is performance-minded: direct streaming of raw tokens
/// and minimal intermediate processing.
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _initialised = false;

  /// Initialize with the selected backend.
  /// - Only runs once (idempotent guard).
  /// - Attempts to use a locally cached model file if installed.
  Future<void> init(PreferredBackend backend) async {
    if (_initialised) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

    // If a model file exists locally and the plugin hasn't installed one yet,
    // point it to the local path to avoid redundant downloads.
    if (!await _gemma.modelManager.isModelInstalled &&
        File(path).existsSync()) {
      await _gemma.modelManager.setModelPath(path);
    }

    // Lazily create the model if not yet created.
    _model ??= await _gemma.createModel(
      preferredBackend: backend,
      modelType: ModelType.gemmaIt,
      supportImage: true,
      maxTokens: 8192,
      maxNumImages: 1,
    );

    // Lazily create the chat session tied to the model.
    _chat ??= await _model!.createChat(
      randomSeed: 1,
      temperature: 1,
      topK: 64,
      topP: 0.95,
      supportImage: true,
      tokenBuffer: 512,
    );

    _initialised = true;
  }

  /// ULTRA-OPTIMIZED path: Return the raw token stream directly.
  /// Caller is responsible for throttling, buffering, and any presentation logic.
  Future<Stream<String>> sendWithStreamingDirect({
    required String text,
    File? image,
  }) async {
    // Attach user query to the chat. Support optional image payload.
    if (image != null) {
      final bytes = await image.readAsBytes();
      await _chat!.addQuery(
        Message.withImage(text: text, imageBytes: bytes, isUser: true),
      );
    } else {
      await _chat!.addQuery(Message.text(text: text, isUser: true));
    }

    // Return filtered stream (only text tokens) so caller receives raw tokens.
    return _chat!
        .generateChatResponseAsync()
        .where((res) => res is TextResponse)
        .map((res) => (res as TextResponse).token);
  }

  /// Legacy callback-based method (kept for compatibility).
  /// - Sends tokens via `onToken`.
  /// - Invokes `onComplete` with aggregated stats.
  /// Note: All logging/debugging removed; callers should provide instrumentation if needed.
  Future<void> sendWithStreaming({
    required String text,
    File? image,
    required Function(String) onToken,
    required Function(MessageStats) onComplete,
  }) async {
    if (!_initialised) {
      throw Exception('GemmaService not initialized');
    }
    if (_chat == null) {
      throw Exception('Chat not available');
    }

    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    int tokenCount = 0;
    final responseBuffer = StringBuffer();

    // Attach the user message (with optional image).
    if (image != null) {
      final bytes = await image.readAsBytes();
      await _chat!.addQuery(
        Message.withImage(text: text, imageBytes: bytes, isUser: true),
      );
    } else {
      await _chat!.addQuery(Message.text(text: text, isUser: true));
    }

    final completer = Completer<void>();
    bool streamStarted = false;

    // Listen to the model's response stream and propagate tokens and completion.
    _chat!.generateChatResponseAsync().listen(
      (ModelResponse res) {
        if (!streamStarted) {
          streamStarted = true; // Mark that the stream has begun.
        }

        if (res is TextResponse) {
          // Capture first token timing for latency metrics.
          firstTokenTime ??= DateTime.now();
          tokenCount++;
          responseBuffer.write(res.token);

          // Forward each token to caller.
          try {
            onToken(res.token);
          } catch (_) {
            // Swallow callback errors; they are caller-specific.
          }
        } else {
          // Non-text responses are currently ignored; could be extended later.
        }
      },
      onDone: () {
        final endTime = DateTime.now();
        final stats = MessageStats(
          timeToFirstToken: firstTokenTime != null
              ? firstTokenTime!.difference(startTime).inMilliseconds / 1000.0
              : null,
          totalLatency: endTime.difference(startTime).inMilliseconds / 1000.0,
          tokenCount: tokenCount,
          prefillSpeed: firstTokenTime != null && tokenCount > 0
              ? 1000.0 / firstTokenTime!.difference(startTime).inMilliseconds
              : null,
          decodeSpeed: firstTokenTime != null && tokenCount > 1
              ? (tokenCount - 1) *
                    1000.0 /
                    endTime.difference(firstTokenTime!).inMilliseconds
              : null,
        );

        // Final callback with collected statistics.
        try {
          onComplete(stats);
        } catch (_) {
          // ignore
        }

        completer.complete();
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    await completer.future;
  }

  /// Clears conversation history but retains loaded model (fast reset).
  Future<void> resetChatSession() async {
    if (!_initialised) return;
    await _chat?.clearHistory();
  }

  /// Dispose of the entire stack: model, underlying plugin state, and reset initialization.
  Future<void> dispose() async {
    await _model?.close();
    await _gemma.modelManager.deleteModel();
    _model = null;
    _chat = null;
    _initialised = false;
  }
}
