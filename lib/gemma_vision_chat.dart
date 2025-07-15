import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_gemma/pigeon.g.dart';

import 'services/gemma_service.dart';
import 'services/streaming_tts_service.dart';
import 'services/camera_service.dart';
import 'models/message_models.dart';
import 'widgets/camera_preview.dart';
import 'widgets/ip_camera_preview.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/prompt_bar.dart';
import 'widgets/settings_dialog.dart';
import 'download_page.dart';
import 'services/chat_helpers.dart';

/// Intent used by global Shortcuts / Actions so controller keys win even when
/// a `TextField` (PromptBar) owns primary focus.
class _GameIntent extends Intent {
  const _GameIntent(this.key);
  final LogicalKeyboardKey key;
}

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

  String _systemCtx = 'Aswer immediately! Keep answers short.';
  double _speechRate = 0.5;

  PreferredBackend _backend = PreferredBackend.cpu;

  /* misc */
  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;

  /* speech-to-text */
  final SpeechToText _speech = SpeechToText();
  bool _speechEnabled = false;
  bool _listening = false;

  /* keyboard focus root */
  final FocusNode _rootFocus = FocusNode();

  /* -------------------------------------------------------------- lifecycle */
  @override
  void initState() {
    super.initState();
    _bootstrap();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    _tts = FlutterTts();
    await _tts.setSpeechRate(_speechRate);
    _streamingTts = StreamingTtsService(_tts);

    // Initialize camera service
    await _cameraService.initialize();

    // Listen to camera service changes
    _cameraService.addListener(_onCameraServiceChanged);

    // Initialize chat helpers
    _chatHelpers = ChatHelpers(
      service: _service,
      streamingTts: _streamingTts,
      onStateChanged: () => setState(() {}),
      showSnackBar: (message) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
      systemContext: _systemCtx,
    );

    try {
      await _service.init(_backend);
    } catch (_) {
      await _handleInitError();
      return;
    }

    if (!mounted) return;
    setState(() => _initialising = false);
    _rootFocus.requestFocus();
  }

  void _onCameraServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /* -------------------------------------------------- error on first launch */
  Future<void> _handleInitError() async {
    final tasks = await FlutterDownloader.loadTasks() ?? [];
    for (final t in tasks) {
      if (t.filename!.endsWith('.task') &&
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
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const DownloadPage()));
  }

  /* ---------------------------------------------------------------- dispose */
  @override
  void dispose() {
    _streamingTts.stop();
    _tts.stop();
    _speech.stop();
    _speech.cancel();
    _rootFocus.dispose();
    _cameraService.removeListener(_onCameraServiceChanged);
    super.dispose();
  }

  /* ------------------------------------------------------- helper switches */
  void _toggleMessages() => setState(() => _showMessages = !_showMessages);
  void _toggleCamera() => setState(() => _showCamera = !_showCamera);

  Future<void> _toggleSettings() async {
    if (_settingsVisible) {
      // If settings are visible, close the dialog
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _settingsVisible = false);
      return;
    }

    setState(() => _settingsVisible = true);

    await showSettingsDialog(
      context: context,
      systemCtx: _systemCtx,
      speechRate: _speechRate,
      backend: _backend,
      cameraSource: _cameraService.cameraSource,
      ipCameraUrl: _cameraService.ipCameraUrl,
      onDismiss: () {
        if (mounted) {
          setState(() => _settingsVisible = false);
        }
      },
      onSave: (newCtx, newRate, newBackend, newSource, newUrl) async {
        setState(() {
          _systemCtx = newCtx;
          _speechRate = newRate;

          // Update chat helpers with new context
          _chatHelpers.updateSystemContext(_systemCtx);

          if (_backend != newBackend) {
            _backend = newBackend;
            _msgs.clear();
            _initialising = true;
            _redirectedOnError = false;
            _bootstrap();
          }
        });

        // Update camera settings through service
        await _cameraService.updateCameraSettings(
          newSource: newSource,
          newUrl: newUrl,
        );

        await _tts.setSpeechRate(_speechRate);
      },
    );
  }

  Future<void> _toggleDictation() async {
    if (!_speechEnabled) return;
    if (_listening) {
      _listening = false;
      await _speech.stop();
      if (mounted) setState(() {});
      return;
    }

    await _speech.listen(
      onResult: (val) {
        if (!_listening) return;
        _promptBarKey.currentState?.updateText(val.recognizedWords);
      },
    );
    setState(() => _listening = true);
  }

  /* -------------------------------------- quick actions (camera + prompt) */
  Future<void> _quickAction1() async => _chatHelpers.quickAction1(
    _msgs,
    _cameraService.cameraSource,
    _cameraService.cameraInitialized,
    _cameraService.cameraError,
    _cameraService.camera,
    _cameraService.ipCameraWebView,
    _cameraService.ipCameraUrl,
  );

  Future<void> _quickAction2() async => _chatHelpers.quickAction2(
    _msgs,
    _cameraService.cameraSource,
    _cameraService.cameraInitialized,
    _cameraService.cameraError,
    _cameraService.camera,
    _cameraService.ipCameraWebView,
    _cameraService.ipCameraUrl,
  );

  Future<void> _quickAction3() async => _chatHelpers.quickAction3(
    _msgs,
    _cameraService.cameraSource,
    _cameraService.cameraInitialized,
    _cameraService.cameraError,
    _cameraService.camera,
    _cameraService.ipCameraWebView,
    _cameraService.ipCameraUrl,
  );

  Future<void> _quickAction4() async => _chatHelpers.quickAction4(
    _msgs,
    _cameraService.cameraSource,
    _cameraService.cameraInitialized,
    _cameraService.cameraError,
    _cameraService.camera,
    _cameraService.ipCameraWebView,
    _cameraService.ipCameraUrl,
  );

  /* ------------------------- global logical key handler (Shortcuts layer) */
  void _handleLogicalKey(LogicalKeyboardKey key) {
    switch (key) {
      /* F10 (★ star) => toggle messages */
      case LogicalKeyboardKey.f10:
        _toggleMessages();
        break;

      /* F8 (♥ heart) => toggle settings */
      case LogicalKeyboardKey.f8:
        _toggleSettings();
        break;

      /* F2 (R) => dictation */
      case LogicalKeyboardKey.f2:
        _toggleDictation();
        break;

      /* quick actions */
      case LogicalKeyboardKey.f5: // A button
        _quickAction1();
        break;
      case LogicalKeyboardKey.f7: // B button
        _quickAction2();
        break;
      case LogicalKeyboardKey.f4: // X button
        _quickAction3();
        break;
      case LogicalKeyboardKey.f6: // Y button
        _quickAction4();
        break;

      /* F3 (+ button) => new chat */
      case LogicalKeyboardKey.f3:
        _newChat();
        break;

      /* arrow navigation */
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowLeft:
        FocusScope.of(context).previousFocus();
        break;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowRight:
        FocusScope.of(context).nextFocus();
        break;

      /* Activate (Enter / Select / L2) */
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        Actions.invoke(context, const ActivateIntent());
        break;
    }
  }

  /* ------------------------------ Shortcuts map (controller always wins) */
  Map<LogicalKeySet, Intent> get _shortcutMap => {
    LogicalKeySet(LogicalKeyboardKey.f10): const _GameIntent(
      LogicalKeyboardKey.f10,
    ),
    LogicalKeySet(LogicalKeyboardKey.f8): const _GameIntent(
      LogicalKeyboardKey.f8,
    ),
    LogicalKeySet(LogicalKeyboardKey.f2): const _GameIntent(
      LogicalKeyboardKey.f2,
    ),
    LogicalKeySet(LogicalKeyboardKey.f5): const _GameIntent(
      LogicalKeyboardKey.f5,
    ),
    LogicalKeySet(LogicalKeyboardKey.f7): const _GameIntent(
      LogicalKeyboardKey.f7,
    ),
    LogicalKeySet(LogicalKeyboardKey.f4): const _GameIntent(
      LogicalKeyboardKey.f4,
    ),
    LogicalKeySet(LogicalKeyboardKey.f6): const _GameIntent(
      LogicalKeyboardKey.f6,
    ),
    LogicalKeySet(LogicalKeyboardKey.f3): const _GameIntent(
      LogicalKeyboardKey.f3,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowUp): const _GameIntent(
      LogicalKeyboardKey.arrowUp,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowDown): const _GameIntent(
      LogicalKeyboardKey.arrowDown,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _GameIntent(
      LogicalKeyboardKey.arrowLeft,
    ),
    LogicalKeySet(LogicalKeyboardKey.arrowRight): const _GameIntent(
      LogicalKeyboardKey.arrowRight,
    ),
    LogicalKeySet(LogicalKeyboardKey.enter): const _GameIntent(
      LogicalKeyboardKey.enter,
    ),
    LogicalKeySet(LogicalKeyboardKey.select): const _GameIntent(
      LogicalKeyboardKey.select,
    ),
  };

  /* ------------------------------------------------ chat helpers (wrappers) */
  Future<void> _newChat() async {
    await _chatHelpers.newChat(_msgs, _promptBarKey);
  }

  Future<void> _captureAndSend(String prompt) async {
    await _chatHelpers.captureAndSend(
      prompt,
      _msgs,
      _cameraService.cameraSource,
      _cameraService.cameraInitialized,
      _cameraService.cameraError,
      _cameraService.camera,
      _cameraService.ipCameraWebView,
      _cameraService.ipCameraUrl,
    );
  }

  Future<void> _sendTextOnly(String prompt) async {
    await _chatHelpers.sendTextOnly(prompt, _msgs);
  }

  Widget _buildCameraPreview() {
    if (_cameraService.cameraSource == CameraSource.phone) {
      if (_cameraService.camera != null &&
          _cameraService.cameraInitialized &&
          !_cameraService.cameraError) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CameraPreviewBox(camera: _cameraService.camera!),
        );
      } else {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _cameraService.cameraError ? Icons.error : Icons.camera_alt,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  _cameraService.cameraError
                      ? 'Camera Error'
                      : 'Camera Initializing...',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IpCameraPreviewBox(
          ipCameraUrl: _cameraService.ipCameraUrl,
          onWebViewCreated: (c) => _cameraService.setIpCameraWebView(c),
        ),
      );
    }
  }

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
      shortcuts: _shortcutMap,
      child: Actions(
        actions: {
          _GameIntent: CallbackAction<_GameIntent>(
            onInvoke: (intent) => _handleLogicalKey(intent.key),
          ),
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Gemma Vision Chat',
                style: TextStyle(fontSize: 16),
              ),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                /* New chat button */
                TextButton.icon(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'New Chat',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: _chatHelpers.resetting ? null : _newChat,
                ),
                /* Settings button */
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
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.orange.shade300,
                          width: 2,
                        ),
                      ),
                    ),
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
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),

                /* View toggle buttons */
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _toggleCamera,
                        icon: Icon(
                          _showCamera ? Icons.visibility_off : Icons.visibility,
                        ),
                        label: Text(
                          _showCamera ? 'Hide Camera' : 'Show Camera',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _toggleMessages,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                /* Main content area */
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: Column(
                      children: [
                        /* Camera preview */
                        if (_showCamera)
                          Expanded(
                            flex: _showMessages ? 1 : 2,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: _buildCameraPreview(),
                            ),
                          ),

                        /* Messages list */
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

                /* Voice input button */
                if (_speechEnabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_chatHelpers.resetting ||
                                _chatHelpers.isGenerating)
                            ? null
                            : _toggleDictation,
                        icon: Icon(
                          _listening ? Icons.mic_off : Icons.mic,
                          size: 28,
                        ),
                        label: Text(
                          _listening ? 'Stop Voice Input' : 'Start Voice Input',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _listening
                              ? Colors.red
                              : Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  ),

                /* Prompt bar */
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
                    speechEnabled: _speechEnabled,
                    listening: _listening,
                    onToggleListening: _toggleDictation,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
