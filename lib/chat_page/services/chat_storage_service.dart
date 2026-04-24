// lib/chat_page/services/chat_storage_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import '../models/message_models.dart';

class ChatSaveInfo {
  final String id;
  final String name;
  final DateTime updatedAt;

  ChatSaveInfo({required this.id, required this.name, required this.updatedAt});
}

class ChatSaveData {
  final ChatSaveInfo info;
  final List<ChatMessage> messages;

  ChatSaveData({required this.info, required this.messages});
}

class ChatStorageService {
  ChatStorageService._internal();
  static final ChatStorageService instance = ChatStorageService._internal();

  static const _indexFileName = 'index.json';
  static const _chatFileName = 'chat.json';
  static const _imagesDirName = 'images';

  Future<Directory> _baseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = _join(dir.path, 'chat_history');
    final base = Directory(path);
    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }
    return base;
  }

  Future<List<ChatSaveInfo>> listSaves() async {
    final base = await _baseDir();
    final indexFile = File(_join(base.path, _indexFileName));
    if (!indexFile.existsSync()) return [];
    final data =
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map((item) {
      return ChatSaveInfo(
        id: item['id'] as String,
        name: item['name'] as String,
        updatedAt: DateTime.parse(item['updatedAt'] as String),
      );
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<ChatSaveData?> loadChat(String id) async {
    final base = await _baseDir();
    final safeId = _sanitizeId(id);
    if (safeId != id) return null;
    final chatDir = Directory(_join(base.path, safeId));
    final chatFile = File(_join(chatDir.path, _chatFileName));
    if (!chatFile.existsSync()) return null;
    final payload =
        jsonDecode(await chatFile.readAsString()) as Map<String, dynamic>;
    final info = ChatSaveInfo(
      id: payload['id'] as String,
      name: payload['name'] as String,
      updatedAt: DateTime.parse(payload['updatedAt'] as String),
    );
    final messages = <ChatMessage>[];
    final items = (payload['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final item in items) {
      final text = (item['text'] as String?) ?? '';
      final isUser = item['isUser'] as bool? ?? false;
      final imageRelPath = item['imagePath'] as String?;
      if (imageRelPath != null && imageRelPath.isNotEmpty) {
        final imageFile = File(_join(chatDir.path, imageRelPath));
        if (imageFile.existsSync()) {
          messages.add(
            ChatMessage.withImageFile(
              text,
              isUser: isUser,
              imageFile: imageFile,
            ),
          );
          continue;
        }
      }
      messages.add(ChatMessage.text(text, isUser: isUser));
    }
    return ChatSaveData(info: info, messages: messages);
  }

  Future<ChatSaveInfo?> findSaveByName(String name) async {
    final items = await listSaves();
    for (final item in items) {
      if (item.name == name) return item;
    }
    return null;
  }

  Future<ChatSaveInfo> saveChat({
    required String name,
    String? existingId,
    required List<ChatMessage> messages,
  }) async {
    final base = await _baseDir();
    final id = existingId == null ? _sanitizeId(name) : _sanitizeId(existingId);
    final chatDir = Directory(_join(base.path, id));
    if (!chatDir.existsSync()) {
      chatDir.createSync(recursive: true);
    }
    final imagesDir = Directory(_join(chatDir.path, _imagesDirName));
    if (!imagesDir.existsSync()) {
      imagesDir.createSync(recursive: true);
    }

    final now = DateTime.now();
    final savedMessages = <Map<String, dynamic>>[];

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      String? imagePath;
      if (msg.imageFile != null) {
        imagePath = await _copyImageFile(imagesDir, msg.imageFile!, 'msg_$i');
      } else if (msg.imageBytes != null) {
        imagePath = await _writeImageBytes(
          imagesDir,
          msg.imageBytes!,
          'msg_$i',
        );
      }

      savedMessages.add({
        'text': msg.text,
        'isUser': msg.isUser,
        'imagePath': imagePath,
      });
    }

    final payload = {
      'id': id,
      'name': name,
      'updatedAt': now.toIso8601String(),
      'messages': savedMessages,
    };

    final chatFile = File(_join(chatDir.path, _chatFileName));
    await chatFile.writeAsString(jsonEncode(payload));
    await _updateIndex(ChatSaveInfo(id: id, name: name, updatedAt: now));
    return ChatSaveInfo(id: id, name: name, updatedAt: now);
  }

  Future<void> _updateIndex(ChatSaveInfo info) async {
    final base = await _baseDir();
    final indexFile = File(_join(base.path, _indexFileName));
    final items = await listSaves();
    final updated = <ChatSaveInfo>[
      info,
      for (final item in items)
        if (item.id != info.id) item,
    ];
    final payload = {
      'items': updated
          .map(
            (item) => {
              'id': item.id,
              'name': item.name,
              'updatedAt': item.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    };
    await indexFile.writeAsString(jsonEncode(payload));
  }

  Future<String> _copyImageFile(
    Directory imagesDir,
    File source,
    String baseName,
  ) async {
    final ext = _extensionFromPath(source.path);
    final fileName = '$baseName$ext';
    final target = File(_join(imagesDir.path, fileName));
    if (!target.existsSync() || target.path != source.path) {
      await source.copy(target.path);
    }
    return _join(_imagesDirName, fileName);
  }

  Future<String> _writeImageBytes(
    Directory imagesDir,
    Uint8List bytes,
    String baseName,
  ) async {
    final fileName = '$baseName.jpg';
    final target = File(_join(imagesDir.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    return _join(_imagesDirName, fileName);
  }

  String _sanitizeId(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'chat_${DateTime.now().millisecondsSinceEpoch}';
    }
    return cleaned;
  }

  String _extensionFromPath(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1 || idx == path.length - 1) return '.jpg';
    return path.substring(idx);
  }

  String _join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }
}
