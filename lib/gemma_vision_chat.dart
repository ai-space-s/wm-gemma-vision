// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_gemma/pigeon.g.dart';

import 'services/gemma_service.dart';
import 'services/streaming_tts_service.dart';
import 'models/message_models.dart';
import 'widgets/camera_preview.dart';
import 'widgets/ip_camera_preview.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/prompt_bar.dart';
import 'widgets/settings_dialog.dart';
import 'download_page.dart';

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
  final _msgs = <ChatMessage>[];

  bool _resetting = false;
  bool _showMessages = false;
  bool _settingsVisible = false;

  late FlutterTts _tts;
  late StreamingTtsService _streamingTts;
  String _systemCtx = 'Context: user is blind; keep answers concise.';
  double _speechRate = 0.5;

  PreferredBackend _backend = PreferredBackend.cpu;

  // Camera management - keep instance alive
  CameraController? _camera;
  bool _cameraInitialized = false;
  bool _cameraError = false;

  /* camera source can be phone or IP cam */
  CameraSource _cameraSource = CameraSource.phone;
  String _ipCameraUrl = 'http://192.168.4.1';
  InAppWebViewController? _ipCameraWebView;

  /* misc */
  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;
  bool _isGenerating = false;
  bool _isSpeaking = false;

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
    final prefs = await SharedPreferences.getInstance();
    _cameraSource = CameraSource.values[prefs.getInt('camera_source') ?? 0];
    _ipCameraUrl = prefs.getString('ip_camera_url') ?? 'http://192.168.4.1';

    _tts = FlutterTts();
    await _tts.setSpeechRate(_speechRate);
    _streamingTts = StreamingTtsService(_tts);

    try {
      await _service.init(_backend);
    } catch (_) {
      await _handleInitError();
      return;
    }

    // Only initialize phone camera once at startup
    if (_cameraSource == CameraSource.phone) {
      await _initializePhoneCamera();
    }

    if (!mounted) return;
    setState(() => _initialising = false);
    _rootFocus.requestFocus();
  }

  /* -------------------------------------------------- camera initialisation */
  Future<void> _initializePhoneCamera() async {
    if (_camera != null) return; // Already initialized

    try {
      final cams = await availableCameras();
      if (cams.isNotEmpty) {
        final backCamera = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first,
        );

        _camera = CameraController(
          backCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _camera!.initialize();

        if (mounted) {
          setState(() {
            _cameraInitialized = true;
            _cameraError = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _cameraInitialized = false;
          _cameraError = true;
        });
      }
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
    // DO NOT dispose camera here to avoid the crash
    // The camera will be disposed when the app terminates
    _streamingTts.stop();
    _tts.stop();
    _speech.stop();
    _speech.cancel();
    _rootFocus.dispose();
    super.dispose();
  }

  /* ------------------------------------------------------- helper switches */
  void _toggleMessages() => setState(() => _showMessages = !_showMessages);

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
      cameraSource: _cameraSource,
      ipCameraUrl: _ipCameraUrl,
      onDismiss: () {
        if (mounted) {
          setState(() => _settingsVisible = false);
        }
      },
      onSave: (newCtx, newRate, newBackend, newSource, newUrl) async {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _systemCtx = newCtx;
          _speechRate = newRate;

          if (_cameraSource != newSource || _ipCameraUrl != newUrl) {
            _cameraSource = newSource;
            _ipCameraUrl = newUrl;
            prefs
              ..setInt('camera_source', _cameraSource.index)
              ..setString('ip_camera_url', _ipCameraUrl);

            // If switching to phone camera and not initialized, initialize it
            if (_cameraSource == CameraSource.phone && _camera == null) {
              _initializePhoneCamera();
            }
          }

          if (_backend != newBackend) {
            _backend = newBackend;
            _msgs.clear();
            _initialising = true;
            _redirectedOnError = false;
            _bootstrap();
          }
        });
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
  Future<void> _quickAction1() async => _captureAndSend('Describe the room');
  Future<void> _quickAction2() async => _captureAndSend('Tell me what you see');
  Future<void> _quickAction3() async => _captureAndSend('Find an exit');
  Future<void> _quickAction4() async => _captureAndSend('Read text');

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

  /* ------------------------------------------------ chat helpers (send) */
  Future<void> _newChat() async {
    if (_resetting) return;
    _streamingTts.reset();
    setState(() {
      _resetting = true;
      _msgs.clear();
      _promptBarKey.currentState?.clear();
    });
    await _service.resetChatSession();
    if (mounted) {
      setState(() => _resetting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('New chat started')));
    }
  }

  Future<void> _captureAndSend(String prompt) async {
    if (_cameraSource == CameraSource.phone &&
        (!_cameraInitialized || _cameraError)) {
      setState(() {
        _msgs.add(ChatMessage('Camera not available', isUser: false));
      });
      return;
    }

    try {
      setState(() {
        _isGenerating = true;
        _isSpeaking = false;
      });

      File? img;
      if (_cameraSource == CameraSource.phone) {
        img = await _safeTakePicture();
      } else {
        img = await _captureIpCameraImage();
      }

      if (img == null) {
        setState(() {
          _msgs.add(ChatMessage('Camera busy; try again…', isUser: false));
          _isGenerating = false;
        });
        return;
      }

      setState(() => _msgs.add(ChatMessage(prompt, isUser: true)));

      final aiMsg = ChatMessage('', isUser: false, isStreaming: true);
      setState(() => _msgs.add(aiMsg));

      String prev = '';
      bool first = false;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        image: img,
        onToken: (tok) {
          if (!mounted) return;
          if (!first) {
            first = true;
            setState(() => _isSpeaking = true);
          }
          _streamingTts.addText(tok, prev);
          prev = tok;
          setState(() => aiMsg.text = tok);
        },
        onComplete: (stats) {
          if (!mounted) return;
          setState(() {
            aiMsg
              ..isStreaming = false
              ..stats = stats;
            _isGenerating = false;
            _isSpeaking = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _msgs.add(ChatMessage('Error: $e', isUser: false));
        _isGenerating = false;
        _isSpeaking = false;
      });
    }
  }

  Future<void> _sendTextOnly(String prompt) async {
    try {
      setState(() {
        _isGenerating = true;
        _isSpeaking = false;
      });
      setState(() => _msgs.add(ChatMessage(prompt, isUser: true)));

      final aiMsg = ChatMessage('', isUser: false, isStreaming: true);
      setState(() => _msgs.add(aiMsg));

      String prev = '';
      bool first = false;

      await _service.sendWithStreaming(
        text: '$_systemCtx\nUser: $prompt',
        onToken: (tok) {
          if (!mounted) return;
          if (!first) {
            first = true;
            setState(() => _isSpeaking = true);
          }
          _streamingTts.addText(tok, prev);
          prev = tok;
          setState(() => aiMsg.text = tok);
        },
        onComplete: (stats) {
          if (!mounted) return;
          setState(() {
            aiMsg
              ..isStreaming = false
              ..stats = stats;
            _isGenerating = false;
            _isSpeaking = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _msgs.add(ChatMessage('Error: $e', isUser: false));
        _isGenerating = false;
        _isSpeaking = false;
      });
    }
  }

  /* --------------------------------------------- camera helper functions */
  Future<File?> _safeTakePicture() async {
    if (_camera == null || !_camera!.value.isInitialized) {
      return null;
    }

    // Check if camera is already taking a picture
    if (_camera!.value.isTakingPicture) {
      debugPrint('Camera is already taking a picture');
      return null;
    }

    try {
      final x = await _camera!.takePicture();
      return File(x.path);
    } catch (e) {
      debugPrint('Camera picture error: $e');
      return null;
    }
  }

  Future<File?> _captureIpCameraImage() async {
    try {
      if (_ipCameraWebView != null) {
        final bytes = await _ipCameraWebView!.takeScreenshot();
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

  Widget _buildCameraPreview() {
    if (_cameraSource == CameraSource.phone) {
      if (_camera != null && _cameraInitialized && !_cameraError) {
        return CameraPreviewBox(camera: _camera!);
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _cameraError ? Icons.error : Icons.camera_alt,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _cameraError ? 'Camera Error' : 'Camera Initializing...',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        );
      }
    } else {
      return IpCameraPreviewBox(
        ipCameraUrl: _ipCameraUrl,
        onWebViewCreated: (c) => _ipCameraWebView = c,
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
              Text(
                'Initializing Gemma…',
                semanticsLabel: 'Initializing Gemma AI model',
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        // Handle back button
        return true; // Allow normal back navigation
      },
      child: Shortcuts(
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
                title: const Text('Gemma Vision Chat'),
                actions: [
                  /* ⭐ star toggle */
                  Semantics(
                    label: _showMessages ? 'Hide messages' : 'Show messages',
                    button: true,
                    child: IconButton(
                      icon: Icon(
                        _showMessages ? Icons.star : Icons.star_border,
                      ),
                      onPressed: _toggleMessages,
                      tooltip: _showMessages
                          ? 'Hide messages'
                          : 'Show messages',
                    ),
                  ),
                  /* new chat */
                  Semantics(
                    label: 'New chat',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _resetting ? null : _newChat,
                      tooltip: 'New chat',
                    ),
                  ),
                  /* ♥ heart settings */
                  Semantics(
                    label: _settingsVisible ? 'Hide settings' : 'Show settings',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.favorite),
                      onPressed: _toggleSettings,
                      tooltip: _settingsVisible
                          ? 'Hide settings'
                          : 'Show settings',
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  /* status */
                  if (_isGenerating || _isSpeaking)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.withOpacity(0.1),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isGenerating
                                  ? (_isSpeaking
                                        ? 'Generating and speaking…'
                                        : 'Generating response…')
                                  : 'Speaking…',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  /* camera */
                  Expanded(
                    flex: _showMessages ? 3 : 5,
                    child: Semantics(
                      label: 'Camera view',
                      child: _buildCameraPreview(),
                    ),
                  ),

                  /* messages */
                  if (_showMessages)
                    Expanded(
                      flex: 4,
                      child: Semantics(
                        label: 'Chat messages',
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _msgs.length,
                          itemBuilder: (_, i) =>
                              Focus(child: ChatBubble(msg: _msgs[i])),
                        ),
                      ),
                    ),

                  const Divider(height: 1),

                  /* legend + prompt */
                  Container(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Semantics(
                          label: 'Controller button mappings',
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _CtrlBtn(
                                    'A',
                                    'Describe room',
                                    Colors.green,
                                    semanticLabel: 'A button: Describe room',
                                  ),
                                  _CtrlBtn(
                                    'B',
                                    'What you see',
                                    Colors.red,
                                    semanticLabel:
                                        'B button: Tell me what you see',
                                  ),
                                  _CtrlBtn(
                                    'X',
                                    'Find exit',
                                    Colors.blue,
                                    semanticLabel: 'X button: Find exit',
                                  ),
                                  _CtrlBtn(
                                    'Y',
                                    'Read text',
                                    Colors.yellow,
                                    semanticLabel: 'Y button: Read text',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _CtrlBtn(
                                    '+',
                                    'New chat',
                                    Colors.grey,
                                    semanticLabel: 'Plus button: New chat',
                                  ),
                                  _CtrlBtn(
                                    '★',
                                    'Show messages',
                                    Colors.purple,
                                    semanticLabel:
                                        'Star button: Show or hide messages',
                                  ),
                                  _CtrlBtn(
                                    '♥',
                                    'Settings',
                                    Colors.pink,
                                    semanticLabel:
                                        'Heart button: Toggle settings',
                                  ),
                                  _CtrlBtn(
                                    'R2',
                                    _listening
                                        ? 'Stop dictation'
                                        : 'Start dictation',
                                    _listening ? Colors.orange : Colors.grey,
                                    semanticLabel: _listening
                                        ? 'Right trigger: Stop dictation'
                                        : 'Right trigger: Start dictation',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Semantics(
                                label:
                                    'Left trigger: Press to activate or enter',
                                child: Text(
                                  'L2: Press to activate',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        PromptBar(
                          key: _promptBarKey,
                          onPromptWithPhoto: _captureAndSend,
                          onPromptTextOnly: _sendTextOnly,
                          disabled: _resetting || _isGenerating,
                          speechEnabled: _speechEnabled,
                          listening: _listening,
                          onToggleListening: _toggleDictation,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------ legend tile */
class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn(
    this.btn,
    this.label,
    this.color, {
    super.key,
    this.semanticLabel,
  });
  final String btn, label;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      label: semanticLabel ?? '$btn button: $label',
      button: true,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              btn,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.8),
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 8),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
