// lib/chat_page/gemma_vision_chat.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/prompt_bar.dart';
import 'services/bootstrap_manager.dart';
import 'services/chat_helpers.dart';
import 'services/gemma_service.dart';
import 'services/speech_service.dart';
import 'services/streaming_tts_service.dart';
import 'services/text_recognition_service.dart';
import 'services/sound_manager.dart'; // 사운드 매니저 추가
import 'models/message_models.dart';
import '../error_recovery_page.dart';
import 'handlers/keyboard_handler.dart';
import 'widgets/chat_ui_builder.dart';
import '../settings_page.dart';
import 'widgets/semantic_button_registry.dart';
import 'config/system_prompts.dart';
import 'services/chat_storage_service.dart';
import '../app_settings.dart'; // 앱 설정 추가

/// Main chat interface with AI vision model - handles bootstrap and lifecycle management
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  /* Core state */
  final _msgs = <ChatMessage>[];

  bool _showMessages = false;
  bool _showCamera = true;

  late FlutterTts _tts = FlutterTts();
  late StreamingTtsService _streamingTts = StreamingTtsService(_tts);

  ChatHelpers? _chatHelpers;
  SpeechService? _speechService;
  KeyboardHandler? _keyboardHandler;
  TextRecognitionService? _textRecognition;

  String _systemCtx = SystemPrompts.defaultSystemContext;
  MlcBackend _backend = MlcBackend.gpu;

  final _promptBarKey = GlobalKey<PromptBarState>();
  bool _initialising = true;
  bool _redirectedOnError = false;
  bool _disposed = false;

  final FocusNode _rootFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;

  final ChatStorageService _chatStorage = ChatStorageService.instance;
  String? _currentChatId;
  String? _currentChatName;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    // 설정을 먼저 불러온 후 부트스트랩 실행
    _loadSettings().then((_) => _bootstrap());
  }

  void _requestRootFocusOnNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      if (!_rootFocus.canRequestFocus) return;
      _rootFocus.requestFocus();
    });
  }

  /// 저장된 설정을 불러옵니다 (AppSettings 및 SharedPreferences)
  Future<void> _loadSettings() async {
    // [수정] AppSettings를 로드하여 프롬프트 설정을 가져옴
    await AppSettings.instance.load();

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 시스템 컨텍스트는 AppSettings에서 가져옴
      _systemCtx = AppSettings.instance.systemContext;

      // 백엔드 설정 로드
      final backendIndex = prefs.getInt('backendIndex');
      if (backendIndex != null &&
          backendIndex >= 0 &&
          backendIndex < MlcBackend.values.length) {
        _backend = MlcBackend.values[backendIndex];
      }
    });
  }

  /// 설정을 저장합니다 (주로 백엔드 설정)
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // _systemCtx는 AppSettings에서 관리하므로 여기서는 백엔드만 저장해도 무방하나,
    // 필요 시 AppSettings update 로직을 사용할 수 있음.
    // 여기서는 백엔드 인덱스만 SharedPref에 직접 저장.
    await prefs.setInt('backendIndex', _backend.index);
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
          if (mounted && !_disposed) {
            setState(() => _showMessages = !_showMessages);
            if (_showMessages) {
              _scrollToBottom(force: true);
            }
          }
        },
        onToggleCamera: () {
          if (mounted && !_disposed) setState(() => _showCamera = !_showCamera);
        },
        onToggleSettings: _navigateToSettings,
        onNewChat: _newChat,
        onQuickAction1: _quickAction1,
        onQuickAction2: _quickAction2,
        onQuickAction3: _quickAction3,
        onQuickAction4: _quickAction4,
        onToggleVoice: () {
          _speechService?.toggleDictation();
        },
        // [수정] 연결 테스트 콜백 연결
        onConnectionTest: () {
          SoundManager.instance.playConnectionCheck();
        },
        isMounted: () => mounted,
        isDisposed: () => _disposed,
        setState: (fn) {
          setState(fn);
          if (_showMessages) {
            _scheduleAutoScroll();
          }
        },
      );

      _streamingTts.stop();
      _tts.stop();

      _tts = result.tts;
      _streamingTts = result.streamingTts;
      _chatHelpers = result.chatHelpers;
      _speechService = result.speechService;
      _keyboardHandler = result.keyboardHandler;
      _textRecognition = result.textRecognition;
      _keyboardHandler?.attachGlobalHandler();

      if (mounted && !_disposed) {
        setState(() => _initialising = false);
        _requestRootFocusOnNextFrame();
        _fadeController.forward();
        _slideController.forward();
      }
    } catch (e) {
      debugPrint("Gemma service initialization failed: $e");

      if (mounted && !_disposed && !_redirectedOnError) {
        _redirectedOnError = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ErrorRecoveryPage()),
        );
      }
    }
  }

  void _scheduleAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });
  }

  void _scrollToBottom({bool force = false}) {
    if (!_showMessages && !force) return;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _streamingTts.stop();
    _tts.stop();
    _keyboardHandler?.dispose();
    _speechService?.dispose();
    _textRecognition?.dispose();
    _rootFocus.dispose();
    SemanticButtonRegistry.clear();
    super.dispose();
  }

  Future<void> _newChat() async =>
      await _chatHelpers!.newChat(_msgs, _promptBarKey).then((_) {
        if (mounted && !_disposed) {
          setState(() {
            _currentChatId = null;
            _currentChatName = null;
          });
        }
      });

  // [수정] 카메라 캡처 함수 (ChatHelpers의 새 메서드 사용)
  Future<void> _captureWithCamera(String prompt) async =>
      await _chatHelpers!.captureWithCamera(prompt, _msgs);

  // [추가] 갤러리 선택 함수
  Future<void> _pickFromGallery(String prompt) async =>
      await _chatHelpers!.pickFromGallery(prompt, _msgs);

  Future<void> _sendTextOnly(String prompt) async =>
      await _chatHelpers!.sendTextOnly(prompt, _msgs);

  Future<void> _quickAction1() async => _chatHelpers!.quickAction1(_msgs);
  Future<void> _quickAction2() async => _chatHelpers!.quickAction2(_msgs);
  Future<void> _quickAction3() async => _chatHelpers!.quickAction3(_msgs);
  Future<void> _quickAction4() async => _chatHelpers!.quickAction4(_msgs);

  @override
  Widget build(BuildContext context) {
    if (_initialising) return ChatUIBuilder.buildLoadingScreen();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Do you really want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Shortcuts(
      shortcuts: _keyboardHandler!.shortcuts,
      child: Actions(
        actions: _keyboardHandler!.actions,
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _speechService!.handleFocusKey,
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: ChatUIBuilder.buildCleanAppBar(
              onNewChat: _newChat,
              onToggleSettings: _navigateToSettings,
              isResetting: _chatHelpers!.resetting,
              onSaveChat: _saveChat,
              onSaveChatAs: _saveChatAs,
              onLoadChat: _loadChat,
            ),
            body: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    ChatUIBuilder.buildViewToggleButtons(
                      showMessages: _showMessages,
                      onToggleMessages: () {
                        setState(() => _showMessages = !_showMessages);
                        if (_showMessages) {
                          _scrollToBottom(force: true);
                        }
                      },
                      onNewChat: _newChat,
                      isResetting: _chatHelpers!.resetting,
                    ),
                    if (_showMessages)
                      ChatUIBuilder.buildMessagesContainer(
                        _msgs,
                        _scrollController,
                      )
                    else
                      const Expanded(child: SizedBox()),
                    ChatUIBuilder.buildPromptBarContainer(
                      promptBarKey: _promptBarKey,
                      onPromptWithCamera: _captureWithCamera, // [연결]
                      onPromptWithGallery: _pickFromGallery, // [연결]
                      onPromptTextOnly: _sendTextOnly,
                      disabled:
                          _chatHelpers!.resetting || _chatHelpers!.isGenerating,
                      speechEnabled: _speechService!.speechEnabled,
                      listening: _speechService!.listening,
                      onToggleListening: _speechService!.toggleDictation,
                      isGenerating: _chatHelpers!.isGenerating,
                      isSpeaking: _chatHelpers!.isSpeaking,
                      onStopTts: _chatHelpers!.stopSpeaking,
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

  Future<void> _navigateToSettings() async {
    if (_disposed || !mounted) return;

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        // [수정] systemContext는 내부에서 AppSettings 사용하므로 별도 전달 불필요할 수 있으나
        // SettingsPage 생성자 시그니처 유지
        builder: (context) =>
            SettingsPage(systemContext: _systemCtx, backend: _backend),
      ),
    );

    if (mounted && !_disposed) {
      // [수정] 설정 페이지에서 돌아왔을 때 AppSettings의 변경사항 반영
      setState(() {
        final newSystemContext = AppSettings.instance.systemContext;

        // 시스템 컨텍스트가 변경되었다면 헬퍼 업데이트
        if (newSystemContext != _systemCtx) {
          _systemCtx = newSystemContext;
          _chatHelpers!.updateSystemContext(_systemCtx);
        }

        // 백엔드가 변경되었다면 리부트스트랩
        if (result != null) {
          final newBackend = result['backend'] as MlcBackend?;
          if (newBackend != null && _backend != newBackend) {
            _backend = newBackend;
            _saveSettings(); // 백엔드 설정 저장

            // 완전 재초기화
            _msgs.clear();
            _initialising = true;
            BootstrapManager.reset();
            _redirectedOnError = false;
            _bootstrap();
          }
        }
      });
      _requestRootFocusOnNextFrame();
    }
  }

  // ... (저장/로드 관련 헬퍼 메소드들 - 기존 유지)
  String _defaultChatName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  void _showSnackBar(String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveChat() async {
    if (_msgs.isEmpty) {
      _showSnackBar('No messages to save.');
      return;
    }
    if (_currentChatId == null || _currentChatName == null) {
      await _saveChatAs();
      return;
    }
    try {
      final info = await _chatStorage.saveChat(
        name: _currentChatName!,
        existingId: _currentChatId,
        messages: _msgs,
      );
      setState(() {
        _currentChatId = info.id;
        _currentChatName = info.name;
      });
      _showSnackBar('Chat saved.');
    } catch (e) {
      _showSnackBar('Failed to save chat: $e');
    }
  }

  Future<void> _saveChatAs() async {
    if (_msgs.isEmpty) {
      _showSnackBar('No messages to save.');
      return;
    }
    final name = await _promptForChatName();
    if (name == null) return;

    try {
      final existing = await _chatStorage.findSaveByName(name);
      if (existing != null) {
        final overwrite = await _confirmOverwrite(name);
        if (!overwrite) return;
      }

      final info = await _chatStorage.saveChat(
        name: name,
        existingId: existing?.id,
        messages: _msgs,
      );
      setState(() {
        _currentChatId = info.id;
        _currentChatName = info.name;
      });
      _showSnackBar('Chat saved.');
    } catch (e) {
      _showSnackBar('Failed to save chat: $e');
    }
  }

  Future<void> _loadChat() async {
    try {
      final saves = await _chatStorage.listSaves();
      if (saves.isEmpty) {
        _showSnackBar('No saved chats found.');
        return;
      }
      final selected = await _showChatListDialog(saves);
      if (selected == null) return;

      final data = await _chatStorage.loadChat(selected.id);
      if (data == null) {
        _showSnackBar('Failed to load chat.');
        return;
      }

      setState(() {
        _msgs
          ..clear()
          ..addAll(data.messages);
        _currentChatId = data.info.id;
        _currentChatName = data.info.name;
        if (_showMessages) {
          _scrollToBottom(force: true);
        }
      });
    } catch (e) {
      _showSnackBar('Failed to load chat: $e');
    }
  }

  Future<String?> _promptForChatName() async {
    final controller = TextEditingController(text: _defaultChatName());
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save chat as'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter a chat name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.of(
                context,
              ).pop(name.isEmpty ? _defaultChatName() : name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<bool> _confirmOverwrite(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overwrite existing chat?'),
        content: Text('A chat named "$name" already exists. Overwrite it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<ChatSaveInfo?> _showChatListDialog(List<ChatSaveInfo> saves) async {
    return showDialog<ChatSaveInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load chat'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: saves.length,
            separatorBuilder: (_, separatorIndex) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = saves[index];
              final date = item.updatedAt.toLocal();
              final subtitle =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')} '
                  '${date.hour.toString().padLeft(2, '0')}:'
                  '${date.minute.toString().padLeft(2, '0')}';
              return ListTile(
                title: Text(item.name),
                subtitle: Text(subtitle),
                onTap: () => Navigator.of(context).pop(item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
