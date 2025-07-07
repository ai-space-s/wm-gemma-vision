import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Encapsulates all Gemma setup & chat logic.
class GemmaService {
  final _gemma = FlutterGemmaPlugin.instance;
  late final InferenceModel _model;
  late final _chat;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/gemma-3n-E2B-it-int4.task';

    await _gemma.modelManager.setModelPath(path);
    _model = await _gemma.createModel(
      preferredBackend: PreferredBackend.cpu,
      modelType: ModelType.gemmaIt,
      supportImage: true,
      maxTokens: 4096,
      maxNumImages: 1,
    );
    _chat = await _model.createChat(
      randomSeed: 1,
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
    );
  }

  Future<String> send({String? text, File? image}) async {
    if (image != null && (text?.isNotEmpty ?? false)) {
      // text + image together
      final bytes = await image.readAsBytes();
      await _chat.addQueryChunk(
        Message.withImage(text: text!, imageBytes: bytes, isUser: true),
      );
    } else if (image != null) {
      // image only
      final bytes = await image.readAsBytes();
      await _chat.addQueryChunk(
        Message.imageOnly(imageBytes: bytes, isUser: true),
      );
    } else if (text != null && text.isNotEmpty) {
      // text only
      await _chat.addQueryChunk(Message.text(text: text, isUser: true));
    }
    return await _chat.generateChatResponse();
  }

  Future<void> dispose() async {
    await _chat.close();
    await _model.close();
    await _gemma.modelManager.deleteModel();
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _service = GemmaService();
  final _msgs = <_Msg>[];
  bool _initing = true;

  @override
  void initState() {
    super.initState();
    _service.init().then((_) => setState(() => _initing = false));
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _handleSend(String txt, File? img) async {
    setState(() => _msgs.add(_Msg(txt, true)));
    final reply = await _service.send(text: txt, image: img);
    setState(() => _msgs.add(_Msg(reply, false)));
  }

  @override
  Widget build(BuildContext c) {
    if (_initing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Initializing Chat')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              _service.dispose();
              setState(() => _msgs.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                return _ChatBubble(text: m.text, isUser: m.isUser);
              },
            ),
          ),
          const Divider(height: 1),
          InputBar(onSend: _handleSend),
        ],
      ),
    );
  }
}

class _Msg {
  final String text;
  final bool isUser;
  _Msg(this.text, this.isUser);
}

/// Chat bubble widget
class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser, Key? key})
    : super(key: key);
  @override
  Widget build(BuildContext ctx) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    ),
  );
}

class InputBar extends StatefulWidget {
  final Future<void> Function(String, File?) onSend;
  const InputBar({required this.onSend, Key? key}) : super(key: key);

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  bool _picking = false; // ← guard flag
  File? _img;

  Future<void> _pick(ImageSource src) async {
    if (_picking) return; // ← already picking
    setState(() => _picking = true);
    try {
      final x = await ImagePicker().pickImage(source: src);
      if (x != null) setState(() => _img = File(x.path));
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') {
        rethrow; // only ignore multiple_request
      }
    } finally {
      setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext ctx) => Row(
    children: [
      IconButton(
        icon: const Icon(Icons.photo),
        onPressed: _picking ? null : () => _pick(ImageSource.gallery),
      ),
      IconButton(
        icon: const Icon(Icons.camera_alt),
        onPressed: _picking ? null : () => _pick(ImageSource.camera),
      ),
      Expanded(
        child: TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            hintText: 'Type a message…',
            suffixIcon: _img != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _img = null),
                  )
                : null,
          ),
          onSubmitted: (_) => _send(),
        ),
      ),
      IconButton(
        icon: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
        onPressed: _send,
      ),
    ],
  );

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if ((txt.isEmpty && _img == null) || _sending) return;
    setState(() => _sending = true);
    await widget.onSend(txt, _img);
    _ctrl.clear();
    setState(() {
      _img = null;
      _sending = false;
    });
  }
}
