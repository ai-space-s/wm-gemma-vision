// services/gemma_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_models.dart';

/// Gemma Service (singleton) – loads model once, keeps chat alive
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _initialised = false;

  /// Initialize with selected backend
  Future<void> init(PreferredBackend backend) async {
    if (_initialised) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

    if (!await _gemma.modelManager.isModelInstalled &&
        File(path).existsSync()) {
      await _gemma.modelManager.setModelPath(path);
    }

    _model ??= await _gemma.createModel(
      preferredBackend: backend,
      modelType: ModelType.gemmaIt,
      supportImage: true,
      maxTokens: 4096,
      maxNumImages: 1,
    );

    _chat ??= await _model!.createChat(
      randomSeed: 1,
      temperature: 1,
      topK: 64,
      topP: 0.95,
      supportImage: true,
      tokenBuffer: 256,
    );

    _initialised = true;
  }

  /// Send message with callback-based streaming
  Future<void> sendWithStreaming({
    required String text,
    File? image,
    required Function(String) onToken,
    required Function(MessageStats) onComplete,
  }) async {
    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    int tokenCount = 0;
    final tokens = <String>[];

    // Add the query
    if (image != null) {
      final bytes = await image.readAsBytes();
      await _chat!.addQueryChunk(
        Message.withImage(text: text, imageBytes: bytes, isUser: true),
      );
    } else {
      await _chat!.addQueryChunk(Message.text(text: text, isUser: true));
    }

    // Use the async streaming method from the documentation
    final completer = Completer<void>();

    _chat!.generateChatResponseAsync().listen(
      (String token) {
        if (firstTokenTime == null) {
          firstTokenTime = DateTime.now();
        }
        tokenCount++;
        tokens.add(token);
        onToken(tokens.join(''));
      },
      onDone: () {
        final endTime = DateTime.now();

        // Calculate statistics
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

        onComplete(stats);
        completer.complete();
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    await completer.future;
  }

  Future<void> resetChatSession() async {
    if (!_initialised) return;
    await _chat?.clearHistory();
  }

  Future<void> dispose() async {
    await _model?.close();
    await _gemma.modelManager.deleteModel();
    _model = null;
    _chat = null;
    _initialised = false;
  }
}
