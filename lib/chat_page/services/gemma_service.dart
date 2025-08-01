// services/gemma_service.dart - Further Optimized Version
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
      maxTokens: 8192,
      maxNumImages: 1,
    );

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

  /// 🔑 ULTRA-OPTIMIZED: Return the raw token stream instead of processing it
  /// This eliminates the intermediate callback layer for maximum performance
  Future<Stream<String>> sendWithStreamingDirect({
    required String text,
    File? image,
  }) async {
    // Add the query
    if (image != null) {
      final bytes = await image.readAsBytes();
      await _chat!.addQuery(
        Message.withImage(text: text, imageBytes: bytes, isUser: true),
      );
    } else {
      await _chat!.addQuery(Message.text(text: text, isUser: true));
    }

    // 🔑 Return raw stream of tokens - let caller handle throttling
    return _chat!
        .generateChatResponseAsync()
        .where((res) => res is TextResponse)
        .map((res) => (res as TextResponse).token);
  }

  /// Legacy callback-based method (kept for compatibility) - DEBUG VERSION
  Future<void> sendWithStreaming({
    required String text,
    File? image,
    required Function(String) onToken,
    required Function(MessageStats) onComplete,
  }) async {
    debugPrint('🤖 GemmaService.sendWithStreaming called');
    debugPrint('📝 Text length: ${text.length}');
    debugPrint('🖼️ Image provided: ${image != null}');
    debugPrint('🔧 Model initialized: ${_model != null}');
    debugPrint('💬 Chat initialized: ${_chat != null}');

    if (!_initialised) {
      debugPrint('❌ Service not initialized!');
      throw Exception('GemmaService not initialized');
    }

    if (_chat == null) {
      debugPrint('❌ Chat is null!');
      throw Exception('Chat not available');
    }

    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    int tokenCount = 0;
    final responseBuffer = StringBuffer();

    try {
      debugPrint('📋 Adding query to chat...');
      if (image != null) {
        final bytes = await image.readAsBytes();
        debugPrint('🖼️ Image bytes length: ${bytes.length}');
        await _chat!.addQuery(
          Message.withImage(text: text, imageBytes: bytes, isUser: true),
        );
      } else {
        await _chat!.addQuery(Message.text(text: text, isUser: true));
      }
      debugPrint('✅ Query added successfully');

      final completer = Completer<void>();
      bool streamStarted = false;

      debugPrint('🎯 Starting response stream...');
      _chat!.generateChatResponseAsync().listen(
        (ModelResponse res) {
          if (!streamStarted) {
            debugPrint('🎉 Stream started! First response received');
            streamStarted = true;
          }

          debugPrint('📨 Received response type: ${res.runtimeType}');

          if (res is TextResponse) {
            firstTokenTime ??= DateTime.now();
            tokenCount++;
            responseBuffer.write(res.token);

            debugPrint(
              '🔤 Token $tokenCount: "${res.token.replaceAll('\n', '\\n')}"',
            );

            // 🔑 Send individual tokens, let caller handle throttling
            try {
              onToken(res.token);
              debugPrint('✅ Token passed to callback successfully');
            } catch (e) {
              debugPrint('❌ Error in onToken callback: $e');
            }
          } else {
            debugPrint('⚠️ Non-text response: $res');
          }
        },
        onDone: () {
          debugPrint('🏁 Stream completed! Total tokens: $tokenCount');
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

          debugPrint('📊 Final stats: $stats');

          try {
            onComplete(stats);
            debugPrint('✅ onComplete callback executed successfully');
          } catch (e) {
            debugPrint('❌ Error in onComplete callback: $e');
          }

          completer.complete();
        },
        onError: (error) {
          debugPrint('❌ Stream error: $error');
          completer.completeError(error);
        },
      );

      debugPrint('⏳ Waiting for stream to complete...');
      await completer.future;
      debugPrint('✅ sendWithStreaming completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR in sendWithStreaming: $e');
      debugPrint('📚 Stack trace: $stackTrace');
      rethrow;
    }
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
