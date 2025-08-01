// lib/chat_page/services/chat_helpers.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/message_models.dart';
import '../widgets/prompt_bar.dart';
import '../config/system_prompts.dart';
import 'gemma_service.dart';
import 'speech_service.dart';
import 'streaming_tts_service.dart';
import 'text_recognition_service.dart';

class ChatHelpers {
  final GemmaService _service;
  final StreamingTtsService _streamingTts;
  final SpeechService _speechService;
  final TextRecognitionService _textRecognition;
  final VoidCallback _onStateChanged;
  final Function(String) _showSnackBar;

  String _systemCtx;
  bool _resetting = false;
  bool _isGenerating = false;

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

  Future<void> _announceError(String error) async {
    try {
      final cleanError = error
          .replaceAll('Exception:', '')
          .replaceAll('Error:', '')
          .replaceAll('_', ' ')
          .trim();
      await _speechService.speak('Error: $cleanError');
    } catch (e) {
      // Silent fallback
    }
  }

  Future<void> _announceStateChange(String message) async {
    try {
      await _speechService.speak(message);
    } catch (e) {
      // Silent fallback
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

      _resetting = false;
      _onStateChanged();

      await _announceStateChange('New chat ready');
    } catch (e) {
      _resetting = false;
      _onStateChanged();

      final errorMsg = 'Failed to start new chat: $e';
      _showSnackBar(errorMsg);
      await _announceError(errorMsg);
    }
  }

  Future<void> showMessages(List<ChatMessage> messages, bool show) async {
    try {
      if (show) {
        await _announceStateChange('Showing ${messages.length} messages');
      } else {
        await _announceStateChange('Hiding messages');
      }
    } catch (e) {
      await _announceError('Failed to toggle message visibility');
    }
  }

  Future<File?> _captureWithEfficientCamera() async {
    if (kIsWeb) {
      throw Exception('Camera not supported on web');
    }

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

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

  Future<void> captureAndSend(
    String prompt,
    List<ChatMessage> messages, {
    bool isQuickAction = false,
  }) async {
    try {
      final imageFile = await _captureWithEfficientCamera();

      final userMsg = ChatMessage.withImageFile(
        prompt,
        isUser: true,
        imageFile: imageFile,
      );
      messages.add(userMsg);
      _onStateChanged();

      final aiMsg = ChatMessage.text('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      await _speechService.playWooshSound();

      // Only announce message type if it's not a quick action
      if (!isQuickAction) {
        await _speechService.announceMessageType(true);
      }

      _isGenerating = true;
      _onStateChanged();

      await _streamingTts.startLoading();

      String extractedText = '';
      try {
        extractedText = await _textRecognition.extractTextFromImage(imageFile!);
        // if (extractedText.isNotEmpty) {
        //   _showSnackBar('Text detected in image');
        // }
      } catch (e) {
        await _announceError('Text recognition failed: $e');
      }

      String enhancedPrompt = prompt;
      if (extractedText.isNotEmpty) {
        enhancedPrompt = '''$prompt

[TEXT DETECTED IN IMAGE: $extractedText]''';
      }

      final responseBuffer = StringBuffer();
      int tokenCounter = 0;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $enhancedPrompt',
        image: imageFile,
        onToken: (tok) {
          responseBuffer.write(tok);
          tokenCounter++;

          final currentText = responseBuffer.toString();
          _streamingTts.addText(tok, currentText);

          if (tokenCounter % 3 == 0) {
            aiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          final finalText = responseBuffer.toString();
          aiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          _onStateChanged();
          await _streamingTts.onMessageComplete();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      final errorMsg = 'Failed to process image and text: $e';

      if (messages.isEmpty || !messages.last.isUser) {
        messages.add(ChatMessage.text('Error: $e', isUser: false));
      } else {
        final lastAiIndex = messages.lastIndexWhere((m) => !m.isUser);
        if (lastAiIndex != -1) {
          messages[lastAiIndex] = ChatMessage.text('Error: $e', isUser: false);
        } else {
          messages.add(ChatMessage.text('Error: $e', isUser: false));
        }
      }
      _isGenerating = false;
      _onStateChanged();
      await _announceError(errorMsg);
    }
  }

  Future<void> sendTextOnly(String prompt, List<ChatMessage> messages) async {
    try {
      // Add user message immediately for instant feedback
      messages.add(ChatMessage.text(prompt, isUser: true));
      _onStateChanged();

      // Add placeholder AI message immediately
      final aiMsg = ChatMessage.text('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      // Now start the actual processing
      await _speechService.playWooshSound();

      await _speechService.announceMessageType(false);

      _isGenerating = true;
      _onStateChanged();

      await _streamingTts.startLoading();

      // Ultra-fast optimization: Use local variables for throttling
      final responseBuffer = StringBuffer();
      int tokenCounter = 0;

      final fullPrompt = '$_systemCtx\nUser: $prompt';

      await _service.sendWithStreaming(
        text: fullPrompt,
        onToken: (tok) {
          // Build response incrementally with StringBuffer
          responseBuffer.write(tok);
          tokenCounter++;

          // Throttle: Only update UI every 3 tokens, but always pass to TTS
          final currentText = responseBuffer.toString();

          _streamingTts.addText(tok, currentText);

          if (tokenCounter % 3 == 0) {
            aiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          // Final update with complete text
          final finalText = responseBuffer.toString();

          aiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          _onStateChanged(); // Update UI with final text

          await _streamingTts.onMessageComplete();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      final errorMsg = 'Failed to send text message: $e';
      messages.add(ChatMessage.text('Error: $e', isUser: false));
      _isGenerating = false;
      _onStateChanged();
      await _announceError(errorMsg);
    }
  }

  Future<void> quickAction1(List<ChatMessage> messages) async {
    await _announceStateChange('Describing room');
    await captureAndSend(
      SystemPrompts.describeRoom,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> quickAction2(List<ChatMessage> messages) async {
    await _announceStateChange('Analyzing what I can see');
    await captureAndSend(
      SystemPrompts.tellMeWhatYouSee,
      messages,
      isQuickAction: true,
    );
  }

  Future<void> quickAction3(List<ChatMessage> messages) async {
    await _announceStateChange('Looking for exit');
    await captureAndSend(SystemPrompts.findExit, messages, isQuickAction: true);
  }

  Future<void> quickAction4(List<ChatMessage> messages) async {
    await _announceStateChange('Reading text');
    await captureAndSend(SystemPrompts.readText, messages, isQuickAction: true);
  }

  Future<void> clearMessages(List<ChatMessage> messages) async {
    try {
      final messageCount = messages.length;
      messages.clear();
      _onStateChanged();
      await _announceStateChange('Cleared $messageCount messages');
    } catch (e) {
      await _announceError('Failed to clear messages: $e');
    }
  }
}
