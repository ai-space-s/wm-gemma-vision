import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gemma_chat/models/message_models.dart';
import 'package:gemma_chat/widgets/prompt_bar.dart';
import 'package:path_provider/path_provider.dart';

import 'gemma_service.dart';
import 'streaming_tts_service.dart';

class ChatHelpers {
  final GemmaService _service;
  final StreamingTtsService _streamingTts;
  final VoidCallback _onStateChanged;
  final Function(String) _showSnackBar;

  String _systemCtx;
  bool _resetting = false;
  bool _isGenerating = false;
  bool _isSpeaking = false;

  ChatHelpers({
    required GemmaService service,
    required StreamingTtsService streamingTts,
    required VoidCallback onStateChanged,
    required Function(String) showSnackBar,
    required String systemContext,
  }) : _service = service,
       _streamingTts = streamingTts,
       _onStateChanged = onStateChanged,
       _showSnackBar = showSnackBar,
       _systemCtx = systemContext;

  // Getters for state
  bool get resetting => _resetting;
  bool get isGenerating => _isGenerating;
  bool get isSpeaking => _isSpeaking;
  String get systemContext => _systemCtx;

  // Setters for state
  void updateSystemContext(String newContext) {
    _systemCtx = newContext;
  }

  /// Starts a new chat session
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

  /// Captures an image and sends it with a prompt
  Future<void> captureAndSend(
    String prompt,
    List<ChatMessage> messages,
    CameraSource cameraSource,
    bool cameraInitialized,
    bool cameraError,
    CameraController? camera,
    InAppWebViewController? ipCameraWebView,
    String ipCameraUrl,
  ) async {
    if (cameraSource == CameraSource.phone &&
        (!cameraInitialized || cameraError)) {
      messages.add(ChatMessage('Camera not available', isUser: false));
      _onStateChanged();
      return;
    }

    try {
      _isGenerating = true;
      _isSpeaking = false;
      _onStateChanged();

      File? img;
      if (cameraSource == CameraSource.phone) {
        img = await _safeTakePicture(camera);
      } else {
        img = await _captureIpCameraImage(ipCameraWebView);
      }

      if (img == null) {
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

      String prev = '';
      bool first = false;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        image: img,
        onToken: (tok) {
          if (!first) {
            first = true;
            _isSpeaking = true;
            _onStateChanged();
          }
          _streamingTts.addText(tok, prev);
          prev = tok;
          aiMsg.text = tok;
          _onStateChanged();
        },
        onComplete: (stats) {
          aiMsg
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          _isSpeaking = false;
          _onStateChanged();
        },
      );
    } catch (e) {
      messages.add(ChatMessage('Error: $e', isUser: false));
      _isGenerating = false;
      _isSpeaking = false;
      _onStateChanged();
    }
  }

  /// Sends a text-only message
  Future<void> sendTextOnly(String prompt, List<ChatMessage> messages) async {
    try {
      _isGenerating = true;
      _isSpeaking = false;
      _onStateChanged();

      messages.add(ChatMessage(prompt, isUser: true));
      _onStateChanged();

      final aiMsg = ChatMessage('', isUser: false, isStreaming: true);
      messages.add(aiMsg);
      _onStateChanged();

      String prev = '';
      bool first = false;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        onToken: (tok) {
          if (!first) {
            first = true;
            _isSpeaking = true;
            _onStateChanged();
          }
          _streamingTts.addText(tok, prev);
          prev = tok;
          aiMsg.text = tok;
          _onStateChanged();
        },
        onComplete: (stats) {
          aiMsg
            ..isStreaming = false
            ..stats = stats;
          _isGenerating = false;
          _isSpeaking = false;
          _onStateChanged();
        },
      );
    } catch (e) {
      messages.add(ChatMessage('Error: $e', isUser: false));
      _isGenerating = false;
      _isSpeaking = false;
      _onStateChanged();
    }
  }

  /// Safely takes a picture with the camera
  Future<File?> _safeTakePicture(CameraController? camera) async {
    if (camera == null || !camera.value.isInitialized) {
      return null;
    }

    // Check if camera is already taking a picture
    if (camera.value.isTakingPicture) {
      debugPrint('Camera is already taking a picture');
      return null;
    }

    try {
      final x = await camera.takePicture();
      return File(x.path);
    } catch (e) {
      debugPrint('Camera picture error: $e');
      return null;
    }
  }

  /// Captures an image from IP camera
  Future<File?> _captureIpCameraImage(InAppWebViewController? webView) async {
    try {
      if (webView != null) {
        final bytes = await webView.takeScreenshot();
        if (bytes != null) {
          final tmp = await getTemporaryDirectory();
          final f = File('${tmp.path}/ip_cam.jpg');
          await f.writeAsBytes(bytes);
          return f;
        }
      }
    } catch (e) {
      debugPrint('IP cam screenshot error: $e');
    }
    return null;
  }

  /// Quick action helpers
  Future<void> quickAction1(
    List<ChatMessage> messages,
    CameraSource cameraSource,
    bool cameraInitialized,
    bool cameraError,
    CameraController? camera,
    InAppWebViewController? ipCameraWebView,
    String ipCameraUrl,
  ) async {
    await captureAndSend(
      'Describe the room',
      messages,
      cameraSource,
      cameraInitialized,
      cameraError,
      camera,
      ipCameraWebView,
      ipCameraUrl,
    );
  }

  Future<void> quickAction2(
    List<ChatMessage> messages,
    CameraSource cameraSource,
    bool cameraInitialized,
    bool cameraError,
    CameraController? camera,
    InAppWebViewController? ipCameraWebView,
    String ipCameraUrl,
  ) async {
    await captureAndSend(
      'Tell me what you see',
      messages,
      cameraSource,
      cameraInitialized,
      cameraError,
      camera,
      ipCameraWebView,
      ipCameraUrl,
    );
  }

  Future<void> quickAction3(
    List<ChatMessage> messages,
    CameraSource cameraSource,
    bool cameraInitialized,
    bool cameraError,
    CameraController? camera,
    InAppWebViewController? ipCameraWebView,
    String ipCameraUrl,
  ) async {
    await captureAndSend(
      'Find an exit',
      messages,
      cameraSource,
      cameraInitialized,
      cameraError,
      camera,
      ipCameraWebView,
      ipCameraUrl,
    );
  }

  Future<void> quickAction4(
    List<ChatMessage> messages,
    CameraSource cameraSource,
    bool cameraInitialized,
    bool cameraError,
    CameraController? camera,
    InAppWebViewController? ipCameraWebView,
    String ipCameraUrl,
  ) async {
    await captureAndSend(
      'Read text',
      messages,
      cameraSource,
      cameraInitialized,
      cameraError,
      camera,
      ipCameraWebView,
      ipCameraUrl,
    );
  }
}
