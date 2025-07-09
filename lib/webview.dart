import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class InAppWebViewPage extends StatefulWidget {
  const InAppWebViewPage({super.key});

  @override
  State<InAppWebViewPage> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<InAppWebViewPage> {
  InAppWebViewController? webView;
  Uint8List? image;
  FlutterTts flutterTts = FlutterTts();
  double currentvol = 0.5;

  final String cameraStreamUrl = "http://192.168.4.1";

  final String htmlContent = '''
    <!DOCTYPE html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin:0; background-color:black;">
        <img src="http://192.168.4.1" style="width:100%; height:auto;" />
      </body>
    </html>
  ''';

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();

    VolumeController.instance.addListener((volume) async {
      if (webView != null) {
        image = await webView!.takeScreenshot();
        setState(() {});
        await saveWholeImage();
      }
    });

    Future.delayed(Duration.zero, () async {
      currentvol = await VolumeController.instance.getVolume();
      setState(() {});
    });

    ifFirstRun();
  }

  @override
  void dispose() {
    VolumeController.instance.removeListener();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<String> saveWholeImage() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;
    final file = File('$path/screenshot.png');
    await file.writeAsBytes(image!);
    return file.path;
  }

  speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1);
    await flutterTts.speak(text);
  }

  greeting() async {
    final player = AudioPlayer();
    await player.play(AssetSource("Santa.wav"));
  }

  ifFirstRun() async {
    final now = DateTime.now();
    if (now.day == 25 && now.month == 12) {
      await greeting();
    }
  }

  void refreshWebView() {
    if (webView != null) {
      webView!.loadData(
        data: htmlContent,
        baseUrl: WebUri(cameraStreamUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Camera View"),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () async {
              if (webView != null) {
                image = await webView!.takeScreenshot();
                setState(() {});
                await saveWholeImage();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Camera",
            onPressed: refreshWebView,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: htmlContent,
                baseUrl: WebUri(cameraStreamUrl),
                encoding: 'utf-8',
                mimeType: 'text/html',
              ),
              onWebViewCreated: (controller) {
                webView = controller;
              },
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: false,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                userAgent: "Mozilla/5.0",
              ),
              onPermissionRequest: (controller, request) async {
                await Permission.camera.request();
                await Permission.microphone.request();
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
            ),
          ),
          if (image != null) Expanded(child: Image.memory(image!)),
        ],
      ),
    );
  }
}
