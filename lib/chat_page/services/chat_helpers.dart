// lib/chat_page/services/chat_helpers.dart
// Ultra-optimized version with throttling applied to your architecture

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/camera_context.dart';
import '../models/message_models.dart';
import '../widgets/prompt_bar.dart';
import '../config/system_prompts.dart';
import 'gemma_service.dart';
import 'speech_service.dart';
import 'streaming_tts_service.dart';

class ChatHelpers {
  final GemmaService _service;
  final StreamingTtsService _streamingTts;
  final SpeechService _speechService;
  final VoidCallback _onStateChanged;
  final Function(String) _showSnackBar;

  String _systemCtx;
  bool _resetting = false;
  bool _isGenerating = false;

  ChatHelpers({
    required GemmaService service,
    required StreamingTtsService streamingTts,
    required SpeechService speechService,
    required VoidCallback onStateChanged,
    required Function(String) showSnackBar,
    required String systemContext,
  }) : _service = service,
       _streamingTts = streamingTts,
       _speechService = speechService,
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

  Future<void> newChat(
    List<ChatMessage> messages,
    GlobalKey<PromptBarState>? promptBarKey,
  ) async {
    if (_resetting) return;

    _streamingTts.reset();
    _resetting = true;
    _onStateChanged();

    messages.clear();
    promptBarKey?.currentState?.clear();

    await _service.resetChatSession();

    _resetting = false;
    _onStateChanged();
    _showSnackBar('New chat started');
  }

  Future<void> captureAndSend(
    String prompt,
    List<ChatMessage> messages,
    CameraContext cameraContext,
  ) async {
    if (!cameraContext.cameraInitialized || cameraContext.cameraError) {
      messages.add(ChatMessage('Camera not available', isUser: false));
      _onStateChanged();
      return;
    }

    try {
      await _speechService.playWooshSound();
      await _speechService.announceMessageType(true);
      await Future.delayed(const Duration(milliseconds: 200));

      _isGenerating = true;
      _onStateChanged();

      await _streamingTts.startLoading();
      final img = await _safeTakePicture(cameraContext.camera);

      if (img == null) {
        await _streamingTts.stopLoading();
        messages.add(ChatMessage('Camera busy; try again…', isUser: false));
        _isGenerating = false;
        _onStateChanged();
        return;
      }

      messages.add(ChatMessage(prompt, isUser: true));
      _onStateChanged();

      final aiMsg = ChatMessage('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      // 🔑 ULTRA-FAST OPTIMIZATION: Use local variables for throttling
      final responseBuffer = StringBuffer();
      int tokenCounter = 0;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        image: img,
        onToken: (tok) {
          // 🔑 Build response incrementally with StringBuffer
          responseBuffer.write(tok);
          tokenCounter++;

          // 🔑 THROTTLE: Only update UI and TTS every 3 tokens (adjust as needed)
          if (tokenCounter % 3 == 0) {
            final currentText = responseBuffer.toString();
            _streamingTts.addText(
              tok,
              aiMsg.text,
            ); // Only process TTS occasionally
            aiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          // 🔑 Final update with complete text
          final finalText = responseBuffer.toString();
          aiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          await _streamingTts.onMessageComplete();
          _onStateChanged();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      messages.add(ChatMessage('Error: $e', isUser: false));
      _isGenerating = false;
      _onStateChanged();
    }
  }

  Future<void> sendTextOnly(String prompt, List<ChatMessage> messages) async {
    try {
      await _speechService.playWooshSound();
      await _speechService.announceMessageType(false);
      await Future.delayed(const Duration(milliseconds: 200));

      _isGenerating = true;
      _onStateChanged();

      await _streamingTts.startLoading();
      messages.add(ChatMessage(prompt, isUser: true));
      _onStateChanged();

      final aiMsg = ChatMessage('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      // 🔑 ULTRA-FAST OPTIMIZATION: Use local variables for throttling
      final responseBuffer = StringBuffer();
      int tokenCounter = 0;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        onToken: (tok) {
          // 🔑 Build response incrementally with StringBuffer
          responseBuffer.write(tok);
          tokenCounter++;

          // 🔑 THROTTLE: Only update UI and TTS every 3 tokens
          if (tokenCounter % 3 == 0) {
            final currentText = responseBuffer.toString();
            _streamingTts.addText(tok, aiMsg.text); // Throttled TTS processing
            aiMsg.text = currentText;
            _onStateChanged();
          }
        },
        onComplete: (stats) async {
          // 🔑 Final update with complete text
          final finalText = responseBuffer.toString();
          aiMsg
            ..text = finalText
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          await _streamingTts.onMessageComplete();
          _onStateChanged();
        },
      );
    } catch (e) {
      await _streamingTts.stopLoading();
      messages.add(ChatMessage('Error: $e', isUser: false));
      _isGenerating = false;
      _onStateChanged();
    }
  }

  Future<File?> _safeTakePicture(CameraController? camera) async {
    if (camera == null || !camera.value.isInitialized) return null;
    if (camera.value.isTakingPicture) return null;

    try {
      final x = await camera.takePicture();
      return File(x.path);
    } catch (e) {
      debugPrint('Camera picture error: $e');
      return null;
    }
  }

  Future<void> quickAction1(List<ChatMessage> m, CameraContext c) async =>
      captureAndSend(SystemPrompts.describeRoom, m, c);
  Future<void> quickAction2(List<ChatMessage> m, CameraContext c) async =>
      captureAndSend(SystemPrompts.tellMeWhatYouSee, m, c);
  Future<void> quickAction3(List<ChatMessage> m, CameraContext c) async =>
      captureAndSend(SystemPrompts.findExit, m, c);
  Future<void> quickAction4(List<ChatMessage> m, CameraContext c) async =>
      captureAndSend(SystemPrompts.readText, m, c);
}
