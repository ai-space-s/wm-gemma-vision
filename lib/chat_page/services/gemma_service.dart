// lib/chat_page/services/gemma_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message_models.dart';
import '../../download_page/config/constants.dart';

enum MlcBackend { cpu, gpu }

/// Singleton service for Gemma 4 through the native Android runtime.
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.tommasogiovannini.gemma/mlc',
  );
  static const EventChannel _streamChannel = EventChannel(
    'com.tommasogiovannini.gemma/mlc_stream',
  );

  StreamSubscription<dynamic>? _streamSubscription;
  final Map<String, _PendingGeneration> _pending = {};

  bool _initialised = false;
  bool _isModelLoading = false;
  String? _loadingError;
  String? _modelPath;
  MlcBackend _backend = MlcBackend.gpu;

  Future<void> init(MlcBackend backend) async {
    if (_initialised && _backend == backend) return;
    _backend = backend;
    _isModelLoading = true;
    _loadingError = null;

    try {
      _modelPath = await _getMainModelPath();
      if (kIsWeb) {
        throw UnsupportedError(
          'Gemma 4 web runtime is not wired for Flutter Web.',
        );
      }

      final modelFile = File(_modelPath!);
      final modelDir = Directory(_modelPath!);
      if (!await modelFile.exists() && !await modelDir.exists()) {
        throw Exception('Gemma 4 model artifact missing: $_modelPath');
      }

      await _ensureStreamSubscription();
      await _channel.invokeMethod('initialize', {
        'modelPath': _modelPath,
        'modelLib': androidModelRuntimeLib,
        'runtime': modelRuntime,
        'backend': backend.name,
      });

      _initialised = true;
    } catch (e) {
      _loadingError = e.toString();
      _initialised = false;
      rethrow;
    } finally {
      _isModelLoading = false;
    }
  }

  Future<void> _ensureStreamSubscription() async {
    _streamSubscription ??= _streamChannel.receiveBroadcastStream().listen(
      _handleStreamEvent,
      onError: (Object error) {
        for (final pending in _pending.values) {
          pending.completeError(error);
        }
        _pending.clear();
      },
    );
  }

  void _handleStreamEvent(dynamic event) {
    if (event is! Map) return;
    final requestId = event['requestId']?.toString();
    if (requestId == null) return;

    final pending = _pending[requestId];
    if (pending == null) return;

    final error = event['error']?.toString();
    if (error != null && error.isNotEmpty) {
      _pending.remove(requestId);
      pending.completeError(Exception(error));
      return;
    }

    final token = event['token']?.toString();
    if (token != null && token.isNotEmpty) {
      pending.addToken(token);
    }

    final done = event['done'] == true;
    if (done) {
      _pending.remove(requestId);
      pending.complete();
    }
  }

  Future<String> _getMainModelPath() async {
    if (kIsWeb) {
      return Uri.base.removeFragment().resolve('models/$modelName').toString();
    }
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$modelName';
  }

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    if (_isModelLoading) {
      throw Exception('모델을 로딩 중입니다. 잠시 후 다시 시도해주세요.');
    }
    if (_loadingError != null) {
      throw Exception('모델 로드 실패: $_loadingError');
    }
    await init(_backend);
  }

  int _seed() => DateTime.now().millisecondsSinceEpoch;

  Future<String> generateWithTemporarySession(String prompt) async {
    final buffer = StringBuffer();
    await _generate(
      prompt: prompt,
      temperature: 0.0,
      topP: 1.0,
      maxTokens: 512,
      temporarySession: true,
      onToken: buffer.write,
    );
    return buffer.toString();
  }

  Future<String> generateRawResponse(String prompt) async {
    final buffer = StringBuffer();
    await _generate(
      prompt: prompt,
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 2048,
      onToken: buffer.write,
    );
    return buffer.toString();
  }

  Future<void> sendWithStreaming({
    required String text,
    File? image,
    Function(String)? onToken,
    required FutureOr<void> Function(MessageStats) onComplete,
  }) async {
    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    var tokenCount = 0;

    await _generate(
      prompt: text,
      imagePath: image?.path,
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 2048,
      onToken: (token) {
        firstTokenTime ??= DateTime.now();
        tokenCount++;
        onToken?.call(token);
      },
    );

    final endTime = DateTime.now();
    await onComplete(
      MessageStats(
        timeToFirstToken: firstTokenTime != null
            ? firstTokenTime!.difference(startTime).inMilliseconds / 1000.0
            : null,
        totalLatency: endTime.difference(startTime).inMilliseconds / 1000.0,
        tokenCount: tokenCount,
      ),
    );
  }

  Future<void> _generate({
    required String prompt,
    String? imagePath,
    required double temperature,
    required double topP,
    required int maxTokens,
    bool temporarySession = false,
    required void Function(String token) onToken,
  }) async {
    await _ensureInitialised();
    await _ensureStreamSubscription();

    final requestId = 'mlc-${DateTime.now().microsecondsSinceEpoch}';
    final pending = _PendingGeneration(onToken);
    _pending[requestId] = pending;

    try {
      await _channel.invokeMethod(
        temporarySession ? 'generateTemporary' : 'generate',
        {
          'requestId': requestId,
          'prompt': prompt,
          if (imagePath != null && imagePath.isNotEmpty) 'imagePath': imagePath,
          'temperature': temperature,
          'topP': topP,
          'maxTokens': maxTokens,
          'seed': _seed(),
        },
      );
      await pending.future;
    } catch (e) {
      _pending.remove(requestId);
      rethrow;
    }
  }

  Future<void> resetChatSession() async {
    if (!_initialised) return;
    await _channel.invokeMethod('reset');
  }

  Future<void> dispose() async {
    for (final pending in _pending.values) {
      pending.completeError(StateError('GemmaService disposed'));
    }
    _pending.clear();
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    if (_initialised) {
      await _channel.invokeMethod('dispose');
    }
    _initialised = false;
    _modelPath = null;
  }
}

class _PendingGeneration {
  _PendingGeneration(this._onToken);

  final void Function(String token) _onToken;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void addToken(String token) => _onToken(token);

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void completeError(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}
