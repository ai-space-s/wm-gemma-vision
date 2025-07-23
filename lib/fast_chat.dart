// ultra_fast_chat_screen.dart
//
// Updated to flutter_gemma ^0.10.0 example‑style API
// – uses ModelResponse (TextResponse, FunctionCallResponse)
// – throttles UI rebuilds
// – service separated into GemmaLocalService
// – Added dual send buttons: text-only and quick photo+text
// – Auto camera capture without affecting response speed
//
// Add this to your lib/ folder.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';

/// Gemma service wrapper that mirrors the example‑app style
class GemmaLocalService {
  GemmaLocalService._();
  static final GemmaLocalService instance = GemmaLocalService._();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? _chat;

  Future<void> init({
    PreferredBackend backend = PreferredBackend.cpu,
    int tokenBuffer = 512,
  }) async {
    if (_chat != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

    if (!await _gemma.modelManager.isModelInstalled) {
      await _gemma.modelManager.setModelPath(path);
    }

    final model = await _gemma.createModel(
      modelType: ModelType.gemmaIt,
      preferredBackend: backend,
      supportImage: true,
      maxTokens: 4096,
      maxNumImages: 1,
    );

    _chat = await model.createChat(
      temperature: 1.0,
      randomSeed: 1,
      topK: 64,
      topP: 0.95,
      supportImage: true,
      tokenBuffer: tokenBuffer,
    );
  }

  Future<Stream<ModelResponse>> processMessage(Message message) async {
    if (_chat == null) {
      throw StateError('GemmaLocalService was not initialised');
    }
    await _chat!.addQuery(message);
    return _chat!.generateChatResponseAsync();
  }

  Future<void> dispose() async {
    _chat = null;
    await _gemma.modelManager.deleteModel();
  }
}

/// Ultra‑fast chat UI that consumes ModelResponse streams
class UltraFastChatScreen extends StatefulWidget {
  const UltraFastChatScreen({super.key});

  @override
  State<UltraFastChatScreen> createState() => _UltraFastChatScreenState();
}

class _UltraFastChatScreenState extends State<UltraFastChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _messages = <_ChatMessage>[];

  bool _initialised = false;
  bool _isResponding = false;
  StringBuffer _currentBuffer = StringBuffer();
  int _tokenCounter = 0;
  DateTime? _responseStartTime;

  StreamSubscription<ModelResponse>? _currentStream;
  Uint8List? _selectedImage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await GemmaLocalService.instance.init();
      if (mounted) {
        setState(() => _initialised = true);
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) _showError('Init error: $e');
    }
  }

  @override
  void dispose() {
    _currentStream?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    GemmaLocalService.instance.dispose();
    super.dispose();
  }

  Future<void> _sendTextOnly() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await _sendMessage(text, null);
  }

  Future<void> _sendWithQuickPhoto() async {
    final text = _controller.text.trim();

    if (kIsWeb) {
      _showError('Camera not supported on web');
      return;
    }

    try {
      // Fast camera initialization and capture
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No camera available');
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      // Take picture immediately
      final image = await controller.takePicture();
      final imageBytes = await image.readAsBytes();

      // Dispose camera immediately to free resources
      await controller.dispose();

      await _sendMessage(text, imageBytes);
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  Future<void> _sendMessage(String text, Uint8List? imageBytes) async {
    if (text.isEmpty && imageBytes == null) return;

    final userMsg = _ChatMessage(text: text, isUser: true, image: imageBytes);
    setState(() {
      _messages.add(userMsg);
      _isResponding = true;
      _currentBuffer = StringBuffer();
      _tokenCounter = 0;
      _responseStartTime = DateTime.now();
    });
    _controller.clear();
    _selectedImage = null;
    _scrollToBottom();

    await _currentStream?.cancel();

    final msg = imageBytes != null
        ? Message.withImage(text: text, imageBytes: imageBytes, isUser: true)
        : Message.text(text: text, isUser: true);

    try {
      final stream = await GemmaLocalService.instance.processMessage(msg);
      _currentStream = stream.listen(
        _handleModelResponse,
        onDone: _finishResponse,
        onError: (e) {
          _showError('Gemma error: $e');
          _finishResponse();
        },
      );
    } catch (e) {
      _showError('Send error: $e');
      _finishResponse();
    }
  }

  void _handleModelResponse(ModelResponse res) {
    if (!mounted) return;

    if (res is TextResponse) {
      _currentBuffer.write(res.token);
      _tokenCounter++;
      if (_tokenCounter % 5 == 0) {
        setState(() {});
        _scrollToBottom();
      }
    } else if (res is FunctionCallResponse) {
      // Handle function call – you can adapt this to your app
      debugPrint('Function call: ${res.name}(${res.args})');
    } else {
      // Fallback for legacy String tokens
      _currentBuffer.write(res.toString());
    }
  }

  void _finishResponse() {
    if (!mounted) return;

    // Calculate response time
    final responseTime = _responseStartTime != null
        ? DateTime.now().difference(_responseStartTime!).inMilliseconds
        : 0;

    final botMsg = _ChatMessage(
      text: _currentBuffer.toString(),
      isUser: false,
      responseTimeMs: responseTime,
    );
    setState(() {
      _messages.add(botMsg);
      _isResponding = false;
      _responseStartTime = null;
    });
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    if (kIsWeb) return _showError('Image pick not supported on web');
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (img != null) {
      _selectedImage = await img.readAsBytes();
      setState(() {});
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (!_initialised) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0b1426),
      appBar: AppBar(
        title: const Text('Ultra‑Fast Chat'),
        backgroundColor: const Color(0xFF1a2332),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length + (_isResponding ? 1 : 0),
              itemBuilder: (_, i) {
                if (_isResponding && i == _messages.length) {
                  return _Bubble(
                    message: _ChatMessage(
                      text: _currentBuffer.toString(),
                      isUser: false,
                    ),
                    streaming: true,
                  );
                }
                return _Bubble(message: _messages[i]);
              },
            ),
          ),
          _InputBar(
            controller: _controller,
            focus: _focusNode,
            onSendText: _isResponding ? null : _sendTextOnly,
            onSendWithPhoto: _isResponding ? null : _sendWithQuickPhoto,
            onPickImage: _isResponding ? null : _pickImage,
            hasImage: _selectedImage != null,
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.onSendText,
    required this.onSendWithPhoto,
    required this.onPickImage,
    required this.hasImage,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback? onSendText;
  final VoidCallback? onSendWithPhoto;
  final VoidCallback? onPickImage;
  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1a2332),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.image,
              color: hasImage ? Colors.blue : Colors.white70,
            ),
            onPressed: onPickImage,
            tooltip: 'Pick from gallery',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              onSubmitted: (_) => onSendText?.call(),
              textInputAction: TextInputAction.send,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Color(0xFF2a3441),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Text-only send button
          IconButton(
            icon: _SendIcon(onSendText != null, Icons.send),
            onPressed: onSendText,
            tooltip: 'Send text',
          ),
          // Quick photo + text send button
          IconButton(
            icon: _SendIcon(onSendWithPhoto != null, Icons.camera_alt),
            onPressed: onSendWithPhoto,
            tooltip: 'Auto photo + send',
          ),
        ],
      ),
    );
  }
}

class _SendIcon extends StatelessWidget {
  const _SendIcon(this.enabled, this.icon);
  final bool enabled;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return enabled
        ? Icon(icon, color: Colors.white)
        : const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final Uint8List? image;
  final int? responseTimeMs;
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.image,
    this.responseTimeMs,
  });
}

class _Bubble extends StatelessWidget {
  final _ChatMessage message;
  final bool streaming;
  const _Bubble({required this.message, this.streaming = false});

  @override
  Widget build(BuildContext context) {
    final bg = message.isUser ? Colors.blue : const Color(0xFF2a3441);
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(message.image!, width: 200),
              ),
            if (message.text.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      message.text,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (streaming) ...[
                    const SizedBox(width: 4),
                    const SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(strokeWidth: 1),
                    ),
                  ],
                ],
              ),
            // Show response time for bot messages
            if (!message.isUser && message.responseTimeMs != null) ...[
              const SizedBox(height: 4),
              Text(
                '${(message.responseTimeMs! / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
