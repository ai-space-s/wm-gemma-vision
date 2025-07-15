// download_page.dart
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

import 'gemma_vision_chat.dart'; // your ChatPage

// ─────────────────────────────────────────────────────────────────────────────
//  ↓↓↓  FlutterDownloader isolate callback
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  ↓↓↓  Constants
// ─────────────────────────────────────────────────────────────────────────────
const _hfClientId = '56370c68-410e-4af9-998b-baf53df6cc0c';
const _hfRedirectUri = 'com.tommasogiovannini.gemma://oauthredirect';
const _authEndpoint = 'https://huggingface.co/oauth/authorize';
const _tokenEndpoint = 'https://huggingface.co/oauth/token';
const _scope = 'openid profile read-repos';

const _modelName = 'gemma-3n-E2B-it-int4.task';
const _modelFullName = 'Gemma 3n E2B IT Int4';
const _downloadUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$_modelName?download=true';

// ─────────────────────────────────────────────────────────────────────────────
//  ↓↓↓  Simple secure‑storage token helper
// ─────────────────────────────────────────────────────────────────────────────
class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'hf_access_token';
  static const _kExpiry = 'hf_expires_at';

  Future<String?> readAccessToken() async {
    final tok = await _storage.read(key: _kToken);
    final expiry = await _storage.read(key: _kExpiry);
    if (tok == null || expiry == null) return null;

    final expMs = int.parse(expiry);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs >= expMs - 5 * 60 * 1000) return null; // >5 min from expiry
    return tok;
  }

  Future<void> writeToken(String token, int expiresInSeconds) async {
    final expMs = DateTime.now()
        .add(Duration(seconds: expiresInSeconds))
        .millisecondsSinceEpoch;
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kExpiry, value: expMs.toString()),
    ]);
  }
}

final _tokenStore = TokenStore();

// ─────────────────────────────────────────────────────────────────────────────
//  ↓↓↓  PKCE helper
// ─────────────────────────────────────────────────────────────────────────────
class _Pkce {
  final String verifier, challenge;
  _Pkce._(this.verifier, this.challenge);

  factory _Pkce.generate() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final ver = base64UrlEncode(bytes).replaceAll('=', '');
    final chall = base64UrlEncode(
      sha256.convert(utf8.encode(ver)).bytes,
    ).replaceAll('=', '');
    return _Pkce._(ver, chall);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ↓↓↓  Download page widget
// ─────────────────────────────────────────────────────────────────────────────
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  // ── download bookkeeping ────────────────────────────────────────────────
  String? _taskId;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0.0;
  String? _error;

  static const _modelSize = '3.14 GB';
  int? _totalBytes; // filled after HEAD
  late final ReceivePort _port;
  Timer? _statusTimer;

  // ── lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Register isolate port safely (handles hot‑restart in debug)
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port = ReceivePort()..listen(_onDownloadStatus);
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );

    _initDownloadState();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _port.close();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  // ── download‑status polling every 30 s ───────────────────────────────────
  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollStatus(),
    );
  }

  Future<void> _pollStatus() async {
    if (!_downloading || _taskId == null) return;

    try {
      // 1) fallback: measure the partial file ourselves
      if (_totalBytes != null) {
        final dir = await getApplicationDocumentsDirectory();
        final tmp = File('${dir.path}/$_modelName.part'); // DownloadManager
        if (await tmp.exists()) {
          final current = await tmp.length();
          final calc = (current / _totalBytes!).clamp(0.0, 1.0);
          if (calc > _progress && mounted) {
            setState(() => _progress = calc);
          }
        }
      }

      // 2) check plugin status
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks != null) {
        final task = tasks.firstWhere(
          (t) => t.taskId == _taskId,
          orElse: () => throw 'task vanished',
        );

        final newProg = task.progress / 100.0;
        if (newProg > _progress && mounted) setState(() => _progress = newProg);

        switch (task.status) {
          case DownloadTaskStatus.complete:
            _statusTimer?.cancel();
            _goToChat();
            break;
          case DownloadTaskStatus.failed:
            _statusTimer?.cancel();
            await _cancelDownload(showError: 'Download failed');
            break;
          default:
          // nothing
        }
      }
    } catch (_) {
      // silent – polling is best‑effort
    }
  }

  // ── isolate callback handler ────────────────────────────────────────────
  void _onDownloadStatus(dynamic message) {
    final data = message as List<dynamic>;
    final id = data[0] as String;
    final statusIdx = data[1] as int;
    final progInt = data[2] as int;

    if (id == _taskId && mounted) {
      setState(() => _progress = progInt / 100.0);

      if (statusIdx == DownloadTaskStatus.complete.index) {
        _statusTimer?.cancel();
        _goToChat();
      } else if (statusIdx == DownloadTaskStatus.failed.index) {
        _statusTimer?.cancel();
        _cancelDownload(showError: 'Download failed');
      }
    }
  }

  // ── delete partial + reset UI ───────────────────────────────────────────
  Future<void> _cancelDownload({String? showError}) async {
    if (_taskId != null) {
      await FlutterDownloader.cancel(taskId: _taskId!);
      await FlutterDownloader.remove(
        taskId: _taskId!,
        shouldDeleteContent: true,
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelName');
    if (await file.exists()) await file.delete(); // remove any leftover bits

    if (mounted) {
      setState(() {
        _taskId = null;
        _downloading = false;
        _progress = 0.0;
        _error = showError;
      });
    }
  }

  // ── first‑run check: existing file? existing task? ──────────────────────
  Future<void> _initDownloadState() async {
    setState(() => _checking = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_modelName');

      // 1) model already on disk?
      if (await file.exists() && await file.length() > 0) {
        _goToChat();
        return;
      } else {
        await file.delete().catchError((_) {});
      }

      // 2) unfinished task?
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks != null) {
        for (final t in tasks) {
          if (t.filename == _modelName) {
            _taskId = t.taskId;
            switch (t.status) {
              case DownloadTaskStatus.running:
              case DownloadTaskStatus.paused:
                setState(() {
                  _downloading = true;
                  _progress = t.progress / 100.0;
                });
                _startStatusTimer();
                break;
              case DownloadTaskStatus.complete:
                _goToChat();
                break;
              case DownloadTaskStatus.failed:
                await _cancelDownload(showError: 'Previous download failed');
                break;
              default:
            }
            break;
          }
        }
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ── kick off download ───────────────────────────────────────────────────
  Future<void> _startDownload() async {
    // show spinner
    if (mounted)
      setState(() {
        _checking = true;
        _error = null;
      });

    // 1) get valid token (or null) and HEAD for size
    String? token = await _tokenStore.readAccessToken();
    _totalBytes = await _headForSize(token);

    if (_totalBytes == null) {
      // need OAuth
      try {
        token = await _performOAuth();
        _totalBytes = await _headForSize(token);
      } catch (e) {
        if (mounted)
          setState(() {
            _error = e.toString();
            _checking = false;
          });
        return;
      }
    }

    // 2) enqueue
    if (mounted)
      setState(() {
        _checking = false;
        _downloading = true;
        _progress = 0.0;
      });
    _startStatusTimer();

    final dir = await getApplicationDocumentsDirectory();
    _taskId = await FlutterDownloader.enqueue(
      url: _downloadUrl,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      savedDir: dir.path,
      fileName: _modelName,
      showNotification: false, // no user‑visible notif
      openFileFromNotification: false,
    );
  }

  // ── HEAD helper (returns size or null on unauthorised) ──────────────────
  Future<int?> _headForSize(String? token) async {
    final resp = await http.head(
      Uri.parse(_downloadUrl),
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
    );

    if (resp.statusCode == 200) {
      final len = int.tryParse(resp.headers['content-length'] ?? '');
      return len;
    } else if (resp.statusCode == 302 || resp.statusCode == 301) {
      // follow redirect once (S3 presigned)
      final loc = resp.headers['location'];
      if (loc == null) return null;
      final s3 = await http.head(Uri.parse(loc));
      return int.tryParse(s3.headers['content-length'] ?? '');
    } else {
      return null; // likely 401/403
    }
  }

  // ── OAuth dance returning access‑token ──────────────────────────────────
  Future<String> _performOAuth() async {
    final pkce = _Pkce.generate();
    final uri = Uri.parse(_authEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': _hfClientId,
        'redirect_uri': _hfRedirectUri,
        'scope': _scope,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: uri.toString(),
      callbackUrlScheme: 'com.tommasogiovannini.gemma',
    );

    final resUri = Uri.parse(result);
    if (resUri.queryParameters['error'] != null) {
      throw Exception('OAuth error: ${resUri.queryParameters['error']}');
    }

    final code = resUri.queryParameters['code'];
    if (code == null) throw Exception('No authorization code');

    final tokenResp = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _hfClientId,
        'code': code,
        'redirect_uri': _hfRedirectUri,
        'code_verifier': pkce.verifier,
      },
    );

    if (tokenResp.statusCode != 200) {
      throw Exception('Token exchange failed');
    }

    final body = jsonDecode(tokenResp.body);
    final access = body['access_token'] as String;
    final expires = body['expires_in'] as int? ?? 3600;
    await _tokenStore.writeToken(access, expires);
    return access;
  }

  // ── navigate to chat ────────────────────────────────────────────────────
  void _goToChat() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
  }

  // ── UI helpers ──────────────────────────────────────────────────────────
  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel download?'),
        content: const Text(
          'Are you sure you want to cancel? The partial file will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok == true) await _cancelDownload();
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return _buildCentered(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Checking model status…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _downloading ? _buildDownloading() : _buildIdle(),
        ),
      ),
      bottomNavigationBar: _error != null ? _buildErrorBar() : null,
    );
  }

  // widgets  ───────────────────────────────────────────────────────────────
  Widget _buildCentered(Widget child) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: Center(child: child),
  );

  Widget _buildIdle() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.download_rounded, size: 64, color: Colors.blue),
      const SizedBox(height: 32),
      Text(
        'Download Model',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        _modelFullName,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
      ),
      const SizedBox(height: 8),
      Text(
        'You might need a free Hugging Face account to accept the license.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 48),

      // storage card
      Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.storage_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Requires $_modelSize of device storage',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),

      // download button
      FilledButton.icon(
        onPressed: _startDownload,
        icon: const Icon(Icons.download_rounded),
        label: const Text('Download'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _buildDownloading() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.downloading_outlined, size: 64, color: Colors.blue),
      const SizedBox(height: 32),
      Text(
        'Downloading Model',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        _modelFullName,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
      ),
      const SizedBox(height: 48),

      // progress
      Container(
        height: 8,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '${(_progress * 100).toStringAsFixed(0)}%',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 32),

      TextButton.icon(
        onPressed: _confirmCancel,
        icon: const Icon(Icons.close),
        label: const Text('Cancel download'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    ],
  );

  Widget _buildErrorBar() => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    ),
  );
}
