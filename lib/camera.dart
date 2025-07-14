// // gemma_vision_chat.dart
// // ---------------------------------------------------------------------------
// //  Full demo app: vision-based chat with Gemma, camera, TTS & dictation
// //  Added backend toggle: CPU, NNAPI, GPU, TPU
// //  Enhanced with streaming text display, performance statistics,
// //  streaming TTS, markdown rendering, and IP camera support
// // ---------------------------------------------------------------------------

// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_downloader/flutter_downloader.dart';
// import 'package:flutter_gemma/core/chat.dart';
// import 'package:flutter_gemma/core/model.dart';
// import 'package:flutter_gemma/flutter_gemma.dart';
// import 'package:flutter_gemma/pigeon.g.dart';
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:speech_to_text/speech_to_text.dart';
// import 'package:gpt_markdown/gpt_markdown.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// import 'download_page.dart'; // for fallback if model init fails

// /// Camera source enum
// enum CameraSource { phone, ip }

// /// Performance statistics for each message
// class MessageStats {
//   final double? timeToFirstToken;
//   final double? totalLatency;
//   final double? prefillSpeed;
//   final double? decodeSpeed;
//   final int? tokenCount;

//   MessageStats({
//     this.timeToFirstToken,
//     this.totalLatency,
//     this.prefillSpeed,
//     this.decodeSpeed,
//     this.tokenCount,
//   });
// }

// /// ---------------------------------------------------------------------------
// ///  STREAMING TTS SERVICE
// /// ---------------------------------------------------------------------------
// class StreamingTtsService {
//   final FlutterTts _tts;
//   final List<String> _pendingSegments = [];
//   bool _isSpeaking = false;
//   String _buffer = '';
//   String _lastSpokenText = '';
//   Timer? _bufferTimer;

//   StreamingTtsService(this._tts);

//   void addText(String newText, String previousText) {
//     // Extract new content by comparing with previous text
//     if (newText.length <= previousText.length) return;

//     // Add new content to buffer
//     _buffer = newText;

//     // Reset timer - we'll wait for a pause in updates before processing
//     _bufferTimer?.cancel();
//     _bufferTimer = Timer(const Duration(milliseconds: 500), () {
//       _processBuffer();
//     });
//   }

//   void _processBuffer() {
//     if (_buffer.isEmpty || _buffer == _lastSpokenText) return;

//     // Clean the text for TTS
//     final cleanText = _cleanMarkdownForTts(_buffer);

//     // Find complete sentences that we haven't spoken yet
//     final newSentences = _findNewCompleteSentences(cleanText, _lastSpokenText);

//     if (newSentences.isNotEmpty) {
//       _pendingSegments.addAll(newSentences);

//       // Update what we've processed
//       _lastSpokenText = cleanText;

//       // Start speaking if not already speaking
//       if (!_isSpeaking) {
//         _processNextSegment();
//       }
//     }
//   }

//   List<String> _findNewCompleteSentences(String fullText, String spokenText) {
//     final sentences = <String>[];

//     // Remove what we've already spoken
//     String newContent = fullText;
//     if (spokenText.isNotEmpty && fullText.startsWith(spokenText)) {
//       newContent = fullText.substring(spokenText.length);
//     }

//     // Look for complete phrases (ending with comma, period, exclamation, or question mark)
//     final phraseRegex = RegExp(r'[,.!?]+(?:\s+|$)');
//     final matches = phraseRegex.allMatches(newContent);

//     int lastEnd = 0;
//     for (final match in matches) {
//       final phrase = newContent.substring(lastEnd, match.end).trim();
//       if (phrase.isNotEmpty && phrase.length > 3) {
//         sentences.add(phrase);
//         lastEnd = match.end;
//       }
//     }

//     return sentences;
//   }

//   void _processNextSegment() async {
//     if (_pendingSegments.isEmpty) {
//       _isSpeaking = false;
//       return;
//     }

//     _isSpeaking = true;
//     final segment = _pendingSegments.removeAt(0);

//     // Speak the segment
//     await _tts.speak(segment);

//     // Use TTS completion callback instead of timer
//     _tts.setCompletionHandler(() {
//       if (_pendingSegments.isNotEmpty) {
//         _processNextSegment();
//       } else {
//         _isSpeaking = false;
//       }
//     });
//   }

//   String _cleanMarkdownForTts(String text) {
//     // Remove markdown formatting for better TTS
//     return text
//         .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1') // Bold
//         .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1') // Italic
//         .replaceAll(RegExp(r'`([^`]+)`'), r'$1') // Inline code
//         .replaceAll(RegExp(r'#{1,6}\s+'), '') // Headers
//         .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1') // Links
//         .replaceAll(RegExp(r'>\s+'), '') // Blockquotes
//         .replaceAll(RegExp(r'[-*+]\s+'), '') // List markers
//         .replaceAll(RegExp(r'\d+\.\s+'), '') // Numbered list markers
//         .replaceAll(RegExp(r'\n+'), ' ') // Replace newlines with spaces
//         .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
//         .trim();
//   }

//   void stop() {
//     _bufferTimer?.cancel();
//     _tts.stop();
//     _pendingSegments.clear();
//     _isSpeaking = false;
//     _buffer = '';
//     _lastSpokenText = '';
//   }

//   void reset() {
//     stop();
//   }
// }

// /// ---------------------------------------------------------------------------
// ///  GEMMA SERVICE (singleton) – loads model once, keeps chat alive
// /// ---------------------------------------------------------------------------
// class GemmaService {
//   GemmaService._internal();
//   static final GemmaService instance = GemmaService._internal();

//   final _gemma = FlutterGemmaPlugin.instance;
//   InferenceModel? _model;
//   InferenceChat? _chat;
//   bool _initialised = false;

//   /// Initialize with selected backend
//   Future<void> init(PreferredBackend backend) async {
//     if (_initialised) return;

//     final dir = await getApplicationDocumentsDirectory();
//     final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

//     if (!await _gemma.modelManager.isModelInstalled &&
//         File(path).existsSync()) {
//       await _gemma.modelManager.setModelPath(path);
//     }

//     _model ??= await _gemma.createModel(
//       preferredBackend: backend,
//       modelType: ModelType.gemmaIt,
//       supportImage: true,
//       maxTokens: 4096,
//       maxNumImages: 1,
//     );

//     _chat ??= await _model!.createChat(
//       randomSeed: 1,
//       temperature: 1,
//       topK: 64,
//       topP: 0.95,
//       supportImage: true,
//       tokenBuffer: 256,
//     );

//     _initialised = true;
//   }

//   /// Send message with callback-based streaming
//   Future<void> sendWithStreaming({
//     required String text,
//     File? image,
//     required Function(String) onToken,
//     required Function(MessageStats) onComplete,
//   }) async {
//     final startTime = DateTime.now();
//     DateTime? firstTokenTime;
//     int tokenCount = 0;
//     final tokens = <String>[];

//     // Add the query
//     if (image != null) {
//       final bytes = await image.readAsBytes();
//       await _chat!.addQueryChunk(
//         Message.withImage(text: text, imageBytes: bytes, isUser: true),
//       );
//     } else {
//       await _chat!.addQueryChunk(Message.text(text: text, isUser: true));
//     }

//     // Use the async streaming method from the documentation
//     final completer = Completer<void>();

//     _chat!.generateChatResponseAsync().listen(
//       (String token) {
//         if (firstTokenTime == null) {
//           firstTokenTime = DateTime.now();
//         }
//         tokenCount++;
//         tokens.add(token);
//         onToken(tokens.join(''));
//       },
//       onDone: () {
//         final endTime = DateTime.now();

//         // Calculate statistics
//         final stats = MessageStats(
//           timeToFirstToken: firstTokenTime != null
//               ? firstTokenTime!.difference(startTime).inMilliseconds / 1000.0
//               : null,
//           totalLatency: endTime.difference(startTime).inMilliseconds / 1000.0,
//           tokenCount: tokenCount,
//           prefillSpeed: firstTokenTime != null && tokenCount > 0
//               ? 1000.0 / firstTokenTime!.difference(startTime).inMilliseconds
//               : null,
//           decodeSpeed: firstTokenTime != null && tokenCount > 1
//               ? (tokenCount - 1) *
//                     1000.0 /
//                     endTime.difference(firstTokenTime!).inMilliseconds
//               : null,
//         );

//         onComplete(stats);
//         completer.complete();
//       },
//       onError: (error) {
//         completer.completeError(error);
//       },
//     );

//     await completer.future;
//   }

//   Future<void> resetChatSession() async {
//     if (!_initialised) return;
//     await _chat?.clearHistory();
//   }

//   Future<void> dispose() async {
//     await _model?.close();
//     await _gemma.modelManager.deleteModel();
//     _model = null;
//     _chat = null;
//     _initialised = false;
//   }
// }

// /// ---------------------------------------------------------------------------
// ///  CHAT PAGE – camera feed, transcript bubbles, prompt bar & settings
// /// ---------------------------------------------------------------------------
// class ChatPage extends StatefulWidget {
//   const ChatPage({Key? key}) : super(key: key);
//   @override
//   State<ChatPage> createState() => _ChatPageState();
// }

// class _ChatPageState extends State<ChatPage> {
//   final _service = GemmaService.instance;
//   final _msgs = <_Msg>[];
//   bool _resetting = false;

//   late FlutterTts _tts;
//   late StreamingTtsService _streamingTts;
//   String _systemCtx = 'Context: user is blind; keep answers concise.';
//   double _speechRate = 0.5;
//   PreferredBackend _backend = PreferredBackend.cpu;

//   CameraController? _camera;
//   bool _cameraReady = false;
//   final _promptBarKey = GlobalKey<_PromptBarState>();

//   bool _initialising = true;
//   bool _redirectedOnError = false;

//   // IP Camera settings
//   CameraSource _cameraSource = CameraSource.phone;
//   String _ipCameraUrl = 'http://192.168.4.1';
//   InAppWebViewController? _ipCameraWebView;

//   @override
//   void initState() {
//     super.initState();
//     _bootstrap();
//   }

//   Future<void> _bootstrap() async {
//     // Load preferences
//     final prefs = await SharedPreferences.getInstance();
//     _cameraSource = CameraSource.values[prefs.getInt('camera_source') ?? 0];
//     _ipCameraUrl = prefs.getString('ip_camera_url') ?? 'http://192.168.4.1';

//     _tts = FlutterTts();
//     await _tts.setSpeechRate(_speechRate);
//     _streamingTts = StreamingTtsService(_tts);

//     try {
//       await _service.init(_backend);
//     } catch (e) {
//       // Delete any incomplete tasks
//       final tasks = await FlutterDownloader.loadTasks() ?? [];
//       for (var t in tasks) {
//         if (t.filename!.endsWith('.task') &&
//             t.status != DownloadTaskStatus.complete) {
//           await FlutterDownloader.remove(
//             taskId: t.taskId,
//             shouldDeleteContent: true,
//           );
//         }
//       }

//       // Delete model file and any temp file
//       final dir = await getApplicationDocumentsDirectory();
//       final fileNames = [
//         '${dir.path}/gemma-3n-E2B-it-int4.task',
//         '${dir.path}/gemma-3n-E2B-it-int4.task.tmp',
//       ];
//       for (final p in fileNames) {
//         final f = File(p);
//         if (await f.exists()) {
//           try {
//             await f.delete();
//           } catch (_) {}
//         }
//       }
//       // Redirect once to download screen
//       if (!mounted || _redirectedOnError) return;
//       _redirectedOnError = true;
//       Navigator.of(context).pushReplacement(
//         MaterialPageRoute(builder: (_) => const DownloadPage()),
//       );
//       return;
//     }

//     // Initialize camera based on source
//     await _initializeCamera();

//     if (!mounted) return;
//     setState(() {
//       _initialising = false;
//     });
//   }

//   Future<void> _initializeCamera() async {
//     if (_cameraSource == CameraSource.phone) {
//       // Initialize phone camera
//       final cams = await availableCameras();
//       _camera = CameraController(
//         cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back),
//         ResolutionPreset.medium,
//         enableAudio: false,
//       );
//       await _camera!.initialize();
//       _cameraReady = true;
//     } else {
//       // IP camera will be initialized through InAppWebView
//       _cameraReady = true;
//     }
//   }

//   @override
//   void dispose() {
//     _camera?.dispose();
//     _streamingTts.stop();
//     _tts.stop();
//     super.dispose();
//   }

//   Future<void> _resetChat() async {
//     if (_resetting) return;
//     _streamingTts.reset();
//     setState(() {
//       _resetting = true;
//       _msgs.clear();
//       _promptBarKey.currentState?.clear();
//     });
//     await _service.resetChatSession();
//     if (mounted) setState(() => _resetting = false);
//   }

//   Future<void> _captureAndSend(String prompt) async {
//     if (!_cameraReady) return;
//     try {
//       File? file;

//       if (_cameraSource == CameraSource.phone) {
//         file = await _safeTakePicture();
//       } else {
//         file = await _captureIpCameraImage();
//       }

//       if (file == null) {
//         setState(
//           () => _msgs.add(_Msg('Camera busy, try again…', isUser: false)),
//         );
//         return;
//       }

//       // Add user message
//       setState(() => _msgs.add(_Msg(prompt, isUser: true)));

//       // Add placeholder for AI response
//       final aiMsg = _Msg('', isUser: false, isStreaming: true);
//       setState(() => _msgs.add(aiMsg));

//       String previousResponse = '';

//       await _service.sendWithStreaming(
//         text: '$_systemCtx\nUser: $prompt',
//         image: file,
//         onToken: (token) {
//           if (!mounted) return;

//           // Update streaming TTS with new content
//           _streamingTts.addText(token, previousResponse);
//           previousResponse = token;

//           setState(() {
//             aiMsg.text = token;
//           });
//         },
//         onComplete: (stats) {
//           if (!mounted) return;
//           setState(() {
//             aiMsg.isStreaming = false;
//             aiMsg.stats = stats;
//           });
//         },
//       );
//     } catch (e) {
//       setState(() => _msgs.add(_Msg('Error: $e', isUser: false)));
//     }
//   }

//   Future<void> _sendTextOnly(String prompt) async {
//     try {
//       // Add user message
//       setState(() => _msgs.add(_Msg(prompt, isUser: true)));

//       // Add placeholder for AI response
//       final aiMsg = _Msg('', isUser: false, isStreaming: true);
//       setState(() => _msgs.add(aiMsg));

//       String previousResponse = '';

//       await _service.sendWithStreaming(
//         text: '$_systemCtx\nUser: $prompt',
//         onToken: (token) {
//           if (!mounted) return;

//           // Update streaming TTS with new content
//           _streamingTts.addText(token, previousResponse);
//           previousResponse = token;

//           setState(() {
//             aiMsg.text = token;
//           });
//         },
//         onComplete: (stats) {
//           if (!mounted) return;
//           setState(() {
//             aiMsg.isStreaming = false;
//             aiMsg.stats = stats;
//           });
//         },
//       );
//     } catch (e) {
//       setState(() => _msgs.add(_Msg('Error: $e', isUser: false)));
//     }
//   }

//   Future<File?> _safeTakePicture() async {
//     if (_camera == null || !_camera!.value.isInitialized) {
//       try {
//         await _camera!.initialize();
//         setState(() => _cameraReady = true);
//       } catch (_) {
//         return null;
//       }
//     }
//     if (_camera!.value.isTakingPicture) return null;
//     final xFile = await _camera!.takePicture();
//     return File(xFile.path);
//   }

//   Future<File?> _captureIpCameraImage() async {
//     try {
//       if (_ipCameraWebView != null) {
//         final screenshot = await _ipCameraWebView!.takeScreenshot();
//         if (screenshot != null) {
//           final tempDir = await getTemporaryDirectory();
//           final tempFile = File('${tempDir.path}/ip_camera_capture.jpg');
//           await tempFile.writeAsBytes(screenshot);
//           return tempFile;
//         }
//       }
//     } catch (e) {
//       print('Error capturing IP camera image: $e');
//     }
//     return null;
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_initialising) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Gemma Vision Chat'),
//         actions: [
//           IconButton(icon: const Icon(Icons.refresh), onPressed: _resetChat),
//           IconButton(
//             icon: const Icon(Icons.settings),
//             onPressed: _showSettingsDialog,
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             flex: 3,
//             child: _cameraSource == CameraSource.phone && _camera != null
//                 ? _CameraPreviewBox(camera: _camera!)
//                 : _IpCameraPreviewBox(
//                     ipCameraUrl: _ipCameraUrl,
//                     onWebViewCreated: (controller) {
//                       _ipCameraWebView = controller;
//                     },
//                   ),
//           ),
//           Expanded(
//             flex: 4,
//             child: ListView.builder(
//               padding: const EdgeInsets.all(8),
//               itemCount: _msgs.length,
//               itemBuilder: (_, i) => _ChatBubble(msg: _msgs[i]),
//             ),
//           ),
//           const Divider(height: 1),
//           Padding(
//             padding: const EdgeInsets.all(8),
//             child: _PromptBar(
//               key: _promptBarKey,
//               onPromptWithPhoto: _captureAndSend,
//               onPromptTextOnly: _sendTextOnly,
//               disabled: _resetting,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _showSettingsDialog() async {
//     final ctxCtl = TextEditingController(text: _systemCtx);
//     final ipCtl = TextEditingController(text: _ipCameraUrl);
//     double tmpRate = _speechRate;
//     PreferredBackend tmpBackend = _backend;
//     CameraSource tmpCameraSource = _cameraSource;

//     final result = await showDialog<bool>(
//       context: context,
//       builder: (ctx) => StatefulBuilder(
//         builder: (context, setDialogState) => AlertDialog(
//           title: const Text('Settings'),
//           content: SingleChildScrollView(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(
//                   controller: ctxCtl,
//                   maxLines: 3,
//                   decoration: const InputDecoration(
//                     labelText: 'System context',
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//                 DropdownButtonFormField<CameraSource>(
//                   value: tmpCameraSource,
//                   items: const [
//                     DropdownMenuItem(
//                       value: CameraSource.phone,
//                       child: Text('Phone Camera'),
//                     ),
//                     DropdownMenuItem(
//                       value: CameraSource.ip,
//                       child: Text('IP Camera'),
//                     ),
//                   ],
//                   onChanged: (v) => setDialogState(() => tmpCameraSource = v!),
//                   decoration: const InputDecoration(labelText: 'Camera Source'),
//                 ),
//                 if (tmpCameraSource == CameraSource.ip) ...[
//                   const SizedBox(height: 16),
//                   TextField(
//                     controller: ipCtl,
//                     decoration: const InputDecoration(
//                       labelText: 'IP Camera URL',
//                       hintText: 'http://192.168.4.1',
//                     ),
//                   ),
//                 ],
//                 const SizedBox(height: 16),
//                 DropdownButtonFormField<PreferredBackend>(
//                   value: tmpBackend,
//                   items: PreferredBackend.values
//                       .map(
//                         (b) => DropdownMenuItem(
//                           value: b,
//                           child: Text(b.name.toUpperCase()),
//                         ),
//                       )
//                       .toList(),
//                   onChanged: (v) => tmpBackend = v!,
//                   decoration: const InputDecoration(labelText: 'Backend'),
//                 ),
//                 const SizedBox(height: 16),
//                 Text('Speech rate: ${tmpRate.toStringAsFixed(2)}'),
//                 Slider(
//                   min: 0.5,
//                   max: 2,
//                   divisions: 15,
//                   value: tmpRate,
//                   onChanged: (v) => setDialogState(() => tmpRate = v),
//                 ),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(ctx, false),
//               child: const Text('Cancel'),
//             ),
//             ElevatedButton(
//               onPressed: () => Navigator.pop(ctx, true),
//               child: const Text('Save'),
//             ),
//           ],
//         ),
//       ),
//     );
//     if (result == true) {
//       final prefs = await SharedPreferences.getInstance();

//       setState(() {
//         _systemCtx = ctxCtl.text.trim();
//         _speechRate = tmpRate;

//         // Handle camera source change
//         if (_cameraSource != tmpCameraSource || _ipCameraUrl != ipCtl.text) {
//           _cameraSource = tmpCameraSource;
//           _ipCameraUrl = ipCtl.text;

//           // Save preferences
//           prefs.setInt('camera_source', _cameraSource.index);
//           prefs.setString('ip_camera_url', _ipCameraUrl);

//           // Re-initialize camera
//           _cameraReady = false;
//           if (_cameraSource == CameraSource.phone) {
//             _ipCameraWebView = null;
//           } else {
//             _camera?.dispose();
//             _camera = null;
//           }
//           _initializeCamera().then((_) {
//             if (mounted) setState(() {});
//           });
//         }

//         if (_backend != tmpBackend) {
//           _backend = tmpBackend;
//           _msgs.clear();
//           _initialising = true;
//           _redirectedOnError = false;
//           _bootstrap();
//         }
//       });
//       await _tts.setSpeechRate(_speechRate);
//     }
//   }
// }

// /// ---------------------------------------------------------------------------
// ///  WIDGETS
// /// ---------------------------------------------------------------------------

// class _CameraPreviewBox extends StatelessWidget {
//   final CameraController camera;
//   const _CameraPreviewBox({required this.camera});

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (_, constraints) {
//         final ratio = camera.value.aspectRatio;
//         var w = constraints.maxWidth;
//         var h = w / ratio;
//         if (h > constraints.maxHeight) {
//           h = constraints.maxHeight;
//           w = h * ratio;
//         }
//         return Center(
//           child: SizedBox(width: w, height: h, child: CameraPreview(camera)),
//         );
//       },
//     );
//   }
// }

// class _IpCameraPreviewBox extends StatelessWidget {
//   final String ipCameraUrl;
//   final Function(InAppWebViewController)? onWebViewCreated;

//   const _IpCameraPreviewBox({required this.ipCameraUrl, this.onWebViewCreated});

//   String get _htmlContent =>
//       '''
//     <!DOCTYPE html>
//     <html>
//       <head>
//         <meta name="viewport" content="width=device-width, initial-scale=1.0">
//         <style>
//           body {
//             margin: 0;
//             padding: 0;
//             background-color: black;
//             display: flex;
//             justify-content: center;
//             align-items: center;
//             height: 100vh;
//             overflow: hidden;
//           }
//           img {
//             max-width: 100%;
//             max-height: 100%;
//             width: auto;
//             height: auto;
//             object-fit: contain;
//           }
//         </style>
//       </head>
//       <body>
//         <img src="$ipCameraUrl" onerror="this.style.display='none'; document.getElementById('error').style.display='block';" />
//         <div id="error" style="display:none; color:white; text-align:center;">
//           <p>Connecting to IP Camera...</p>
//           <p style="font-size:12px;">$ipCameraUrl</p>
//         </div>
//       </body>
//     </html>
//   ''';

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       color: Colors.black,
//       child: InAppWebView(
//         initialData: InAppWebViewInitialData(
//           data: _htmlContent,
//           baseUrl: WebUri(ipCameraUrl),
//           encoding: 'utf-8',
//           mimeType: 'text/html',
//         ),
//         onWebViewCreated: onWebViewCreated,
//         initialSettings: InAppWebViewSettings(
//           javaScriptEnabled: true,
//           allowsInlineMediaPlayback: true,
//           mediaPlaybackRequiresUserGesture: false,
//           userAgent: "Mozilla/5.0",
//           mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
//         ),
//       ),
//     );
//   }
// }

// class _Msg {
//   String text;
//   final bool isUser;
//   bool isStreaming;
//   MessageStats? stats;

//   _Msg(this.text, {required this.isUser, this.isStreaming = false, this.stats});
// }

// class _ChatBubble extends StatelessWidget {
//   final _Msg msg;
//   const _ChatBubble({required this.msg});

//   @override
//   Widget build(BuildContext ctx) => Column(
//     crossAxisAlignment: msg.isUser
//         ? CrossAxisAlignment.end
//         : CrossAxisAlignment.start,
//     children: [
//       Align(
//         alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
//         child: Container(
//           margin: const EdgeInsets.symmetric(vertical: 4),
//           padding: const EdgeInsets.all(12),
//           decoration: BoxDecoration(
//             color: msg.isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Use GptMarkdown widget for AI responses, plain text for user messages
//               if (msg.isUser)
//                 Text(msg.text)
//               else
//                 GptMarkdown(msg.text, style: const TextStyle(fontSize: 14)),
//               if (msg.isStreaming && !msg.isUser)
//                 const Padding(
//                   padding: EdgeInsets.only(top: 4),
//                   child: SizedBox(
//                     width: 12,
//                     height: 12,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2,
//                       valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ),
//       // Show stats for AI messages
//       if (!msg.isUser && msg.stats != null && !msg.isStreaming)
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
//           child: _StatsWidget(stats: msg.stats!),
//         ),
//     ],
//   );
// }

// class _StatsWidget extends StatelessWidget {
//   final MessageStats stats;
//   const _StatsWidget({required this.stats});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(8),
//       decoration: BoxDecoration(
//         color: Colors.black.withOpacity(0.05),
//         borderRadius: BorderRadius.circular(6),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Icon(Icons.speed, size: 12, color: Colors.grey),
//           const SizedBox(width: 4),
//           Text(
//             _buildStatsText(),
//             style: const TextStyle(fontSize: 11, color: Colors.grey),
//           ),
//         ],
//       ),
//     );
//   }

//   String _buildStatsText() {
//     final parts = <String>[];

//     if (stats.timeToFirstToken != null) {
//       parts.add('TTFT: ${stats.timeToFirstToken!.toStringAsFixed(2)}s');
//     }

//     if (stats.totalLatency != null) {
//       parts.add('Total: ${stats.totalLatency!.toStringAsFixed(2)}s');
//     }

//     if (stats.prefillSpeed != null) {
//       parts.add('Prefill: ${stats.prefillSpeed!.toStringAsFixed(1)} t/s');
//     }

//     if (stats.decodeSpeed != null) {
//       parts.add('Decode: ${stats.decodeSpeed!.toStringAsFixed(1)} t/s');
//     }

//     if (stats.tokenCount != null) {
//       parts.add('${stats.tokenCount} tokens');
//     }

//     return parts.join(' • ');
//   }
// }

// class _PromptBar extends StatefulWidget {
//   final Future<void> Function(String) onPromptWithPhoto;
//   final Future<void> Function(String) onPromptTextOnly;
//   final bool disabled;
//   const _PromptBar({
//     required this.onPromptWithPhoto,
//     required this.onPromptTextOnly,
//     this.disabled = false,
//     Key? key,
//   }) : super(key: key);

//   @override
//   State<_PromptBar> createState() => _PromptBarState();
// }

// class _PromptBarState extends State<_PromptBar> {
//   final _ctrl = TextEditingController();
//   final SpeechToText _speech = SpeechToText();
//   bool _speechEnabled = false;
//   bool _listening = false;
//   bool _sending = false;

//   @override
//   void initState() {
//     super.initState();
//     _initializeSpeech();
//   }

//   Future<void> _initializeSpeech() async {
//     _speechEnabled = await _speech.initialize(
//       onStatus: (_) {},
//       onError: (_) {},
//     );
//     if (mounted) setState(() {});
//   }

//   Future<void> _sendWithPhoto(String prompt) async {
//     if (widget.disabled || _sending) return;
//     if (_listening) {
//       _listening = false;
//       await _speech.stop();
//     }
//     final txt = prompt.trim();
//     if (txt.isEmpty) return;
//     _ctrl.clear();
//     setState(() => _sending = true);
//     try {
//       await widget.onPromptWithPhoto(txt);
//     } finally {
//       if (mounted) setState(() => _sending = false);
//     }
//   }

//   Future<void> _sendTextOnly(String prompt) async {
//     if (widget.disabled || _sending) return;
//     if (_listening) {
//       _listening = false;
//       await _speech.stop();
//     }
//     final txt = prompt.trim();
//     if (txt.isEmpty) return;
//     _ctrl.clear();
//     setState(() => _sending = true);
//     try {
//       await widget.onPromptTextOnly(txt);
//     } finally {
//       if (mounted) setState(() => _sending = false);
//     }
//   }

//   Future<void> _toggleListening() async {
//     if (widget.disabled || !_speechEnabled) return;
//     if (_listening) {
//       _listening = false;
//       await _speech.stop();
//       if (mounted) setState(() {});
//       return;
//     }
//     await _speech.listen(
//       onResult: (val) {
//         if (!_listening) return;
//         setState(() {
//           _ctrl.text = val.recognizedWords;
//           _ctrl.selection = TextSelection.fromPosition(
//             TextPosition(offset: _ctrl.text.length),
//           );
//         });
//       },
//     );
//     setState(() => _listening = true);
//   }

//   @override
//   void dispose() {
//     _speech.stop();
//     _speech.cancel();
//     _ctrl.dispose();
//     super.dispose();
//   }

//   void clear() => _ctrl.clear();

//   @override
//   Widget build(BuildContext context) {
//     final disabled = widget.disabled || _sending;
//     return SafeArea(
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: TextField(
//                   controller: _ctrl,
//                   enabled: !disabled,
//                   decoration: const InputDecoration(hintText: 'Custom prompt…'),
//                   onSubmitted: _sendWithPhoto,
//                 ),
//               ),
//               IconButton(
//                 icon: Icon(_listening ? Icons.mic : Icons.mic_none),
//                 tooltip: _speechEnabled
//                     ? (_listening ? 'Stop dictation' : 'Start dictation')
//                     : 'Dictation unavailable',
//                 onPressed: disabled || !_speechEnabled
//                     ? null
//                     : _toggleListening,
//               ),
//               const SizedBox(width: 4),
//               Semantics(
//                 label: 'Send',
//                 child: ElevatedButton(
//                   onPressed: disabled ? null : () => _sendTextOnly(_ctrl.text),
//                   child: _sending
//                       ? const SizedBox(
//                           width: 16,
//                           height: 16,
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         )
//                       : const Icon(Icons.send),
//                 ),
//               ),
//               const SizedBox(width: 4),
//               Semantics(
//                 label: 'Send with photo',
//                 child: ElevatedButton(
//                   onPressed: disabled ? null : () => _sendWithPhoto(_ctrl.text),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Theme.of(context).primaryColor,
//                     foregroundColor: Colors.white,
//                   ),
//                   child: _sending
//                       ? const SizedBox(
//                           width: 16,
//                           height: 16,
//                           child: CircularProgressIndicator(
//                             strokeWidth: 2,
//                             color: Colors.white,
//                           ),
//                         )
//                       : const Icon(Icons.camera_alt),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Wrap(
//             alignment: WrapAlignment.spaceEvenly,
//             spacing: 8,
//             children: [
//               _quick('Describe the room', disabled),
//               _quick('Tell me what you see', disabled),
//               _quick('Find an exit', disabled),
//               _quick('Read text', disabled),
//               _quick('Summarise this', disabled),
//               _quick('Identify obstacles', disabled),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _quick(String label, bool disabled) => ElevatedButton(
//     onPressed: disabled ? null : () => _sendWithPhoto(label),
//     child: Text(label, textAlign: TextAlign.center),
//   );
// }
