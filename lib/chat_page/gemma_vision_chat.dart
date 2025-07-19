// lib/chat_page/chat_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gemma_chat/download_page/model_download_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/pigeon.g.dart';

import 'services/gemma_service.dart';
import 'services/streaming_tts_service.dart';
import 'services/camera_service.dart';
import 'services/chat_helpers.dart';
import 'services/speech_service.dart';
import 'models/message_models.dart';
import 'models/camera_context.dart';
import 'handlers/keyboard_handler.dart';
import 'widgets/camera_preview.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/prompt_bar.dart';
import 'widgets/settings_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /* ----------------------------------------------------------------- state */
  final _service = GemmaService.instance;
  final _cameraService = CameraService.instance;
  final _msgs = <ChatMessage>[];

  bool _showMessages = false;
  bool _showCamera = true;
  bool _settingsVisible = false;

  late FlutterTts _tts;
  late StreamingTtsService _streamingTts;
  late ChatHelpers _chatHelpers;
  late SpeechService _speechService;
  late KeyboardHandler _keyboardHandler;

  String _systemCtx = 'Answer immediately! Keep answers short.';
  PreferredBackend _backend = PreferredBackend.cpu;

  /* misc */
  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;
  bool _bootstrapping = false; // Add flag to prevent double bootstrap

  /* focus */
  final FocusNode _rootFocus = FocusNode();

  /* -------------------------------------------------------------- lifecycle */
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) {
      debugPrint("[ChatPage] Bootstrap already in progress, skipping...");
      return;
    }

    _bootstrapping = true;

    try {
      debugPrint("[ChatPage] Starting bootstrap...");

      // Initialize TTS
      _tts = FlutterTts();
      await _tts.setSpeechRate(0.5); // Fixed speech rate
      _streamingTts = StreamingTtsService(_tts);
      debugPrint("[ChatPage] TTS initialized");

      // Initialize camera service
      await _cameraService.initialize();
      _cameraService.addListener(() => mounted ? setState(() {}) : null);
      debugPrint("[ChatPage] Camera service initialized");

      // Initialize chat helpers
      _chatHelpers = ChatHelpers(
        service: _service,
        streamingTts: _streamingTts,
        onStateChanged: () => mounted ? setState(() {}) : null,
        showSnackBar: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        },
        systemContext: _systemCtx,
      );
      debugPrint("[ChatPage] Chat helpers initialized");

      // Initialize speech service
      _speechService = SpeechService(
        tts: _tts,
        onStateChanged: () => mounted ? setState(() {}) : null,
        promptBarKey: _promptBarKey,
        isGenerating: () => _chatHelpers.isGenerating,
      );
      await _speechService.initialize();
      debugPrint("[ChatPage] Speech service initialized");

      // Initialize keyboard handler
      _keyboardHandler = KeyboardHandler(
        context: context,
        promptBarKey: _promptBarKey,
        onToggleMessages: () => setState(() => _showMessages = !_showMessages),
        onToggleCamera: () => setState(() => _showCamera = !_showCamera),
        onToggleSettings: _toggleSettings,
        onNewChat: _newChat,
        onQuickAction1: _quickAction1,
        onQuickAction2: _quickAction2,
        onQuickAction3: _quickAction3,
        onQuickAction4: _quickAction4,
      );
      debugPrint("[ChatPage] Keyboard handler initialized");

      // Initialize Gemma service
      debugPrint("[ChatPage] Initializing Gemma service...");
      await _service.init(_backend);
      debugPrint("[ChatPage] Gemma service initialized successfully");

      // Final mounted check
      if (!mounted) {
        debugPrint("[ChatPage] Widget not mounted, skipping UI update");
        return;
      }

      setState(() => _initialising = false);
      _rootFocus.requestFocus();
      debugPrint("[ChatPage] Bootstrap completed successfully");
    } catch (e) {
      debugPrint("[ChatPage] Bootstrap error: $e");
      if (mounted) {
        await _handleInitError();
      }
    } finally {
      _bootstrapping = false;
    }
  }

  /* -------------------------------------------------- first‑launch errors */
  Future<void> _handleInitError() async {
    debugPrint("Handling initialization error...");

    final tasks = await FlutterDownloader.loadTasks() ?? [];
    for (final t in tasks) {
      if (t.filename?.endsWith('.task') == true &&
          t.status != DownloadTaskStatus.complete) {
        await FlutterDownloader.remove(
          taskId: t.taskId,
          shouldDeleteContent: true,
        );
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    for (final fn in [
      '${dir.path}/gemma-3n-E2B-it-int4.task',
      '${dir.path}/gemma-3n-E2B-it-int4.task.tmp',
    ]) {
      final f = File(fn);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    if (!mounted || _redirectedOnError) return;
    _redirectedOnError = true;

    // Use Navigator safely
    try {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ModelDownloadPage()),
      );
    } catch (e) {
      debugPrint("Error navigating to download page: $e");
    }
  }

  /* ---------------------------------------------------------------- dispose */
  @override
  void dispose() {
    _streamingTts.stop();
    _tts.stop();
    _speechService.dispose();
    _rootFocus.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  /* ------------------------------------- camera context helper */
  CameraContext get _cameraContext => CameraContext.fromService(_cameraService);

  /* -------------------- refactored chat helper wrappers */
  Future<void> _newChat() async => _chatHelpers.newChat(_msgs, _promptBarKey);

  Future<void> _captureAndSend(String prompt) async =>
      _chatHelpers.captureAndSend(prompt, _msgs, _cameraContext);

  Future<void> _sendTextOnly(String prompt) async =>
      _chatHelpers.sendTextOnly(prompt, _msgs);

  /* ------------------------ simplified quick actions */
  Future<void> _quickAction1() async =>
      _chatHelpers.quickAction1(_msgs, _cameraContext);

  Future<void> _quickAction2() async =>
      _chatHelpers.quickAction2(_msgs, _cameraContext);

  Future<void> _quickAction3() async =>
      _chatHelpers.quickAction3(_msgs, _cameraContext);

  Future<void> _quickAction4() async =>
      _chatHelpers.quickAction4(_msgs, _cameraContext);

  /* ------------------------ camera preview */
  Widget _cameraPreview() {
    if (_cameraService.cameraInitialized &&
        !_cameraService.cameraError &&
        _cameraService.camera != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CameraPreviewBox(camera: _cameraService.camera!),
      );
    }
    return _cameraPlaceholder(
      _cameraService.cameraError ? 'Camera Error' : 'Camera Initializing…',
    );
  }

  Widget _cameraPlaceholder(String msg) => Container(
    decoration: BoxDecoration(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    ),
  );

  /* -------------------------------------------------------------- build UI */
  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing Gemma…', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Shortcuts(
      shortcuts: _keyboardHandler.shortcuts,
      child: Actions(
        actions: _keyboardHandler.actions,
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _speechService.handleFocusKey,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Gemma Vision Chat'),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'New Chat',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: _chatHelpers.resetting ? null : _newChat,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  label: const Text(
                    'Settings',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: _toggleSettings,
                ),
              ],
            ),
            body: Column(
              children: [
                /* Status bar */
                if (_chatHelpers.isGenerating || _chatHelpers.isSpeaking)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.shade100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _chatHelpers.isGenerating
                              ? (_chatHelpers.isSpeaking
                                    ? 'Generating and speaking…'
                                    : 'Generating response…')
                              : 'Speaking…',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                /* show / hide buttons */
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            setState(() => _showCamera = !_showCamera),
                        icon: Icon(
                          _showCamera ? Icons.visibility_off : Icons.visibility,
                        ),
                        label: Text(
                          _showCamera ? 'Hide Camera' : 'Show Camera',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () =>
                            setState(() => _showMessages = !_showMessages),
                        icon: Icon(
                          _showMessages
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                        ),
                        label: Text(
                          _showMessages ? 'Hide Messages' : 'Show Messages',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                /* main content */
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: Column(
                      children: [
                        if (_showCamera)
                          Expanded(
                            flex: _showMessages ? 1 : 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _cameraPreview(),
                            ),
                          ),
                        if (_showMessages)
                          Expanded(
                            flex: _showCamera ? 1 : 2,
                            child: Container(
                              margin: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _msgs.length,
                                itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ChatBubble(msg: _msgs[i]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                /* Prompt bar (includes mic button) */
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: PromptBar(
                    key: _promptBarKey,
                    onPromptWithPhoto: _captureAndSend,
                    onPromptTextOnly: _sendTextOnly,
                    disabled:
                        _chatHelpers.resetting || _chatHelpers.isGenerating,
                    speechEnabled: _speechService.speechEnabled,
                    listening: _speechService.listening,
                    onToggleListening: _speechService.toggleDictation,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* ---------------- toggle settings dialog ---------------- */
  Future<void> _toggleSettings() async {
    if (_settingsVisible) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _settingsVisible = false);
      return;
    }

    setState(() => _settingsVisible = true);

    await showSettingsDialog(
      context: context,
      systemCtx: _systemCtx,
      backend: _backend,
      onDismiss: () => setState(() => _settingsVisible = false),
      onSave: (newCtx, newBackend) async {
        setState(() {
          _systemCtx = newCtx;
          _chatHelpers.updateSystemContext(_systemCtx);

          if (_backend != newBackend) {
            _backend = newBackend;
            _msgs.clear();
            _initialising = true;
            _bootstrapping = false; // Reset bootstrap flag
            _redirectedOnError = false;
            _bootstrap();
          }
        });
      },
    );
  }
}
