// main.dart
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:gemma_chat/download_page/model_download_page.dart';
import 'package:gemma_chat/fast_chat.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Top‑level so the background isolate can find it.
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );
  send?.send([id, status, progress]);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ①  Initialise the plugin **once**.
  await FlutterDownloader.initialize(
    debug: kDebugMode, // logs in debug only
    ignoreSsl: false, // set true if you need plain‑HTTP links
  );

  // ②  Register the callback so WorkManager can call it.
  FlutterDownloader.registerCallback(downloadCallback);

  // Optional: keep the screen awake while downloading.
  await WakelockPlus.enable();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Gemma Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const UltraFastChatScreen(),
    );
  }
}
