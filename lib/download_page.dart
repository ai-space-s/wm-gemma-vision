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

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

const _hfClientId = '56370c68-410e-4af9-998b-baf53df6cc0c';
const _hfRedirectUri = 'com.tommasogiovannini.gemma://oauthredirect';
const _authEndpoint = 'https://huggingface.co/oauth/authorize';
const _tokenEndpoint = 'https://huggingface.co/oauth/token';
const _scope = 'openid profile read-repos';

const _modelName = 'gemma-3n-E2B-it-int4.task';
const _modelFullName = 'Gemma 3n E2B IT Int4';
const _downloadUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$_modelName?download=true';

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
  final String _modelSize = '3.14 GB';
  int? _totalBytes;

  final port = ReceivePort();
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      'downloader_send_port',
    );
    port.listen(_onDownloadStatus);
    _initDownloadState();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    port.close();
    super.dispose();
  }

  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    // Check download status every minute
    _statusCheckTimer = Timer.periodic(const Duration(minutes: 1), (
      timer,
    ) async {
      if (!_downloading || _taskId == null) {
        timer.cancel();
        return;
      }

      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_modelName.tmp');

        if (_totalBytes != null && await file.exists()) {
          final currentBytes = await file.length();
          final calculatedProgress = (currentBytes / _totalBytes!).clamp(
            0.0,
            1.0,
          );
          if (calculatedProgress > _progress) {
            setState(() {
              _progress = calculatedProgress;
            });
          }
        }
      } catch (_) {}

      final tasks = await FlutterDownloader.loadTasks();
      if (tasks != null) {
        for (final task in tasks) {
          if (task.taskId == _taskId) {
            final newProgress = task.progress / 100.0;
            if (newProgress > _progress) {
              setState(() {
                _progress = newProgress;
              });
            }

            if (task.status == DownloadTaskStatus.complete) {
              timer.cancel();
              _goToChat();
            } else if (task.status == DownloadTaskStatus.failed) {
              timer.cancel();
              setState(() {
                _error = 'Download failed';
                _downloading = false;
              });
            }
            break;
          }
        }
      }
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
          _statusCheckTimer?.cancel();
          _goToChat();
        } else if (status == DownloadTaskStatus.failed.index) {
          _statusCheckTimer?.cancel();
          _error = 'Download failed';
          _downloading = false;
        }
      });
    }
  }

  /// Cancels the in-flight download, deletes any partial file, and resets UI state.
  Future<void> _cancelDownload() async {
    if (_taskId == null) return;

    // 1) Cancel the system download task
    await FlutterDownloader.cancel(taskId: _taskId!);

    // 2) Remove it (and delete any partial data) from FlutterDownloader
    await FlutterDownloader.remove(taskId: _taskId!, shouldDeleteContent: true);

    // 3) Delete any leftover file on disk
    final dir = await getApplicationDocumentsDirectory();
    final fullPath = '${dir.path}/$_modelName';
    final f = File(fullPath);
    if (await f.exists()) {
      await f.delete();
    }

    // 4) Reset our state so user can retry
    setState(() {
      _taskId = null;
      _downloading = false;
      _progress = 0.0;
      _error = null;
    });
  }

  Future<void> _initDownloadState() async {
    setState(() => _checking = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_modelName');

      if (await file.exists()) {
        // Check it’s not zero-length (or too small to be the real model)
        final bytes = await file.length();
        if (bytes > 0) {
          // Looks like a valid file—proceed to chat
          _goToChat();
          return;
        } else {
          // Corrupt or empty file—delete and fall through to download UI
          await file.delete();
        }
      }

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
              _startStatusCheckTimer();
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
      // ignore
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _onDownload() async {
    setState(() {
      _checking = true;
      _error = null;
    });

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

    setState(() {
      _checking = false;
      _downloading = true;
      _progress = 0.0;
    });
    _startStatusCheckTimer();
    final dir = await getApplicationDocumentsDirectory();
    _taskId = await FlutterDownloader.enqueue(
      url: _downloadUrl,
      headers: tok != null ? {'Authorization': 'Bearer $tok'} : {},
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

  Future<void> _showCancelConfirmation() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Download?'),
        content: const Text(
          'Are you sure you want to cancel the download? You’ll have to start over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Downloading'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel Download'),
          ),
        ],
      ),
    );

    if (shouldCancel == true) {
      await _cancelDownload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Checking model status...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _downloading
                    ? Icons.downloading_outlined
                    : Icons.download_rounded,
                size: 64,
                color: Colors.blue,
              ),
              const SizedBox(height: 32),
              Text(
                _downloading ? 'Downloading Model' : 'Download Model',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _modelFullName,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              if (!_downloading)
                Text(
                  'You might need to create a free HuggingFace account to accept the model license.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 48),

              if (_downloading) ...[
                // Progress bar
                Container(
                  height: 8,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                  onPressed: _showCancelConfirmation,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel Download'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ] else ...[
                // Storage requirement card
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _onDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _error != null
          ? Container(
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
            )
          : null,
    );
  }
}
