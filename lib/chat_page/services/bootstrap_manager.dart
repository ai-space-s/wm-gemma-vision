// lib/chat_page/services/bootstrap_manager.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_gemma/pigeon.g.dart';

import 'gemma_service.dart';
import 'streaming_tts_service.dart';
import 'chat_helpers.dart';
import 'speech_service.dart';
import 'text_recognition_service.dart';
import '../handlers/keyboard_handler.dart';
import '../widgets/prompt_bar.dart';

class BootstrapManager {
  static bool _globalBootstrapping = false;
  static Completer<void>? _globalBootstrapCompleter;

  static Future<BootstrapResult> bootstrap({
    required BuildContext context,
    required String systemContext,
    required PreferredBackend backend,
    required GlobalKey<PromptBarState> promptBarKey,
    required VoidCallback onToggleMessages,
    required VoidCallback onToggleCamera,
    required VoidCallback onToggleSettings,
    required Future<void> Function() onNewChat,
    required Future<void> Function() onQuickAction1,
    required Future<void> Function() onQuickAction2,
    required Future<void> Function() onQuickAction3,
    required Future<void> Function() onQuickAction4,
    required bool Function() isMounted,
    required bool Function() isDisposed,
    required void Function(VoidCallback) setState,
  }) async {
    // Check for concurrent bootstrap
    if (_globalBootstrapping) {
      debugPrint(
        "[BootstrapManager] Bootstrap already in progress globally, waiting...",
      );
      try {
        await _globalBootstrapCompleter?.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint(
              "[BootstrapManager] Bootstrap wait timed out, proceeding anyway",
            );
            _globalBootstrapping = false;
            _globalBootstrapCompleter = null;
          },
        );
      } catch (e) {
        debugPrint("[BootstrapManager] Bootstrap wait error: $e");
        _globalBootstrapping = false;
        _globalBootstrapCompleter = null;
      }

      if (_globalBootstrapping) {
        debugPrint(
          "[BootstrapManager] Forcing bootstrap reset due to deadlock",
        );
        _globalBootstrapping = false;
        _globalBootstrapCompleter = null;
      }
    }

    if (isDisposed()) {
      debugPrint("[BootstrapManager] Widget disposed, skipping bootstrap");
      throw BootstrapException("Widget disposed");
    }

    _globalBootstrapping = true;
    _globalBootstrapCompleter = Completer<void>();

    try {
      debugPrint("[BootstrapManager] Starting bootstrap...");
      await Future.delayed(const Duration(milliseconds: 100));

      // Initialize TTS
      final tts = FlutterTts();
      await tts.setSpeechRate(0.5);
      final streamingTts = StreamingTtsService(tts);
      debugPrint("[BootstrapManager] TTS initialized");

      if (!isMounted() || isDisposed()) {
        debugPrint("[BootstrapManager] Not mounted after TTS init");
        _globalBootstrapCompleter!.complete();
        throw BootstrapException("Widget not mounted");
      }

      // Initialize text recognition service
      final textRecognition = TextRecognitionService.instance;
      await textRecognition.initialize();
      debugPrint("[BootstrapManager] Text recognition initialized");

      if (!isMounted() || isDisposed()) {
        debugPrint(
          "[BootstrapManager] Not mounted after text recognition init",
        );
        _globalBootstrapCompleter!.complete();
        throw BootstrapException("Widget not mounted");
      }

      // Initialize speech service first (needed for chat helpers)
      final speechService = SpeechService(
        tts: tts,
        onStateChanged: () {
          if (isMounted() && !isDisposed()) setState(() {});
        },
        promptBarKey: promptBarKey,
        isGenerating: () =>
            false, // Will be updated after chatHelpers is created
      );
      await speechService.initialize();

      if (!isMounted() || isDisposed()) {
        debugPrint("[BootstrapManager] Not mounted after speech init");
        _globalBootstrapCompleter!.complete();
        throw BootstrapException("Widget not mounted");
      }
      debugPrint("[BootstrapManager] Speech service initialized");

      // Initialize chat helpers with speech service and text recognition
      final chatHelpers = ChatHelpers(
        service: GemmaService.instance,
        streamingTts: streamingTts,
        speechService: speechService,
        textRecognition: textRecognition,
        onStateChanged: () {
          if (isMounted() && !isDisposed()) setState(() {});
        },
        showSnackBar: (msg) {
          if (isMounted() && !isDisposed()) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        },
        systemContext: systemContext,
      );
      debugPrint("[BootstrapManager] Chat helpers initialized");

      // Update speech service's isGenerating callback now that chatHelpers exists
      speechService.updateIsGeneratingCallback(() => chatHelpers.isGenerating);

      // Initialize keyboard handler
      final keyboardHandler = KeyboardHandler(
        context: context,
        promptBarKey: promptBarKey,
        onToggleMessages: onToggleMessages,
        onToggleCamera: onToggleCamera,
        onToggleSettings: onToggleSettings,
        onNewChat: onNewChat,
        onQuickAction1: onQuickAction1,
        onQuickAction2: onQuickAction2,
        onQuickAction3: onQuickAction3,
        onQuickAction4: onQuickAction4,
      );
      debugPrint("[BootstrapManager] Keyboard handler initialized");

      // Initialize Gemma service
      debugPrint("[BootstrapManager] Initializing Gemma service...");
      await GemmaService.instance.init(backend);

      if (!isMounted() || isDisposed()) {
        debugPrint("[BootstrapManager] Not mounted after Gemma init");
        _globalBootstrapCompleter!.complete();
        throw BootstrapException("Widget not mounted");
      }
      debugPrint("[BootstrapManager] Gemma service initialized successfully");

      if (!_globalBootstrapCompleter!.isCompleted) {
        _globalBootstrapCompleter!.complete();
      }

      debugPrint("[BootstrapManager] Bootstrap completed successfully");

      return BootstrapResult(
        tts: tts,
        streamingTts: streamingTts,
        chatHelpers: chatHelpers,
        speechService: speechService,
        keyboardHandler: keyboardHandler,
        textRecognition: textRecognition,
      );
    } catch (e, stackTrace) {
      debugPrint("[BootstrapManager] Bootstrap error: $e");
      debugPrint("[BootstrapManager] Stack trace: $stackTrace");

      if (e is PlatformException) {
        debugPrint("[BootstrapManager] Platform error code: ${e.code}");
        debugPrint("[BootstrapManager] Platform error message: ${e.message}");
        debugPrint("[BootstrapManager] Platform error details: ${e.details}");
      }

      if (!_globalBootstrapCompleter!.isCompleted) {
        _globalBootstrapCompleter!.completeError(e);
      }

      rethrow;
    } finally {
      _globalBootstrapping = false;
      _globalBootstrapCompleter = null;
      debugPrint("[BootstrapManager] Bootstrap finally block - flags reset");
    }
  }

  static void reset() {
    _globalBootstrapping = false;
    _globalBootstrapCompleter = null;
  }
}

class BootstrapResult {
  final FlutterTts tts;
  final StreamingTtsService streamingTts;
  final ChatHelpers chatHelpers;
  final SpeechService speechService;
  final KeyboardHandler keyboardHandler;
  final TextRecognitionService textRecognition;

  BootstrapResult({
    required this.tts,
    required this.streamingTts,
    required this.chatHelpers,
    required this.speechService,
    required this.keyboardHandler,
    required this.textRecognition,
  });
}

class BootstrapException implements Exception {
  final String message;
  BootstrapException(this.message);

  @override
  String toString() => 'BootstrapException: $message';
}
