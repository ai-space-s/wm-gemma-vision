// gemma_vision_chat.dart
// ---------------------------------------------------------------------------
//  Full demo app: vision-based chat with Gemma, camera, TTS & dictation
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'download_page.dart'; // ← for fallback if model init fails

/// ---------------------------------------------------------------------------
///  GEMMA SERVICE (singleton) – loads model once, keeps chat alive
/// ---------------------------------------------------------------------------
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

    // if the plugin doesn't yet have the model installed but we see the file on disk,
    // tell it where to load from
    if (!await _gemma.modelManager.isModelInstalled &&
        File(path).existsSync()) {
      await _gemma.modelManager.setModelPath(path);
    }

    // attempt to create the model; this will throw if the file is corrupt/incomplete
    _model ??= await _gemma.createModel(
      preferredBackend: PreferredBackend.cpu,
      modelType: ModelType.gemmaIt,
      supportImage: true,
      maxTokens: 4096,
      maxNumImages: 1,
    );

    // create or reuse the chat session
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

  Future<String> send({required String text, required File image}) async {
    final bytes = await image.readAsBytes();
    await _chat!.addQueryChunk(
      Message.withImage(text: text, imageBytes: bytes, isUser: true),
    );
    return _chat!.generateChatResponse();
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

/// ---------------------------------------------------------------------------
///  CHAT PAGE – camera feed, transcript bubbles & prompt bar
/// ---------------------------------------------------------------------------
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _service = GemmaService.instance;
  final _msgs = <_Msg>[];
  bool _resetting = false;

  // TTS
  late FlutterTts _tts;

  // Editable settings
  String _systemCtx =
      'Context: user is blind; keep answers concise and informative.';
  double _speechRate = 0.6;

  // Camera
  late CameraController _camera;
  bool _cameraReady = false;

  // Prompt-bar key so we can clear its TextField
  final _promptBarKey = GlobalKey<_PromptBarState>();

  bool _initialising = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // TTS
    _tts = FlutterTts();
    await _tts.setSpeechRate(_speechRate);

    // LLM init with fallback
    try {
      await _service.init();
    } catch (e) {
      // 1) cancel / remove any running download for this model:
      final tasks = await FlutterDownloader.loadTasks() ?? [];
      for (final t in tasks) {
        if (t.filename == 'gemma-3n-E2B-it-int4.task' &&
            t.status != DownloadTaskStatus.complete) {
          // Stop the download and delete its temp file too
          await FlutterDownloader.remove(
            taskId: t.taskId,
            shouldDeleteContent: true,
          );
        }
      }
      // model load failed—delete potentially incomplete file and go back to download
      final dir = await getApplicationDocumentsDirectory();
      final badFile = File('${dir.path}/gemma-3n-E2B-it-int4.task');
      if (await badFile.exists()) {
        await badFile.delete();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DownloadPage()),
      );
      return;
    }

    // Camera
    final cams = await availableCameras();
    _camera = CameraController(
      cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back),
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _camera.initialize();

    if (!mounted) return;
    setState(() {
      _cameraReady = true;
      _initialising = false;
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    _tts.stop();
    super.dispose();
  }

  // Reset UI and chat state
  Future<void> _resetChat() async {
    if (_resetting) return;
    setState(() {
      _resetting = true;
      _msgs.clear();
      _promptBarKey.currentState?.clear();
    });

    await _service.resetChatSession();

    if (mounted) {
      setState(() => _resetting = false);
    }
  }

  // Capture a frame then ask Gemma
  Future<void> _captureAndSend(String userPrompt) async {
    if (!_cameraReady) return;

    try {
      final file = await _safeTakePicture();
      if (file == null) {
        setState(
          () => _msgs.add(_Msg('Camera busy, try again…', isUser: false)),
        );
        return;
      }

      setState(() => _msgs.add(_Msg(userPrompt, isUser: true)));

      final fullPrompt = '$_systemCtx\nUser: $userPrompt';
      final reply = await _service.send(text: fullPrompt, image: file);

      setState(() => _msgs.add(_Msg(reply, isUser: false)));
      await Future.delayed(const Duration(milliseconds: 300));
      await _tts.speak(reply);
    } catch (e) {
      setState(() => _msgs.add(_Msg('Error: $e', isUser: false)));
    }
  }

  // Ensures a valid camera session (avoids “Session closed” crash)
  Future<File?> _safeTakePicture() async {
    if (!_camera.value.isInitialized) {
      try {
        await _camera.initialize();
        setState(() => _cameraReady = true);
      } catch (e) {
        return null;
      }
    }
    if (_camera.value.isTakingPicture) return null;
    final xFile = await _camera.takePicture();
    return File(xFile.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Vision Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New chat',
            onPressed: _resetChat,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 3, child: _CameraPreviewBox(camera: _camera)),
          Expanded(
            flex: 4,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              reverse: false,
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                return _ChatBubble(text: m.text, isUser: m.isUser);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _PromptBar(
              key: _promptBarKey,
              onPrompt: _captureAndSend,
              disabled: _resetting,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final ctxCtl = TextEditingController(text: _systemCtx);
    double tmpRate = _speechRate;

    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctxCtl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'System context'),
              ),
              const SizedBox(height: 16),
              Text('Speech rate: ${tmpRate.toStringAsFixed(2)}'),
              Slider(
                min: 0.5,
                max: 2,
                divisions: 15,
                value: tmpRate,
                onChanged: (v) => setDlg(() => tmpRate = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'ctx': ctxCtl.text.trim(),
                'rate': tmpRate,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (res != null) {
      setState(() {
        _systemCtx = res['ctx'] as String;
        _speechRate = res['rate'] as double;
      });
      await _tts.setSpeechRate(_speechRate);
    }
  }
}

/// ---------------------------------------------------------------------------
///  WIDGETS
/// ---------------------------------------------------------------------------

/// Live camera preview (letter-boxed to fit)
class _CameraPreviewBox extends StatelessWidget {
  final CameraController camera;
  const _CameraPreviewBox({required this.camera});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final ratio = camera.value.aspectRatio;
        var w = constraints.maxWidth;
        var h = w / ratio;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * ratio;
        }
        return Center(
          child: SizedBox(width: w, height: h, child: CameraPreview(camera)),
        );
      },
    );
  }
}

/// Simple message record
class _Msg {
  final String text;
  final bool isUser;
  _Msg(this.text, {required this.isUser});
}

/// Chat bubble
class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext ctx) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    ),
  );
}

/// PROMPT BAR – dictation, custom prompt & quick buttons
class _PromptBar extends StatefulWidget {
  final Future<void> Function(String) onPrompt;
  final bool disabled;
  const _PromptBar({required this.onPrompt, this.disabled = false, super.key});

  @override
  State<_PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends State<_PromptBar> {
  final _ctrl = TextEditingController();
  final SpeechToText _speech = SpeechToText();

  bool _speechEnabled = false;
  bool _listening = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _initialiseSpeech();
  }

  Future<void> _initialiseSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    if (mounted) setState(() {});
  }

  Future<void> _send(String prompt) async {
    if (widget.disabled) return;
    final txt = prompt.trim();
    if (txt.isEmpty || _sending) return;

    if (_listening) {
      _listening = false;
      await _speech.stop();
    }

    _ctrl.clear();
    setState(() => _sending = true);

    try {
      await widget.onPrompt(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleListening() async {
    if (widget.disabled || !_speechEnabled) return;

    if (_listening) {
      _listening = false;
      await _speech.stop();
      if (mounted) setState(() {});
      return;
    }

    await _speech.listen(
      onResult: (val) {
        if (!_listening) return;
        setState(() {
          _ctrl.text = val.recognizedWords;
          _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _ctrl.text.length),
          );
        });
      },
    );
    setState(() => _listening = true);
  }

  @override
  void dispose() {
    _speech.stop();
    _speech.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void clear() => _ctrl.clear();

  @override
  Widget build(BuildContext context) {
    final controlsDisabled = widget.disabled || _sending;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !controlsDisabled,
                  decoration: const InputDecoration(hintText: 'Custom prompt…'),
                  onSubmitted: _send,
                ),
              ),
              IconButton(
                icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                tooltip: _speechEnabled
                    ? (_listening ? 'Stop dictation' : 'Start dictation')
                    : 'Dictation unavailable',
                onPressed: controlsDisabled
                    ? null
                    : (_speechEnabled ? _toggleListening : null),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: controlsDisabled ? null : () => _send(_ctrl.text),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            children: [
              _quick('Describe the room', controlsDisabled),
              _quick('Find an exit', controlsDisabled),
              _quick('Read text', controlsDisabled),
              _quick('Identify obstacles', controlsDisabled),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quick(String label, bool disabled) => ElevatedButton(
    onPressed: disabled ? null : () => _send(label),
    child: Text(label, textAlign: TextAlign.center),
  );
}
