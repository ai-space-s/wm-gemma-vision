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

/// Intent so controller keys win even when a TextField has focus.
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

  String _systemCtx = 'Answer immediately! Keep answers short.';
  double _speechRate = 0.5;

  PreferredBackend _backend = PreferredBackend.cpu;

  /* misc */
  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;

  /* speech‑to‑text */
  final SpeechToText _speech = SpeechToText();
  bool _speechEnabled = false;
  bool _listening = false;
  String _dictationText = '';

  /* focus */
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
      onStatus: (status) {
        // Restart if recognizer auto‑stops while key still held.
        if (_listening && status == 'notListening') {
          _listenAgain();
        }
      },
      onError: (_) {},
    );
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    _tts = FlutterTts();
    await _tts.setSpeechRate(_speechRate);
    _streamingTts = StreamingTtsService(_tts);

    await _cameraService.initialize();
    _cameraService.addListener(() => mounted ? setState(() {}) : {});

    _chatHelpers = ChatHelpers(
      service: _service,
      streamingTts: _streamingTts,
      onStateChanged: () => setState(() {}),
      showSnackBar: (msg) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg))),
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

  /* -------------------------------------------------- first‑launch errors */
  Future<void> _handleInitError() async {
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
    _cameraService.dispose();
    super.dispose();
  }

  /* ------------------------------------------------ helper (click sound) */
  void _click() => SystemSound.play(SystemSoundType.click);

  /* ------------------------------------------------ dictation helpers */
  Future<void> _startDictation() async {
    if (!_speechEnabled || _chatHelpers.isGenerating) return;

    if (!_listening) {
      _dictationText = ''; // new session
      _listening = true;
      setState(() {});
    }

    _click();
    _listenAgain();
  }

  Future<void> _stopDictation() async {
    if (!_listening) return;
    _click();
    _listening = false;
    await _speech.stop();
    if (_dictationText.trim().isNotEmpty) {
      await _tts.speak(_dictationText.trim());
    }
    setState(() {});
  }

  void _listenAgain() {
    _speech.listen(
      onResult: (val) {
        if (!_listening) return;

        final full = (_dictationText + ' ' + val.recognizedWords).trim();
        _promptBarKey.currentState?.updateText(full);

        if (val.finalResult) _dictationText = full;
      },

      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 60),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  Future<void> _toggleDictation() async =>
      _listening ? _stopDictation() : _startDictation();

  /* -------------------------------------------------- raw key handler */
  KeyEventResult _handleFocusKey(FocusNode _, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.f2) {
      if (e is KeyDownEvent) {
        _startDictation();
        return KeyEventResult.handled;
      } else if (e is KeyUpEvent) {
        _stopDictation();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onShortcut(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.f10:
        setState(() => _showMessages = !_showMessages);
        break;
      case LogicalKeyboardKey.f9:
        _promptBarKey.currentState?.sendTextOnly();
        break;
      case LogicalKeyboardKey.f8:
        _toggleSettings();
        break;
      case LogicalKeyboardKey.f1:
        _promptBarKey.currentState?.sendWithPhoto();
        break;
      case LogicalKeyboardKey.f3:
        _newChat();
        break;
      case LogicalKeyboardKey.f5:
        _quickAction1();
        break;
      case LogicalKeyboardKey.f7:
        _quickAction2();
        break;
      case LogicalKeyboardKey.f4:
        _quickAction3();
        break;
      case LogicalKeyboardKey.f6:
        _quickAction4();
        break;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowLeft:
        FocusScope.of(context).previousFocus();
        break;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowRight:
        FocusScope.of(context).nextFocus();
        break;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        Actions.invoke(context, const ActivateIntent());
        break;
    }
  }

  Map<LogicalKeySet, Intent> get _shortcuts => {
    LogicalKeySet(LogicalKeyboardKey.f9): const _GameIntent(
      LogicalKeyboardKey.f9,
    ),
    LogicalKeySet(LogicalKeyboardKey.f10): const _GameIntent(
      LogicalKeyboardKey.f10,
    ),
    LogicalKeySet(LogicalKeyboardKey.f8): const _GameIntent(
      LogicalKeyboardKey.f8,
    ),
    LogicalKeySet(LogicalKeyboardKey.f1): const _GameIntent(
      LogicalKeyboardKey.f1,
    ),
    // F2 handled via press‑and‑hold listener
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

  /* -------------------- chat helper wrappers */
  Future<void> _newChat() async => _chatHelpers.newChat(_msgs, _promptBarKey);

  Future<void> _captureAndSend(String p) async => _chatHelpers.captureAndSend(
    p,
    _msgs,
    _cameraService.cameraSource,
    _cameraService.cameraInitialized,
    _cameraService.cameraError,
    _cameraService.camera,
    _cameraService.ipCameraWebView,
    _cameraService.ipCameraUrl,
  );

  Future<void> _sendTextOnly(String p) async =>
      _chatHelpers.sendTextOnly(p, _msgs);

  /* ------------------------ quick actions */
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

  /* ------------------------ camera preview */
  Widget _cameraPreview() {
    if (_cameraService.cameraSource == CameraSource.phone) {
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
    // IP cam
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: IpCameraPreviewBox(
        ipCameraUrl: _cameraService.ipCameraUrl,
        onWebViewCreated: _cameraService.setIpCameraWebView,
      ),
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
          Icon(Icons.camera_alt, size: 64, color: Colors.grey),
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
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          _GameIntent: CallbackAction<_GameIntent>(
            onInvoke: (i) => _onShortcut(i.key),
          ),
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _handleFocusKey,
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
      speechRate: _speechRate,
      backend: _backend,
      cameraSource: _cameraService.cameraSource,
      ipCameraUrl: _cameraService.ipCameraUrl,
      onDismiss: () => setState(() => _settingsVisible = false),
      onSave: (newCtx, newRate, newBackend, newSrc, newUrl) async {
        setState(() {
          _systemCtx = newCtx;
          _speechRate = newRate;
          _chatHelpers.updateSystemContext(_systemCtx);

          if (_backend != newBackend) {
            _backend = newBackend;
            _msgs.clear();
            _initialising = true;
            _redirectedOnError = false;
            _bootstrap();
          }
        });

        await _cameraService.updateCameraSettings(
          newSource: newSrc,
          newUrl: newUrl,
        );
        await _tts.setSpeechRate(_speechRate);
      },
    );
  }
}
