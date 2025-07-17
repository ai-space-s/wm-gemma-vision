import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'gemma_vision_chat.dart';

// Constants
const _hfClientId = '56370c68-410e-4af9-998b-baf53df6cc0c';
const _hfRedirectUri = 'com.tommasogiovannini.gemma://oauthredirect';
const _authEndpoint = 'https://huggingface.co/oauth/authorize';
const _tokenEndpoint = 'https://huggingface.co/oauth/token';
const _scope = 'openid profile read-repos';

const _modelName = 'gemma-3n-E2B-it-int4.task';
const _modelFullName = 'Gemma 3n E2B IT Int4';
const _downloadUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$_modelName?download=true';
const _modelCardUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview';

// Enums
enum DownloadStatus {
  notStarted,
  checkingAccess,
  authenticating,
  awaitingLicenseAcceptance,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

enum TokenStatus { notStored, expired, valid }

// Download state persistence
class DownloadStateManager {
  static const String _downloadStateKey = 'download_state';
  static const String _downloadTaskIdKey = 'download_task_id';

  static Future<void> saveDownloadInProgress(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadStateKey, 'in_progress');
    await prefs.setString(_downloadTaskIdKey, taskId);
    Logger.info('Saved download state: in_progress with task ID: $taskId');
  }

  static Future<void> saveDownloadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadStateKey, 'completed');
    await prefs.remove(_downloadTaskIdKey);
    Logger.info('Saved download state: completed');
  }

  static Future<void> clearDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadStateKey);
    await prefs.remove(_downloadTaskIdKey);
    Logger.info('Cleared download state');
  }

  static Future<String?> getDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadStateKey);
  }

  static Future<String?> getDownloadTaskId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadTaskIdKey);
  }
}

// Data classes
class AuthTokenData {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiryTime;

  AuthTokenData({
    required this.accessToken,
    this.refreshToken,
    required this.expiryTime,
  });

  bool get isExpired => DateTime.now().isAfter(expiryTime);

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiryTime': expiryTime.toIso8601String(),
  };

  factory AuthTokenData.fromJson(Map<String, dynamic> json) => AuthTokenData(
    accessToken: json['accessToken'],
    refreshToken: json['refreshToken'],
    expiryTime: DateTime.parse(json['expiryTime']),
  );
}

class DownloadProgress {
  final int totalBytes;
  final int downloadedBytes;
  final double downloadRate;
  final Duration remainingTime;
  final DownloadTaskStatus status;

  DownloadProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    required this.downloadRate,
    required this.remainingTime,
    required this.status,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
  int get progressPercent => (progress * 100).round();
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

  @override
  String toString() => '[$formattedTime] [$level] $message';
}

class Logger {
  static final List<LogEntry> _logs = [];
  static final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();

  static Stream<LogEntry> get logStream => _logController.stream;
  static List<LogEntry> get logs => List.unmodifiable(_logs);

  static void info(String message) => _log('INFO', message);
  static void error(String message) => _log('ERROR', message);
  static void debug(String message) => _log('DEBUG', message);
  static void warning(String message) => _log('WARN', message);

  static void _log(String level, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    _logs.add(entry);
    _logController.add(entry);
    print('[$level] $message');
  }

  static String getAllLogsAsString() {
    return _logs.map((log) => log.toString()).join('\n');
  }

  static void clear() {
    _logs.clear();
  }
}

// OAuth Helper
class HuggingFaceOAuth {
  static String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static Future<String> generateAuthUrl() async {
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    Logger.debug('Generated OAuth code verifier and challenge');

    // Store code verifier for later use
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('code_verifier', codeVerifier);

    final params = {
      'client_id': _hfClientId,
      'redirect_uri': _hfRedirectUri,
      'response_type': 'code',
      'scope': _scope,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    };

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final authUrl = '$_authEndpoint?$query';
    Logger.info('Generated OAuth URL');
    return authUrl;
  }

  static Future<AuthTokenData?> exchangeCodeForToken(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final codeVerifier = prefs.getString('code_verifier');
    if (codeVerifier == null) {
      Logger.error('Code verifier not found');
      return null;
    }

    try {
      Logger.info('Exchanging authorization code for access token');
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _hfClientId,
          'code': code,
          'redirect_uri': _hfRedirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final expiryTime = DateTime.now().add(
          Duration(seconds: data['expires_in'] ?? 3600),
        );

        final tokenData = AuthTokenData(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiryTime: expiryTime,
        );

        // Store token
        await prefs.setString('auth_token', json.encode(tokenData.toJson()));
        await prefs.remove('code_verifier');

        Logger.info('Successfully obtained access token');
        return tokenData;
      } else {
        Logger.error(
          'Token exchange failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      Logger.error('Token exchange error: $e');
    }
    return null;
  }
}

// Token Manager
class TokenManager {
  static Future<TokenStatus> getTokenStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenString = prefs.getString('auth_token');

    if (tokenString == null) {
      Logger.debug('No stored token found');
      return TokenStatus.notStored;
    }

    try {
      final tokenData = AuthTokenData.fromJson(json.decode(tokenString));
      final status = tokenData.isExpired
          ? TokenStatus.expired
          : TokenStatus.valid;
      Logger.debug('Token status: $status');
      return status;
    } catch (e) {
      Logger.error('Error reading stored token: $e');
      return TokenStatus.notStored;
    }
  }

  static Future<AuthTokenData?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenString = prefs.getString('auth_token');

    if (tokenString == null) return null;

    try {
      return AuthTokenData.fromJson(json.decode(tokenString));
    } catch (e) {
      Logger.error('Error parsing stored token: $e');
      return null;
    }
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    Logger.info('Cleared stored token');
  }
}

// Download Manager using flutter_downloader
class DownloadManager {
  static String? _currentTaskId;
  static final ReceivePort _port = ReceivePort();

  static Future<void> initialize() async {
    await FlutterDownloader.initialize(debug: true);
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );
    _port.listen((dynamic data) {
      String id = data[0];
      int status = data[1];
      int progress = data[2];
      Logger.debug('Download task $id: status=$status, progress=$progress%');
    });
    FlutterDownloader.registerCallback(downloadCallback);
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName(
      'downloader_send_port',
    );
    send?.send([id, status, progress]);
  }

  static Future<int> checkModelAccess(String url, [String? accessToken]) async {
    try {
      Logger.info('Checking model access at: $url');
      final headers = <String, String>{};
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
        Logger.debug('Using access token for request');
      }

      final response = await http.head(Uri.parse(url), headers: headers);
      Logger.info('Access check response: ${response.statusCode}');
      return response.statusCode;
    } catch (e) {
      Logger.error('Network error during access check: $e');
      return -1;
    }
  }

  static Future<String?> startDownload({
    required String url,
    required String fileName,
    String? accessToken,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      // Check and request permissions properly
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+), we don't need storage permission for app-specific directories
        // But if we want to show notifications, we need notification permission
        final notificationStatus = await Permission.notification.request();
        if (!notificationStatus.isGranted) {
          Logger.warning(
            'Notification permission denied, download will continue without notifications',
          );
        }

        // Only request storage permission if targeting older Android versions
        if (await Permission.storage.isDenied) {
          final storageStatus = await Permission.storage.request();
          if (!storageStatus.isGranted) {
            Logger.warning(
              'Storage permission denied, but will try to download to app directory',
            );
          }
        }
      }

      final headers = <String, String>{};
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
        Logger.debug('Adding authorization header to download request');
      }

      Logger.info('Starting download: $fileName to ${dir.path}');
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: fileName,
        headers: headers,
        showNotification: true,
        openFileFromNotification: false,
        saveInPublicStorage: false,
      );

      _currentTaskId = taskId;
      Logger.info('Download task created with ID: $taskId');
      return taskId;
    } catch (e) {
      Logger.error('Failed to start download: $e');
      return null;
    }
  }

  static Future<void> pauseDownload() async {
    if (_currentTaskId != null) {
      await FlutterDownloader.pause(taskId: _currentTaskId!);
      Logger.info('Download paused');
    }
  }

  static Future<void> resumeDownload() async {
    if (_currentTaskId != null) {
      final newTaskId = await FlutterDownloader.resume(taskId: _currentTaskId!);
      _currentTaskId = newTaskId;
      Logger.info('Download resumed with new task ID: $newTaskId');
    }
  }

  static Future<void> cancelDownload() async {
    if (_currentTaskId != null) {
      await FlutterDownloader.cancel(taskId: _currentTaskId!);
      Logger.info('Download cancelled');
      _currentTaskId = null;
    }
  }

  static Future<void> cleanupFailedDownloads() async {
    try {
      final tasks = await getAllTasks();
      final failedTasks = tasks
          .where(
            (task) =>
                task.status == DownloadTaskStatus.failed ||
                task.status == DownloadTaskStatus.canceled,
          )
          .toList();

      for (final task in failedTasks) {
        await FlutterDownloader.remove(
          taskId: task.taskId,
          shouldDeleteContent: true,
        );
        Logger.info('Cleaned up failed/canceled download: ${task.taskId}');
      }
    } catch (e) {
      Logger.error('Error cleaning up failed downloads: $e');
    }
  }

  static Future<List<DownloadTask>> getAllTasks() async {
    return await FlutterDownloader.loadTasks() ?? [];
  }
}

// Main Download Page Widget
class ModelDownloadPage extends StatefulWidget {
  const ModelDownloadPage({Key? key}) : super(key: key);

  @override
  State<ModelDownloadPage> createState() => _ModelDownloadPageState();
}

class _ModelDownloadPageState extends State<ModelDownloadPage> {
  DownloadStatus _downloadStatus = DownloadStatus.notStarted;
  DownloadProgress? _progress;
  List<String> _errorMessages = [];
  bool _showAgreementSheet = false;
  String? _currentTaskId;
  late StreamSubscription _logSubscription;

  @override
  void initState() {
    super.initState();
    _initializeDownloader();
    _checkDownloadState();
    _setupLogListener();
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  void _setupLogListener() {
    _logSubscription = Logger.logStream.listen((logEntry) {
      // Auto-scroll to new logs if needed
      setState(() {});
    });
  }

  Future<void> _initializeDownloader() async {
    await DownloadManager.initialize();
    Logger.info('Download manager initialized');
  }

  Future<void> _checkDownloadState() async {
    // Focus on download state, not file existence
    await _checkForOngoingDownloads();
  }

  Future<bool> _checkIfModelExists() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelName');

    if (await file.exists()) {
      final fileSize = await file.length();
      Logger.info(
        'Found model file with size: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
      );

      setState(() {
        _downloadStatus = DownloadStatus.completed;
      });
      return true;
    }

    Logger.debug('Model file does not exist');
    return false;
  }

  Future<void> _checkForOngoingDownloads() async {
    try {
      // First check our saved state
      final savedState = await DownloadStateManager.getDownloadState();
      final savedTaskId = await DownloadStateManager.getDownloadTaskId();

      Logger.info(
        'Checking download state - saved: $savedState, taskId: $savedTaskId',
      );

      if (savedState == 'in_progress' && savedTaskId != null) {
        Logger.info(
          'Found saved download in progress with task ID: $savedTaskId',
        );

        // Check if this task still exists in flutter_downloader
        final tasks = await DownloadManager.getAllTasks();
        final task = tasks.firstWhere(
          (task) => task.taskId == savedTaskId,
          orElse: () => DownloadTask(
            taskId: '',
            status: DownloadTaskStatus.undefined,
            progress: 0,
            url: '',
            filename: '',
            savedDir: '',
            timeCreated: 0,
            allowCellular: true,
          ),
        );

        if (task.taskId.isNotEmpty) {
          _currentTaskId = task.taskId;
          Logger.info(
            'Found download task: ${task.taskId}, status: ${task.status}, progress: ${task.progress}%',
          );

          switch (task.status) {
            case DownloadTaskStatus.running:
              setState(() {
                _downloadStatus = DownloadStatus.downloading;
              });
              _monitorDownload(task.taskId);
              Logger.info('Resumed monitoring running download');
              break;
            case DownloadTaskStatus.paused:
              setState(() {
                _downloadStatus = DownloadStatus.paused;
              });
              _monitorDownload(task.taskId);
              Logger.info('Found paused download, showing resume option');
              break;
            case DownloadTaskStatus.enqueued:
              setState(() {
                _downloadStatus = DownloadStatus.downloading;
              });
              _monitorDownload(task.taskId);
              Logger.info('Found enqueued download, monitoring progress');
              break;
            case DownloadTaskStatus.complete:
              // Download completed while app was closed
              if (await _checkIfModelExists()) {
                await DownloadStateManager.saveDownloadCompleted();
                Logger.info(
                  'Download completed while app was closed, navigating to chat',
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => ChatPage()),
                  );
                });
              } else {
                // Task says complete but no file found
                Logger.warning(
                  'Download task complete but file not found, clearing state',
                );
                await DownloadStateManager.clearDownloadState();
                await FlutterDownloader.remove(
                  taskId: task.taskId,
                  shouldDeleteContent: false,
                );
              }
              break;
            case DownloadTaskStatus.failed:
              Logger.warning('Download failed while app was closed');
              setState(() {
                _downloadStatus = DownloadStatus.failed;
              });
              await DownloadStateManager.clearDownloadState();
              _handleError('Download failed while app was in background');
              break;
            case DownloadTaskStatus.canceled:
              Logger.info('Download was canceled while app was closed');
              await DownloadStateManager.clearDownloadState();
              break;
            default:
              // Unknown or undefined status, clean up
              Logger.warning(
                'Unknown download status: ${task.status}, cleaning up',
              );
              await DownloadStateManager.clearDownloadState();
              await FlutterDownloader.remove(
                taskId: task.taskId,
                shouldDeleteContent: false,
              );
              break;
          }
        } else {
          // Saved task ID doesn't exist in download manager anymore
          Logger.warning(
            'Saved task ID not found in download manager, checking for completed file',
          );
          await DownloadStateManager.clearDownloadState();

          // Maybe download completed and task was cleaned up, check if file exists
          if (await _checkIfModelExists()) {
            Logger.info('File exists despite missing task, navigating to chat');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => ChatPage()),
              );
            });
          }
        }
      } else if (savedState == 'completed') {
        // Previously marked as completed, check if file still exists
        if (await _checkIfModelExists()) {
          Logger.info('Download was marked complete, navigating to chat');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => ChatPage()),
            );
          });
        } else {
          // File was deleted somehow
          Logger.warning(
            'Download was marked complete but file missing, clearing state',
          );
          await DownloadStateManager.clearDownloadState();
        }
      } else {
        // No saved state or state is clear - check if file exists anyway
        if (await _checkIfModelExists()) {
          Logger.info('No saved state but file exists, navigating to chat');
          await DownloadStateManager.saveDownloadCompleted();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => ChatPage()),
            );
          });
        } else {
          Logger.info(
            'No download in progress and no file, ready for new download',
          );
        }
      }
    } catch (e) {
      Logger.error('Error checking for ongoing downloads: $e');
      await DownloadStateManager.clearDownloadState();
    }
  }

  Future<String> _getModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelName';
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloadStatus = DownloadStatus.checkingAccess;
      _errorMessages.clear();
    });

    Logger.info('Starting download process for $_modelFullName');

    // Check if model needs authentication
    final responseCode = await DownloadManager.checkModelAccess(_downloadUrl);

    if (responseCode == 200) {
      // Public model - download directly
      await _downloadModel(null);
      return;
    } else if (responseCode < 0) {
      _handleError('Network error. Please check your connection.');
      return;
    }

    // Model needs authentication
    await _handleAuthentication();
  }

  Future<void> _handleAuthentication() async {
    setState(() {
      _downloadStatus = DownloadStatus.authenticating;
    });

    Logger.info('Model requires authentication');

    final tokenStatus = await TokenManager.getTokenStatus();

    switch (tokenStatus) {
      case TokenStatus.notStored:
      case TokenStatus.expired:
        await _startOAuthFlow();
        break;
      case TokenStatus.valid:
        final token = await TokenManager.getStoredToken();
        final responseCode = await DownloadManager.checkModelAccess(
          _downloadUrl,
          token?.accessToken,
        );

        if (responseCode == 200) {
          await _downloadModel(token?.accessToken);
        } else if (responseCode == 403) {
          _showUserAgreement();
        } else {
          await _startOAuthFlow();
        }
        break;
    }
  }

  Future<void> _startOAuthFlow() async {
    try {
      Logger.info('Starting OAuth flow');
      final authUrl = await HuggingFaceOAuth.generateAuthUrl();

      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'com.tommasogiovannini.gemma',
      );

      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];

      if (code != null) {
        await _handleAuthorizationCode(code);
      } else {
        _handleError('Authorization failed: No code received');
      }
    } catch (e) {
      if (e.toString().contains('CANCELED') ||
          e.toString().contains('USER_CANCELED')) {
        setState(() {
          _downloadStatus = DownloadStatus.notStarted;
        });
        Logger.info('OAuth flow cancelled by user');
      } else {
        _handleError('Authentication failed: $e');
      }
    }
  }

  Future<void> _handleAuthorizationCode(String code) async {
    setState(() {
      _downloadStatus = DownloadStatus.authenticating;
    });

    try {
      final tokenData = await HuggingFaceOAuth.exchangeCodeForToken(code);
      if (tokenData != null) {
        final responseCode = await DownloadManager.checkModelAccess(
          _downloadUrl,
          tokenData.accessToken,
        );

        if (responseCode == 200) {
          await _downloadModel(tokenData.accessToken);
        } else if (responseCode == 403) {
          _showUserAgreement();
        } else {
          _handleError('Failed to access model with token');
        }
      } else {
        _handleError('Failed to exchange authorization code for token');
      }
    } catch (e) {
      _handleError('Authentication error: $e');
    }
  }

  void _showUserAgreement() {
    setState(() {
      _downloadStatus = DownloadStatus.awaitingLicenseAcceptance;
      _showAgreementSheet = true;
    });
    Logger.info('Model requires license acceptance');
  }

  Future<void> _downloadModel(String? accessToken) async {
    setState(() {
      _downloadStatus = DownloadStatus.downloading;
    });

    // Clean up any old failed downloads first
    await DownloadManager.cleanupFailedDownloads();

    final taskId = await DownloadManager.startDownload(
      url: _downloadUrl,
      fileName: _modelName,
      accessToken: accessToken,
    );

    if (taskId != null) {
      _currentTaskId = taskId;
      // Save that we have a download in progress
      await DownloadStateManager.saveDownloadInProgress(taskId);
      _monitorDownload(taskId);
    } else {
      _handleError('Failed to start download');
    }
  }

  void _monitorDownload(String taskId) {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      final tasks = await DownloadManager.getAllTasks();
      final task = tasks.firstWhere(
        (task) => task.taskId == taskId,
        orElse: () => DownloadTask(
          taskId: '',
          status: DownloadTaskStatus.undefined,
          progress: 0,
          url: '',
          filename: '',
          savedDir: '',
          timeCreated: 0,
          allowCellular: true,
        ),
      );

      if (task.taskId.isEmpty) {
        timer.cancel();
        return;
      }

      setState(() {
        _progress = DownloadProgress(
          totalBytes: 100,
          downloadedBytes: task.progress,
          downloadRate: 0,
          remainingTime: Duration.zero,
          status: task.status,
        );
      });

      switch (task.status) {
        case DownloadTaskStatus.complete:
          timer.cancel();

          // Download completed
          setState(() {
            _downloadStatus = DownloadStatus.completed;
          });
          await DownloadStateManager.saveDownloadCompleted();
          Logger.info('Download completed successfully');

          // Navigate to ChatPage immediately
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => ChatPage()),
            );
          }
          break;
        case DownloadTaskStatus.failed:
          timer.cancel();
          setState(() {
            _downloadStatus = DownloadStatus.failed;
          });
          await DownloadStateManager.clearDownloadState();
          _handleError('Download failed');
          break;
        case DownloadTaskStatus.canceled:
          timer.cancel();
          setState(() {
            _downloadStatus = DownloadStatus.cancelled;
          });
          await DownloadStateManager.clearDownloadState();
          Logger.info('Download was cancelled');
          break;
        case DownloadTaskStatus.paused:
          setState(() {
            _downloadStatus = DownloadStatus.paused;
          });
          break;
        case DownloadTaskStatus.running:
          // Keep current downloading status
          break;
        case DownloadTaskStatus.enqueued:
          // Download is queued, keep showing downloading
          break;
        default:
          break;
      }
    });
  }

  void _handleError(String error) {
    setState(() {
      _downloadStatus = DownloadStatus.failed;
      _errorMessages.add(error);
    });
    Logger.error(error);
  }

  void _cancelDownload() async {
    await DownloadManager.cancelDownload();
    await DownloadStateManager.clearDownloadState();
    setState(() {
      _downloadStatus = DownloadStatus.cancelled;
    });
  }

  void _pauseDownload() async {
    await DownloadManager.pauseDownload();
    // Keep the download state as in_progress when paused
    setState(() {
      _downloadStatus = DownloadStatus.paused;
    });
  }

  void _resumeDownload() async {
    await DownloadManager.resumeDownload();
    setState(() {
      _downloadStatus = DownloadStatus.downloading;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showLogsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Logs'),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: Logger.getAllLogsAsString()),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    Logger.clear();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: Logger.logs.length,
            itemBuilder: (context, index) {
              final log = Logger.logs[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  log.toString(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _getLogColor(log.level),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      case 'DEBUG':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Error Messages'),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _errorMessages.join('\n')),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Errors copied to clipboard')),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _errorMessages.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _errorMessages[index],
                  style: const TextStyle(color: Colors.red),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Download'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: _showLogsDialog,
            tooltip: 'View Logs',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Model Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _modelFullName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'File: $_modelName',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This model will be downloaded to your device for offline use and can continue downloading in the background.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Download Status
            _buildDownloadSection(),

            const Spacer(),

            // Action Buttons
            _buildActionButtons(),
          ],
        ),
      ),
      bottomSheet: _showAgreementSheet ? _buildAgreementSheet() : null,
    );
  }

  Widget _buildDownloadSection() {
    switch (_downloadStatus) {
      case DownloadStatus.notStarted:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.download, color: Colors.blue[600]),
                const SizedBox(width: 12),
                const Text('Ready to download'),
              ],
            ),
          ),
        );

      case DownloadStatus.checkingAccess:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                const Text('Checking access...'),
              ],
            ),
          ),
        );

      case DownloadStatus.authenticating:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                const Text('Authenticating...'),
              ],
            ),
          ),
        );

      case DownloadStatus.awaitingLicenseAcceptance:
        return Card(
          color: Colors.orange[50],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.assignment, color: Colors.orange[600]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'License acceptance required. Please accept the model license to continue.',
                  ),
                ),
              ],
            ),
          ),
        );

      case DownloadStatus.downloading:
        return _buildDownloadProgress();

      case DownloadStatus.paused:
        return _buildDownloadProgress(isPaused: true);

      case DownloadStatus.completed:
        return Card(
          color: Colors.green[50],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600]),
                    const SizedBox(width: 12),
                    const Text('Download completed'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Redirecting to chat in a moment...',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.green[700]),
                ),
              ],
            ),
          ),
        );

      case DownloadStatus.failed:
        return Card(
          color: Colors.red[50],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[600]),
                    const SizedBox(width: 12),
                    const Text('Download failed'),
                    const Spacer(),
                    if (_errorMessages.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        onPressed: _showErrorDialog,
                        tooltip: 'View error details',
                      ),
                  ],
                ),
                if (_errorMessages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessages.last,
                    style: TextStyle(color: Colors.red[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );

      case DownloadStatus.cancelled:
        return Card(
          color: Colors.orange[50],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.cancel, color: Colors.orange[600]),
                const SizedBox(width: 12),
                const Text('Download cancelled'),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildDownloadProgress({bool isPaused = false}) {
    final progress = _progress;
    if (progress == null) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isPaused ? 'Download paused' : 'Downloading...'),
                Text('${progress.progressPercent}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.progress),
            const SizedBox(height: 12),
            if (isPaused)
              Text(
                'Download paused - tap Resume to continue',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.orange[700]),
              )
            else
              Text(
                'Downloading in background...',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.green[700]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    switch (_downloadStatus) {
      case DownloadStatus.notStarted:
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download & Try'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );

      case DownloadStatus.awaitingLicenseAcceptance:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Start Download'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );

      case DownloadStatus.downloading:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pauseDownload,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cancelDownload,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel'),
              ),
            ),
          ],
        );

      case DownloadStatus.paused:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resumeDownload,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cancelDownload,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel'),
              ),
            ),
          ],
        );

      case DownloadStatus.completed:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => ChatPage()),
              );
            },
            icon: const Icon(Icons.chat),
            label: const Text('Go to Chat'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildAgreementSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'License Agreement Required',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'This model requires you to accept a license agreement. Please click the button below to view and accept the license terms. After accepting, return to this app to start the download.',
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _showAgreementSheet = false;
                    _downloadStatus = DownloadStatus.notStarted;
                  });
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _showAgreementSheet = false;
                  });

                  if (await canLaunchUrl(Uri.parse(_modelCardUrl))) {
                    await launchUrl(
                      Uri.parse(_modelCardUrl),
                      mode: LaunchMode.externalApplication,
                    );
                    Logger.info('Opened license agreement in browser');

                    // After opening the license, set state to allow manual retry
                    setState(() {
                      _downloadStatus =
                          DownloadStatus.awaitingLicenseAcceptance;
                    });
                  }
                },
                child: const Text('View License'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
