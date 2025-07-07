import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'camera.dart';

// ── REQUIRED TOP‐LEVEL CALLBACK ────────────────────────────────────────────────
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

// ── CONFIG ───────────────────────────────────────────────────────────────────
const _hfClientId = '56370c68-410e-4af9-998b-baf53df6cc0c';
const _hfRedirectUri = 'com.tommasogiovannini.gemma://oauthredirect';
const _authEndpoint = 'https://huggingface.co/oauth/authorize';
const _tokenEndpoint = 'https://huggingface.co/oauth/token';
const _scope = 'openid profile read-repos';

const _modelName = 'gemma-3n-E2B-it-int4.task';
const _downloadUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$_modelName?download=true';

// ── TOKEN STORE ──────────────────────────────────────────────────────────────
class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'hf_access_token';
  static const _kExpiry = 'hf_expires_at';

  Future<String?> readAccessToken() async {
    final tok = await _storage.read(key: _kToken);
    final expiry = await _storage.read(key: _kExpiry);
    if (tok == null || expiry == null) return null;
    final expMs = int.tryParse(expiry)!;
    if (DateTime.now().millisecondsSinceEpoch >= expMs - 300000) {
      return null;
    }
    return tok;
  }

  Future<void> writeToken(String token, String refresh, int expiresIn) async {
    final expMs = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch
        .toString();
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kExpiry, value: expMs),
    ]);
  }
}

final _tokenStore = TokenStore();

// ── PKCE HELPER ──────────────────────────────────────────────────────────────
class _Pkce {
  final String verifier, challenge;
  _Pkce._(this.verifier, this.challenge);

  factory _Pkce.generate() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final v = base64UrlEncode(bytes).replaceAll('=', '');
    final c = base64UrlEncode(
      sha256.convert(utf8.encode(v)).bytes,
    ).replaceAll('=', '');
    return _Pkce._(v, c);
  }
}

// ── DOWNLOAD PAGE ─────────────────────────────────────────────────────────────
class DownloadPage extends StatefulWidget {
  const DownloadPage({Key? key}) : super(key: key);
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  String? _taskId;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0.0;
  String? _error;
  final port = ReceivePort();

  @override
  void initState() {
    super.initState();

    // 1) register port for background callback
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      'downloader_send_port',
    );
    port.listen(_onDownloadStatus);

    // 2) inspect disk + any in-flight tasks
    _initDownloadState();
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    port.close();
    super.dispose();
  }

  Future<void> _cancelDownload() async {
    if (_taskId == null) return;

    // 1) Cancel the task in the system
    await FlutterDownloader.cancel(taskId: _taskId!);

    // 2) Remove it from FlutterDownloader (and delete any partial data)
    await FlutterDownloader.remove(taskId: _taskId!, shouldDeleteContent: true);

    // 3) Delete any leftover file on disk
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelName');
    if (await file.exists()) {
      await file.delete();
    }

    // 4) Reset UI state
    setState(() {
      _taskId = null;
      _downloading = false;
      _progress = 0.0;
      _error = null;
    });
  }

  void _onDownloadStatus(dynamic message) {
    final data = message as List;
    final id = data[0] as String;
    final status = data[1] as int;
    final prog = data[2] as int;
    if (id == _taskId) {
      setState(() {
        _progress = prog / 100.0;
        if (status == DownloadTaskStatus.complete.index) {
          _goToChat();
        } else if (status == DownloadTaskStatus.failed.index) {
          _error = 'Download failed';
          _downloading = false;
        }
      });
    }
  }

  Future<void> _initDownloadState() async {
    setState(() => _checking = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fp = '${dir.path}/$_modelName';
      final file = File(fp);

      if (await file.exists()) {
        // model already on disk → go straight to Chat
        _goToChat();
        return;
      }

      // no file: check for any in-progress downloader task
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks != null) {
        for (final t in tasks) {
          if (t.filename == _modelName) {
            _taskId = t.taskId;
            final status = t.status;
            final prog = t.progress;
            if (status == DownloadTaskStatus.running ||
                status == DownloadTaskStatus.paused) {
              setState(() {
                _downloading = true;
                _progress = prog / 100.0;
              });
            } else if (status == DownloadTaskStatus.complete) {
              _goToChat();
            } else if (status == DownloadTaskStatus.failed) {
              setState(() => _error = 'Previous download failed');
            }
            break;
          }
        }
      }
    } catch (_) {
      // ignore errors
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _onDownload() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    // OAuth + token fetch...
    String? tok = await _tokenStore.readAccessToken();
    try {
      final head = await http.head(Uri.parse(_downloadUrl));
      if ([401, 403].contains(head.statusCode)) {
        final pk = _Pkce.generate();
        final uri = Uri.parse(_authEndpoint).replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': _hfClientId,
            'redirect_uri': _hfRedirectUri,
            'scope': _scope,
            'code_challenge': pk.challenge,
            'code_challenge_method': 'S256',
          },
        );

        final result = await FlutterWebAuth2.authenticate(
          url: uri.toString(),
          callbackUrlScheme: 'com.tommasogiovannini.gemma',
        );
        final resUri = Uri.parse(result);
        if (resUri.queryParameters['error'] != null) {
          throw Exception('OAuth error');
        }
        final code = resUri.queryParameters['code'];
        if (code == null) throw Exception('No authorization code');

        final resp = await http.post(
          Uri.parse(_tokenEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'authorization_code',
            'client_id': _hfClientId,
            'code': code,
            'redirect_uri': _hfRedirectUri,
            'code_verifier': pk.verifier,
          },
        );
        if (resp.statusCode != 200) {
          throw Exception('Token exchange failed');
        }
        final body = jsonDecode(resp.body);
        tok = body['access_token'];
        await _tokenStore.writeToken(
          body['access_token'],
          body['refresh_token'] ?? '',
          body['expires_in'] ?? 0,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _checking = false;
      });
      return;
    }

    // enqueue background download
    setState(() {
      _checking = false;
      _downloading = true;
      _progress = 0.0;
    });

    final dir = await getApplicationDocumentsDirectory();
    _taskId = await FlutterDownloader.enqueue(
      url: _downloadUrl,
      headers: tok != null
          ? {'Authorization': 'Bearer $tok'}
          : <String, String>{},
      savedDir: dir.path,
      fileName: _modelName,
      showNotification: true,
      openFileFromNotification: false,
    );
  }

  void _goToChat() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Download & Init Model')),
      body: Center(
        child: _downloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress %
                  Text('${(_progress * 100).toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  // Rounded outline “Cancel” button with cross icon
                  OutlinedButton.icon(
                    onPressed: _cancelDownload,
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              )
            : ElevatedButton(
                onPressed: _onDownload,
                child: const Text('Download Model'),
              ),
      ),
      bottomSheet: _error != null
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : null,
    );
  }
}
