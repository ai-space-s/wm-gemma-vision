// main.dart
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_gemma/flutter_gemma.dart'; // [수정] 중요: Gemma 플러그인 임포트
import 'package:gemma_chat/download_page/model_download_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app_settings.dart';

/// Top-level callback function for handling download progress updates.
/// This function is called by the background isolate when download status changes.
///
/// IMPORTANT: This must be a top-level function (not inside a class) and marked
/// with @pragma('vm:entry-point') so the Dart VM can find it when running
/// in the background isolate. The background downloader runs in a separate
/// isolate from the main UI thread for performance reasons.
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  // Look up the SendPort that was registered with the isolate name server
  // This allows communication between the background isolate and main isolate
  // Note: IsolateNameServer is not supported on Web
  if (kIsWeb) return;

  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );

  // Send download progress data to the main isolate
  // Data format: [taskId, status, progress_percentage]
  send?.send([id, status, progress]);
}

/// App entry point - initializes all required services before starting the UI.
Future<void> main() async {
  // Ensure Flutter binding is initialized before calling platform-specific code
  WidgetsFlutterBinding.ensureInitialized();

  // [수정] Gemma 플러그인 초기화 (앱 실행 전 필수)
  // 이 호출이 없으면 "Bad state: FlutterGemma not initialized!" 에러가 발생합니다.
  await FlutterGemma.initialize();

  // Initialize the flutter_downloader plugin for background downloads
  // This must be done before any download operations can be performed
  // Fix: flutter_downloader is not supported on Web, so we skip initialization
  if (!kIsWeb) {
    await FlutterDownloader.initialize(
      debug: kDebugMode, // Enable detailed logs only in debug mode
      ignoreSsl: false, // Set to true only if you need to download from HTTP URLs
    );

    // Register our callback function so the background downloader can call it
    // The downloader will use this callback to report progress updates
    FlutterDownloader.registerCallback(downloadCallback);
  }

  // This prevents the device from sleeping and potentially interrupting downloads
  await WakelockPlus.enable();

  await AppSettings.instance.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(AppSettings settings) {
    if (settings.highContrastEnabled) {
      final scheme = const ColorScheme.highContrastLight();
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return MaterialApp(
          title: 'Gemma Vision',
          theme: _buildTheme(settings),
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(settings.textScaleFactor),
              ),
              child: child,
            );
          },
          // Set the initial page to the model download screen
          // Users must download the ML model before they can use the chat feature
          home: const ModelDownloadPage(),
        );
      },
    );
  }
}
