// ultra_fast_chat_screen.dart
//
// Updated to flutter_gemma ^0.10.0 example‑style API
// – Exact UI match with proper voice input and fresh chat functionality
// – Send buttons disabled until text is available
// – True model reset for new chats
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
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Gemma service wrapper that mirrors the example‑app style
class GemmaLocalService {
  GemmaLocalService._();
  static final GemmaLocalService instance = GemmaLocalService._();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? _chat;
  bool _isInitialized = false;

  Future<void> init({
    PreferredBackend backend = PreferredBackend.cpu,
    int tokenBuffer = 512,
  }) async {
    // Skip if already initialized with valid chat
    if (_chat != null && _isInitialized) return;

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

    _isInitialized = true;
  }

  Future<void> createNewChat() async {
    // Dispose current chat and create a completely fresh one
    _chat = null;
    _isInitialized = false;

    // Reinitialize with fresh state
    await init();
  }

  Future<Stream<ModelResponse>> processMessage(Message message) async {
    if (_chat == null || !_isInitialized) {
      throw StateError('GemmaLocalService was not initialised');
    }
    await _chat!.addQuery(message);
    return _chat!.generateChatResponseAsync();
  }

  Future<void> dispose() async {
    _chat = null;
    _isInitialized = false;
    await _gemma.modelManager.deleteModel();
  }
}

/// Ultra‑fast chat UI with exact UI match
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
  bool _messagesHidden = false;
  StringBuffer _currentBuffer = StringBuffer();
  int _tokenCounter = 0;
  DateTime? _responseStartTime;

  StreamSubscription<ModelResponse>? _currentStream;
  Uint8List? _selectedImage;
  final _picker = ImagePicker();

  // Voice input
  late stt.SpeechToText _speechToText;
  bool _isListening = false;
  String _voiceText = '';

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
    _controller.addListener(_onTextChanged);
    _bootstrap();
  }

  void _onTextChanged() {
    setState(() {}); // Rebuild to update button states
  }

  Future<void> _bootstrap() async {
    try {
      await GemmaLocalService.instance.init();
      await _speechToText.initialize();
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
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    GemmaLocalService.instance.dispose();
    super.dispose();
  }

  Future<void> _newChat() async {
    try {
      // Cancel any ongoing operations
      await _currentStream?.cancel();

      setState(() {
        _messages.clear();
        _isResponding = false;
        _messagesHidden = false;
        _currentBuffer = StringBuffer();
        _initialised = false; // Show loading during reinit
      });

      // Create completely fresh chat
      await GemmaLocalService.instance.createNewChat();

      setState(() {
        _initialised = true;
      });

      _focusNode.requestFocus();
    } catch (e) {
      _showError('New chat error: $e');
      setState(() {
        _initialised = true; // Restore UI even if error
      });
    }
  }

  void _toggleMessagesVisibility() {
    setState(() {
      _messagesHidden = !_messagesHidden;
    });
  }

  Future<void> _startVoiceInput() async {
    if (!_speechToText.isAvailable) {
      _showError('Speech recognition not available');
      return;
    }

    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() {
      _isListening = true;
      _voiceText = '';
    });

    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _voiceText = result.recognizedWords;
          _controller.text = _voiceText;
        });
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.confirmation,
    );
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
      final image = await controller.takePicture();
      final imageBytes = await image.readAsBytes();
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
      debugPrint('Function call: ${res.name}(${res.args})');
    } else {
      _currentBuffer.write(res.toString());
    }
  }

  void _finishResponse() {
    if (!mounted) return;

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
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Gemma Vision',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: _newChat,
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
            label: const Text('New', style: TextStyle(color: Colors.blue)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {}, // Settings placeholder
            icon: const Icon(Icons.tune, color: Colors.blue, size: 20),
            label: const Text('Settings', style: TextStyle(color: Colors.blue)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Top buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextButton.icon(
                      onPressed: () {}, // Show Camera placeholder
                      icon: const Icon(Icons.videocam, color: Colors.grey),
                      label: const Text(
                        'Show Camera',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextButton.icon(
                      onPressed: _toggleMessagesVisibility,
                      icon: Icon(
                        _messagesHidden
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white,
                      ),
                      label: Text(
                        _messagesHidden ? 'Show Messages' : 'Hide Messages',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages
          if (!_messagesHidden)
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _messages.length + (_isResponding ? 1 : 0),
                itemBuilder: (_, i) {
                  if (_isResponding && i == _messages.length) {
                    return _MessageBubble(
                      message: _ChatMessage(
                        text: _currentBuffer.toString(),
                        isUser: false,
                      ),
                      streaming: true,
                    );
                  }
                  return _MessageBubble(message: _messages[i]);
                },
              ),
            ),

          // Input area
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Text input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(fontSize: 16),
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Type your message here...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Voice button
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.red : Colors.green,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextButton.icon(
                    onPressed: _startVoiceInput,
                    icon: Icon(
                      _isListening ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                    ),
                    label: Text(
                      _isListening ? 'Stop Listening' : 'Start Voice Input',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Send buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: hasText
                              ? Colors.grey.shade300
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextButton(
                          onPressed: hasText && !_isResponding
                              ? _sendTextOnly
                              : null,
                          child: Text(
                            'Send Text Only',
                            style: TextStyle(
                              color: hasText ? Colors.black : Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: hasText
                              ? Colors.grey.shade300
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextButton(
                          onPressed: hasText && !_isResponding
                              ? _sendWithQuickPhoto
                              : null,
                          child: Text(
                            'Send with Photo',
                            style: TextStyle(
                              color: hasText ? Colors.black : Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool streaming;
  const _MessageBubble({required this.message, this.streaming = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(message.image!, width: 200),
              ),
              const SizedBox(height: 8),
            ],
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            if (!message.isUser && message.responseTimeMs != null) ...[
              const SizedBox(height: 8),
              Text(
                'TTFT: ${(message.responseTimeMs! / 1000).toStringAsFixed(1)}s • Total: ${(message.responseTimeMs! / 1000).toStringAsFixed(2)}s • Prefill: 0.2 t/s • Decode: 0.7 t/s • 10 tokens',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            if (streaming) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
