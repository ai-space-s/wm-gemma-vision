// lib/chat_page/chat_page.dart
// Patched to avoid LateInitializationError by eagerly constructing
// _tts and _streamingTts; also null‑aware dispose of services in case
// bootstrap fails early.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'widgets/prompt_bar.dart';

import 'services/bootstrap_manager.dart';
import 'services/camera_service.dart';
import 'services/chat_helpers.dart';
import 'services/speech_service.dart';
import 'services/streaming_tts_service.dart';
import 'models/camera_context.dart';
import 'models/message_models.dart';
import 'handlers/initialization_handler.dart';
import 'handlers/keyboard_handler.dart';
import 'widgets/chat_ui_builder.dart';
import 'widgets/settings_dialog.dart';
import 'config/system_prompts.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  /* ----------------------------------------------------------------- state */
  final _msgs = <ChatMessage>[];

  bool _showMessages = false;
  bool _showCamera = true;
  bool _settingsVisible = false;

  // Eagerly create TTS objects so they are **always** initialized, even if
  // bootstrap later fails. They will be overwritten with the instances coming
  // from BootstrapManager, and the temporary ones are stopped/disposed.
  late FlutterTts _tts = FlutterTts();
  late StreamingTtsService _streamingTts = StreamingTtsService(_tts);

  // These come from bootstrap – keep nullable until then.
  ChatHelpers? _chatHelpers;
  SpeechService? _speechService;
  KeyboardHandler? _keyboardHandler;

  // Use the specialized blind user navigation prompt by default
  String _systemCtx = SystemPrompts.blindUserNavigation;
  PreferredBackend _backend = PreferredBackend.cpu;

  /* misc */
  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;
  bool _disposed = false;

  /* focus */
  final FocusNode _rootFocus = FocusNode();

  /* Animation controllers */
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  /* -------------------------------------------------------------- lifecycle */
  @override
  void initState() {
    super.initState();
    _initAnimations();
    _bootstrap();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
  }

  Future<void> _bootstrap() async {
    if (_disposed) return;

    try {
      final result = await BootstrapManager.bootstrap(
        context: context,
        systemContext: _systemCtx,
        backend: _backend,
        promptBarKey: _promptBarKey,
        onToggleMessages: () {
          if (mounted && !_disposed)
            setState(() => _showMessages = !_showMessages);
        },
        onToggleCamera: () {
          if (mounted && !_disposed) setState(() => _showCamera = !_showCamera);
        },
        onToggleSettings: _toggleSettings,
        onNewChat: _newChat,
        onQuickAction1: _quickAction1,
        onQuickAction2: _quickAction2,
        onQuickAction3: _quickAction3,
        onQuickAction4: _quickAction4,
        isMounted: () => mounted,
        isDisposed: () => _disposed,
        setState: (fn) => setState(fn),
      );

      // Stop/clean temporary instances before overwriting.
      _streamingTts.stop();
      _tts.stop();

      // Store references from bootstrap result.
      _tts = result.tts;
      _streamingTts = result.streamingTts;
      _chatHelpers = result.chatHelpers;
      _speechService = result.speechService;
      _keyboardHandler = result.keyboardHandler;

      if (mounted && !_disposed) {
        setState(() => _initialising = false);
        _rootFocus.requestFocus();
        _fadeController.forward();
        _slideController.forward();
      }
    } catch (e) {
      if (mounted && !_disposed) {
        await InitializationHandler.handleInitError(
          context: context,
          mounted: mounted,
          disposed: _disposed,
          redirectedOnError: _redirectedOnError,
          setRedirectedOnError: (v) => _redirectedOnError = v,
        );
      }
    }
  }

  /* ---------------------------------------------------------------- dispose */
  @override
  void dispose() {
    _disposed = true;
    _fadeController.dispose();
    _slideController.dispose();
    _streamingTts.stop();
    _tts.stop();
    _speechService?.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  /* ------------------------------------- camera context helper */
  CameraContext get _cameraContext =>
      CameraContext.fromService(CameraService.instance);

  /* -------------------- chat helper wrappers */
  Future<void> _newChat() async =>
      await _chatHelpers!.newChat(_msgs, _promptBarKey);

  Future<void> _captureAndSend(String prompt) async =>
      await _chatHelpers!.captureAndSend(prompt, _msgs, _cameraContext);

  Future<void> _sendTextOnly(String prompt) async =>
      await _chatHelpers!.sendTextOnly(prompt, _msgs);

  /* ------------------------ quick actions */
  Future<void> _quickAction1() async =>
      _chatHelpers!.quickAction1(_msgs, _cameraContext);
  Future<void> _quickAction2() async =>
      _chatHelpers!.quickAction2(_msgs, _cameraContext);
  Future<void> _quickAction3() async =>
      _chatHelpers!.quickAction3(_msgs, _cameraContext);
  Future<void> _quickAction4() async =>
      _chatHelpers!.quickAction4(_msgs, _cameraContext);

  /* -------------------------------------------------------------- build UI */
  @override
  Widget build(BuildContext context) {
    if (_initialising) return ChatUIBuilder.buildLoadingScreen();

    return Shortcuts(
      shortcuts: _keyboardHandler!.shortcuts,
      child: Actions(
        actions: _keyboardHandler!.actions,
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _speechService!.handleFocusKey,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: ChatUIBuilder.buildCleanAppBar(
              onNewChat: _newChat,
              onToggleSettings: _toggleSettings,
              isResetting: _chatHelpers!.resetting,
            ),
            body: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    /* View toggles */
                    ChatUIBuilder.buildViewToggleButtons(
                      showCamera: _showCamera,
                      showMessages: _showMessages,
                      onToggleCamera: () =>
                          setState(() => _showCamera = !_showCamera),
                      onToggleMessages: () =>
                          setState(() => _showMessages = !_showMessages),
                    ),

                    /* Main content */
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            if (_showCamera)
                              Expanded(
                                flex: _showMessages ? 1 : 2,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ChatUIBuilder.buildCameraPreview(),
                                ),
                              ),
                            if (_showMessages)
                              Expanded(
                                flex: _showCamera ? 1 : 2,
                                child: ChatUIBuilder.buildMessagesContainer(
                                  _msgs,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    /* Prompt bar */
                    ChatUIBuilder.buildPromptBarContainer(
                      promptBarKey: _promptBarKey,
                      onPromptWithPhoto: _captureAndSend,
                      onPromptTextOnly: _sendTextOnly,
                      disabled:
                          _chatHelpers!.resetting || _chatHelpers!.isGenerating,
                      speechEnabled: _speechService!.speechEnabled,
                      listening: _speechService!.listening,
                      onToggleListening: _speechService!.toggleDictation,
                      isGenerating: _chatHelpers!.isGenerating,
                      isSpeaking: _chatHelpers!.isSpeaking,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ---------------- toggle settings dialog ---------------- */
  Future<void> _toggleSettings() async {
    if (_disposed || !mounted) return;

    if (_settingsVisible) {
      Navigator.of(context, rootNavigator: true).pop();
      if (mounted && !_disposed) setState(() => _settingsVisible = false);
      return;
    }

    if (mounted && !_disposed) setState(() => _settingsVisible = true);

    await showSettingsDialog(
      context: context,
      systemCtx: _systemCtx,
      backend: _backend,
      onDismiss: () {
        if (mounted && !_disposed) setState(() => _settingsVisible = false);
      },
      onSave: (newCtx, newBackend) async {
        if (!(mounted && !_disposed)) return;
        setState(() {
          _systemCtx = newCtx;
          _chatHelpers!.updateSystemContext(_systemCtx);

          if (_backend != newBackend) {
            _backend = newBackend;
            _msgs.clear();
            _initialising = true;
            BootstrapManager.reset();
            _redirectedOnError = false;
            _bootstrap();
          }
        });
      },
    );
  }
}
