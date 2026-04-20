// lib/chat_page/services/gemma_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_models.dart';
import '../../download_page/config/constants.dart';

/// Singleton service for Google's Gemma AI model
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;

  InferenceModel? _mainModel;
  InferenceChat? _mainChat;

  InferenceModel? _funcModel;
  InferenceChat? _funcChat;

  bool _initialised = false;
  String? _activeModelPath;

  bool _isModelLoading = false;
  String? _loadingError;

  String _getWebModelUrl(String fileName) {
    return Uri.base.removeFragment().resolve('models/$fileName').toString();
  }

  /// Initialize models at startup
  Future<void> init(PreferredBackend backend) async {
    if (_initialised) return;

    String mainPath;
    if (kIsWeb) {
      mainPath = _getWebModelUrl(modelName);
      print("🌐 Running on Web: Using static URL '$mainPath'");
    } else {
      final dir = await getApplicationDocumentsDirectory();
      mainPath = '${dir.path}/$modelName';
    }

    if (kIsWeb) {
      _isModelLoading = true;
      _loadMainModel(mainPath, backend: backend).then((_) {
        _isModelLoading = false;
        print("✅ Web Model Background Load Completed!");
      }).catchError((e) {
        _isModelLoading = false;
        _loadingError = e.toString();
        print("🔥 Web Model Background Load Failed: $e");
      });
      _initialised = true;
    } else {
      await _loadMainModel(mainPath, backend: backend);
      _initialised = true;
    }
  }

  int _getRandomSeed() => DateTime.now().millisecondsSinceEpoch;

  /// Load Main Model (Vision supported)
  Future<void> _loadMainModel(
      String modelPath, {
        PreferredBackend backend = PreferredBackend.gpu,
      }) async {
    if (_activeModelPath == modelPath && _mainChat != null) return;

    try {
      print("🔄 Switching to Main Gemma model: $modelPath");

      _funcChat = null;
      _funcModel = null;

      if (kIsWeb) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(modelPath).install();

        _mainModel = await FlutterGemma.getActiveModel(
          preferredBackend: backend,
          maxTokens: 2048,
          maxNumImages: 1,
        );
      } else {
        if (!File(modelPath).existsSync()) {
          throw Exception("Main model file missing: $modelPath");
        }

        await _gemma.modelManager.setModelPath(modelPath);

        _mainModel = await _gemma.createModel(
          preferredBackend: backend,
          modelType: ModelType.gemmaIt,
          supportImage: true,
          maxTokens: 2048,
          maxNumImages: 1,
        );
      }

      _mainChat = await _mainModel!.createChat(
        randomSeed: _getRandomSeed(),
        temperature: 1.0,
        topK: 64,
        topP: 0.95,
        supportImage: true,
        tokenBuffer: 512,
      );

      _activeModelPath = modelPath;
      print("✅ Main Model Loaded!");
    } catch (e) {
      print("🔥 Failed to load main model: $e");
      _activeModelPath = null;
      rethrow;
    }
  }

  Future<void> _loadFunctionModel(
      String modelPath, {
        PreferredBackend backend = PreferredBackend.gpu,
      }) async {
    if (_activeModelPath == modelPath && _funcChat != null) return;

    try {
      print("🔄 Switching to Function Gemma model: $modelPath");

      _mainChat = null;
      _mainModel = null;

      if (kIsWeb) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(modelPath).install();

        _funcModel = await FlutterGemma.getActiveModel(
          preferredBackend: backend,
          maxTokens: 1024,
          maxNumImages: 0,
        );
      } else {
        await _gemma.modelManager.setModelPath(modelPath);

        _funcModel = await _gemma.createModel(
          preferredBackend: backend,
          modelType: ModelType.gemmaIt,
          supportImage: false,
          maxTokens: 1024,
          maxNumImages: 0,
        );
      }

      _funcChat = await _funcModel!.createChat(
        randomSeed: _getRandomSeed(),
        temperature: 0.0,
        topK: 1,
        topP: 1.0,
        supportImage: false,
        tokenBuffer: 512,
      );

      _activeModelPath = modelPath;
      print("✅ Function Model Loaded!");
    } catch (e) {
      print("🔥 Failed to load function model: $e");
      _activeModelPath = null;
    }
  }

  Future<void> ensureFunctionModelLoaded() async {
    final path = await _getFuncModelPath();
    if (kIsWeb) {
      await _loadFunctionModel(path);
    } else {
      if (await File(path).exists()) {
        await _loadFunctionModel(path);
      }
    }
  }

  Future<String> _getMainModelPath() async {
    if (kIsWeb) return _getWebModelUrl(modelName);
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$modelName';
  }

  Future<String> _getFuncModelPath() async {
    if (kIsWeb) return _getWebModelUrl(functionModelName);
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$functionModelName';
  }

  /// [NEW] Generates a response using a temporary chat session.
  /// This prevents polluting the main chat history with router/logic prompts.
  /// Supports both Function Model and Main Model.
  Future<String> generateWithTemporarySession(String prompt, {bool useFunctionModel = false}) async {
    // 1. Ensure the required model is loaded
    if (useFunctionModel) {
      if (_funcModel == null) await ensureFunctionModelLoaded();
      if (_funcModel == null) return ""; // Failed to load
    } else {
      if (_mainModel == null) {
        // Force load main model if missing
        final path = await _getMainModelPath();
        await _loadMainModel(path);
      }
      if (_mainModel == null) return "";
    }

    final model = useFunctionModel ? _funcModel! : _mainModel!;

    // 2. Create a temporary chat (stateless)
    // Temperature 0.0 is best for logic/routing/JSON generation
    InferenceChat? tempChat;
    try {
      tempChat = await model.createChat(
        randomSeed: _getRandomSeed(),
        temperature: 0.0,
        topK: 1,
        topP: 1.0,
        supportImage: useFunctionModel ? false : true,
        tokenBuffer: 512,
      );

      final responseBuffer = StringBuffer();
      final completer = Completer<String>();

      await tempChat.addQuery(Message.text(text: prompt, isUser: true));

      tempChat.generateChatResponseAsync().listen(
            (ModelResponse res) {
          if (res is TextResponse) {
            responseBuffer.write(res.token);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(responseBuffer.toString());
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      return await completer.future;
    } catch (e) {
      print("Error in temporary generation: $e");
      return "";
    }
    // Note: InferenceChat in FlutterGemma currently doesn't have an explicit dispose method,
    // but letting it go out of scope allows GC to reclaim it.
  }

  Future<String> generateRawResponse(String prompt) async {
    if (_mainChat == null && _funcChat == null) {
      if (kIsWeb) {
        if (_isModelLoading) return "Error: Model is still downloading...";
        if (_loadingError != null) return "Error: Model load failed: $_loadingError";
      }
      final path = await _getMainModelPath();
      await _loadMainModel(path);
    }

    final chat = _mainChat ?? _funcChat;
    if (chat == null) return "";

    final responseBuffer = StringBuffer();
    final completer = Completer<String>();

    try {
      await chat.addQuery(Message.text(text: prompt, isUser: true));

      chat.generateChatResponseAsync().listen(
            (ModelResponse res) {
          if (res is TextResponse) {
            responseBuffer.write(res.token);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(responseBuffer.toString());
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      return await completer.future;
    } catch (e) {
      print("Error in raw generation: $e");
      return "";
    }
  }

  Future<void> sendWithStreaming({
    required String text,
    File? image,
    Function(String)? onToken,
    required Function(MessageStats) onComplete,
  }) async {
    if (_mainChat == null) {
      if (kIsWeb) {
        if (_isModelLoading) {
          throw Exception("모델을 다운로드 중입니다(3GB). 잠시 후 다시 시도해주세요.");
        }
        if (_loadingError != null) {
          throw Exception("모델 로드 실패: $_loadingError");
        }
      }

      final path = await _getMainModelPath();
      await _loadMainModel(path);
    }

    if (_mainChat == null) throw Exception('Main Chat could not be initialized');

    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    int tokenCount = 0;
    final responseBuffer = StringBuffer();

    final completer = Completer<void>();

    try {
      if (image != null && !kIsWeb) {
        final bytes = await image.readAsBytes();
        await _mainChat!.addQuery(
          Message.withImage(text: text, imageBytes: bytes, isUser: true),
        );
      } else {
        await _mainChat!.addQuery(Message.text(text: text, isUser: true));
      }

      bool streamStarted = false;

      _mainChat!.generateChatResponseAsync().listen(
            (ModelResponse res) {
          if (!streamStarted) streamStarted = true;

          if (res is TextResponse) {
            firstTokenTime ??= DateTime.now();
            tokenCount++;
            responseBuffer.write(res.token);
            onToken?.call(res.token);
          }
        },
        onDone: () {
          if (completer.isCompleted) return;

          final endTime = DateTime.now();
          final stats = MessageStats(
            timeToFirstToken: firstTokenTime != null
                ? firstTokenTime!.difference(startTime).inMilliseconds / 1000.0
                : null,
            totalLatency: endTime.difference(startTime).inMilliseconds / 1000.0,
            tokenCount: tokenCount,
          );
          onComplete(stats);
          completer.complete();
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      await completer.future;
    } catch (e) {
      print("Error in sendWithStreaming: $e");
      rethrow;
    }
  }

  /// [Deprecated] Use generateWithTemporarySession or generateRawResponse
  Future<String> generateFunctionResponse(String prompt) async {
    if (_funcChat == null) {
      await ensureFunctionModelLoaded();
    }
    if (_funcChat == null) return "";
    await _funcChat!.clearHistory();
    // Re-use logic... simplified to just call chat logic
    // But since we have generateWithTemporarySession, this is less critical.
    // Keeping basic implementation for compatibility if needed.
    return generateRawResponse(prompt);
  }

  Future<void> resetChatSession() async {
    if (_mainChat != null) {
      await _mainChat!.clearHistory();
    }
    if (_funcChat != null) {
      await _funcChat!.clearHistory();
    }
  }

  Future<void> dispose() async {
    _mainModel = null;
    _mainChat = null;
    _funcModel = null;
    _funcChat = null;
    _activeModelPath = null;
    _initialised = false;
  }
}