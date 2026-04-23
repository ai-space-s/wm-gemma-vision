// lib/chat_page/services/chat_helpers.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message_models.dart';
import '../widgets/prompt_bar.dart';
import 'function_calling_service.dart';
import 'gemma_service.dart';
import 'speech_service.dart';
import 'streaming_tts_service.dart';
import 'text_recognition_service.dart';
import '../../app_settings.dart';

class ChatHelpers {
  final GemmaService _service;
  final StreamingTtsService _streamingTts;
  final SpeechService _speechService;
  final TextRecognitionService _textRecognition;
  final VoidCallback _onStateChanged;
  final Function(String) _showSnackBar;

  // [추가] 갤러리 이미지 선택을 위한 ImagePicker 인스턴스
  final ImagePicker _picker = ImagePicker();

  String _systemCtx;
  bool _resetting = false;
  bool _isGenerating = false;

  bool _isFirstMessage = true;

  ChatHelpers({
    required GemmaService service,
    required StreamingTtsService streamingTts,
    required SpeechService speechService,
    required TextRecognitionService textRecognition,
    required VoidCallback onStateChanged,
    required Function(String) showSnackBar,
    required String systemContext,
  }) : _service = service,
       _streamingTts = streamingTts,
       _speechService = speechService,
       _textRecognition = textRecognition,
       _onStateChanged = onStateChanged,
       _showSnackBar = showSnackBar,
       _systemCtx = systemContext {
    _streamingTts.isSpeaking.addListener(_onStateChanged);
  }

  void dispose() {
    _streamingTts.isSpeaking.removeListener(_onStateChanged);
  }

  bool get resetting => _resetting;
  bool get isGenerating => _isGenerating;
  bool get isSpeaking => _streamingTts.isSpeaking.value;
  String get systemContext => _systemCtx;

  void updateSystemContext(String newContext) => _systemCtx = newContext;

  Future<void> stopSpeaking() async {
    _streamingTts.stop();
    await _speechService.stopTts();
    _onStateChanged();
  }

  String _buildConversationPrompt(
    List<ChatMessage> messages,
    String currentPrompt, {
    required bool includeSystem,
    bool replaceLastUser = false,
    int maxHistoryMessages = 10,
  }) {
    final history = <ChatMessage>[...messages];
    while (history.isNotEmpty &&
        !history.last.isUser &&
        history.last.isStreaming &&
        history.last.text.trim().isEmpty) {
      history.removeLast();
    }
    if (replaceLastUser && history.isNotEmpty && history.last.isUser) {
      history.removeLast();
    }

    final selected = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;
    final buffer = StringBuffer();
    if (includeSystem) {
      buffer.writeln('System: $_systemCtx');
      buffer.writeln();
    }
    for (final message in selected) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      buffer.writeln('${message.isUser ? 'User' : 'Assistant'}: $text');
    }
    buffer.writeln('User: ${currentPrompt.trim()}');
    buffer.write('Assistant:');
    return buffer.toString();
  }

  Future<void> _announceError(String error) async {
    try {
      final cleanError = error.replaceAll('Exception:', '').trim();
      await _speechService.speak('Error: $cleanError');
    } catch (e) {
      debugPrint('Failed to announce error: $e');
    }
  }

  Future<void> _announceStateChange(String message) async {
    try {
      await _speechService.speak(message);
    } catch (e) {
      debugPrint('Failed to announce state change: $e');
    }
  }

  Future<void> newChat(
    List<ChatMessage> messages,
    GlobalKey<PromptBarState>? promptBarKey,
  ) async {
    if (_resetting) return;
    try {
      _streamingTts.reset();
      _resetting = true;
      _onStateChanged();
      await _announceStateChange('Starting new chat');

      messages.clear();
      promptBarKey?.currentState?.clear();
      await _service.resetChatSession();
      _isFirstMessage = true;

      _resetting = false;
      _onStateChanged();
      await _announceStateChange('New chat ready');
    } catch (e) {
      _resetting = false;
      _onStateChanged();
      _showSnackBar('Failed to start new chat: $e');
    }
  }

  Future<void> showMessages(List<ChatMessage> messages, bool show) async {
    if (show) {
      await _announceStateChange('Showing ${messages.length} messages');
    } else {
      await _announceStateChange('Hiding messages');
    }
  }

  // [수정] Web 호환성 체크 추가
  Future<File?> _captureWithEfficientCamera() async {
    if (kIsWeb) throw Exception('Camera is not supported on Web.');
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available');
      final description = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      final image = await controller.takePicture();
      return File(image.path);
    } catch (e) {
      await _announceError('Camera error: $e');
      rethrow;
    } finally {
      await controller?.dispose();
    }
  }

  // [신규] 카메라 캡처 후 전송 (기존 captureAndSend 대체)
  Future<void> captureWithCamera(
    String prompt,
    List<ChatMessage> messages, {
    bool isQuickAction = false,
  }) async {
    try {
      final imageFile = await _captureWithEfficientCamera();
      await _processAndSendImage(
        prompt,
        messages,
        imageFile,
        isQuickAction: isQuickAction,
      );
    } catch (e) {
      if (kIsWeb) {
        _showSnackBar('Camera not supported on Web');
      } else {
        // 이미 _captureWithEfficientCamera 내부에서 에러를 읽어줬을 수 있음
        // 추가 처리가 필요하다면 여기에 작성
      }
    }
  }

  // [신규] 갤러리에서 이미지 선택 후 전송
  Future<void> pickFromGallery(
    String prompt,
    List<ChatMessage> messages,
  ) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return; // 사용자가 취소함

      // Web에서는 File 객체가 정상 동작하지 않을 수 있으나,
      // GemmaService에서 Web일 경우 이미지를 무시하거나 URL 처리를 하므로
      // 여기서는 모바일 기준으로 File 객체를 생성하여 넘김.
      final imageFile = File(pickedFile.path);

      await _processAndSendImage(prompt, messages, imageFile);
    } catch (e) {
      await _announceError('Gallery error: $e');
      _showSnackBar('Failed to pick image: $e');
    }
  }

  // [신규] 이미지 처리 및 전송 공통 로직 (기존 captureAndSend의 핵심 로직 이동)
  Future<void> _processAndSendImage(
    String prompt,
    List<ChatMessage> messages,
    File? imageFile, {
    bool isQuickAction = false,
  }) async {
    try {
      // 이미지 메시지 UI 추가
      messages.add(
        ChatMessage.withImageFile(prompt, isUser: true, imageFile: imageFile),
      );
      _onStateChanged();

      final aiMsg = ChatMessage.text('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      await _speechService.playWooshSound();
      _isGenerating = true;
      _onStateChanged();

      if (!isQuickAction) await _speechService.announceMessageType(true);
      await _streamingTts.startLoading();

      String extractedText = '';
      try {
        // Web에서는 File 기반 OCR이 지원되지 않을 수 있으므로 체크
        if (imageFile != null && !kIsWeb) {
          extractedText = await _textRecognition.extractTextFromImage(
            imageFile,
          );
        }
      } catch (e) {
        debugPrint('OCR extraction failed: $e');
      }

      String enhancedPrompt = prompt.trim();
      if (extractedText.isNotEmpty) {
        enhancedPrompt =
            '''$prompt\n\n[OCR text detected in the image]\n$extractedText\n\nUse the image itself if the Gemma 4 vision runtime is available. If only OCR is available, clearly limit the answer to the detected text.''';
      } else if (imageFile != null) {
        enhancedPrompt =
            '''$prompt\n\n[Image attached]\nUse the image itself if the Gemma 4 vision runtime is available. If the runtime cannot inspect images, say that image understanding is not available instead of guessing.''';
      }

      final responseBuffer = StringBuffer();
      final streamingEnabled = AppSettings.instance.streamingResponsesEnabled;
      final fullPrompt = _buildConversationPrompt(
        messages,
        enhancedPrompt,
        includeSystem: _isFirstMessage,
        replaceLastUser: true,
      );
      if (_isFirstMessage) _isFirstMessage = false;

      await _service.sendWithStreaming(
        text: fullPrompt,
        image: imageFile,
        onToken: (tok) {
          responseBuffer.write(tok);
          final currentText = responseBuffer.toString();
          if (streamingEnabled) {
            _streamingTts.addText(tok, currentText);
            aiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          final finalText = responseBuffer.toString().trim();
          aiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          _onStateChanged();
          if (!streamingEnabled && finalText.isNotEmpty) {
            _streamingTts.addText(finalText, finalText);
          }
          await _streamingTts.onMessageComplete();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      _isGenerating = false;
      _onStateChanged();
      if (messages.isNotEmpty) messages.last.text = 'Error: $e';
      await _announceError('Failed to process image: $e');
    }
  }

  /// Send text-only message with Gemma 4 tool calling.
  Future<void> sendTextOnly(
    String prompt,
    List<ChatMessage> messages, {
    bool isInternalCall = false,
    bool isFunctionResult = false,
  }) async {
    try {
      // 1. 사용자 메시지 UI 추가
      if (!isInternalCall) {
        messages.add(ChatMessage.text(prompt, isUser: true));
        _onStateChanged();

        final aiMsg = ChatMessage.text('', isUser: false, isStreaming: true);
        messages.add(aiMsg);
        _onStateChanged();

        await _speechService.playWooshSound();
        _isGenerating = true;
        _onStateChanged();
        await _speechService.announceMessageType(false);
      }

      // 2. Function Calling Loop
      if (!isInternalCall) {
        messages.last.text = "Analyzing request...";
        _onStateChanged();

        final functionCall = await FunctionCallingService.instance.predict(
          prompt,
        );

        if (functionCall != null) {
          debugPrint("Function call detected: ${functionCall.name}");

          if (messages.isNotEmpty) {
            messages.last.text = "Running ${functionCall.name}...";
            _onStateChanged();
          }

          // Generalized Execution Handler
          await _handleFunctionExecution(functionCall, prompt, messages);
          return; // 재귀 호출로 넘어가므로 여기서 종료
        }

        // 함수 호출이 없으면 텍스트 초기화 (스트리밍 준비)
        if (messages.isNotEmpty) {
          messages.last.text = "";
          _onStateChanged();
        }
      }

      // 3. Main Model Streaming (General Chat)
      await _streamingTts.startLoading();

      final responseBuffer = StringBuffer();
      final streamingEnabled = AppSettings.instance.streamingResponsesEnabled;

      String fullPrompt;
      final trimmedPrompt = prompt.trim();

      if (isInternalCall) {
        fullPrompt = _buildConversationPrompt(
          messages,
          trimmedPrompt,
          includeSystem: true,
        );
      } else {
        fullPrompt = _buildConversationPrompt(
          messages,
          trimmedPrompt,
          includeSystem: _isFirstMessage,
          replaceLastUser: true,
        );
        if (_isFirstMessage) _isFirstMessage = false;
      }

      final currentAiMsg = messages.last;
      if (isFunctionResult) {
        currentAiMsg.isFunctionResult = true;
      }

      await _service.sendWithStreaming(
        text: fullPrompt,
        onToken: (tok) {
          responseBuffer.write(tok);
          final currentText = responseBuffer.toString();

          if (streamingEnabled) {
            _streamingTts.addText(tok, currentText);
            currentAiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          final finalText = responseBuffer.toString().trim();
          currentAiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;

          _isGenerating = false;
          _onStateChanged();
          if (!streamingEnabled && finalText.isNotEmpty) {
            _streamingTts.addText(finalText, finalText);
          }
          await _streamingTts.onMessageComplete();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      if (messages.isNotEmpty) messages.last.text = 'Error: $e';
      _isGenerating = false;
      _onStateChanged();
      await _announceError('Error: $e');
    }
  }

  // Generalized Function Executor
  Future<void> _handleFunctionExecution(
    FunctionCall call,
    String originalPrompt,
    List<ChatMessage> messages,
  ) async {
    final resultJson = await FunctionCallingService.instance.execute(call);

    final nextPrompt =
        '''
User query: $originalPrompt
Tool Execution: ${call.name}
Arguments: ${call.args}
Result: $resultJson

Instructions:
1. Using the result above, answer the user's question naturally in Korean.
2. If the result indicates an error, politely inform the user.
''';

    if (messages.isNotEmpty && !messages.last.isUser) {
      messages.last.text = '';
      _onStateChanged();
    }

    // Recursive call to generate natural language response
    await sendTextOnly(
      nextPrompt,
      messages,
      isInternalCall: true,
      isFunctionResult: true,
    );
  }

  // Quick action shortcuts
  Future<void> quickAction1(List<ChatMessage> messages) async {
    await _announceStateChange('Describing room');
    // [수정] captureWithCamera 사용
    await captureWithCamera(
      AppSettings.instance.promptDescribeRoom,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> quickAction2(List<ChatMessage> messages) async {
    await _announceStateChange('Analyzing what I can see');
    // [수정] captureWithCamera 사용
    await captureWithCamera(
      AppSettings.instance.promptWhatYouSee,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> quickAction3(List<ChatMessage> messages) async {
    await _announceStateChange('What is this?');
    // [수정] captureWithCamera 사용
    await captureWithCamera(
      AppSettings.instance.promptWhatIsThis,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> quickAction4(List<ChatMessage> messages) async {
    await _announceStateChange('Reading text');
    // [수정] captureWithCamera 사용
    await captureWithCamera(
      AppSettings.instance.promptReadText,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> clearMessages(List<ChatMessage> messages) async {
    try {
      final count = messages.length;
      messages.clear();
      _onStateChanged();
      await _announceStateChange('Cleared $count messages');
    } catch (e) {
      await _announceError('Failed to clear messages: $e');
    }
  }
}
