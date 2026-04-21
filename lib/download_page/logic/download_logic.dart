// lib/download_page/logic/download_logic.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/enums.dart';
import '../models/models.dart';
import '../services/logger.dart';
import '../services/download_state_manager.dart';
import '../services/download_manager.dart';
import '../services/token_manager.dart';
import '../services/huggingface_oauth.dart';

class DownloadPageLogic {
  final DownloadTarget target;
  final Function(DownloadStatus) setDownloadStatus;
  final Function(DownloadProgress?) setProgress;
  final Function(List<String>) setErrorMessages;
  final Function(bool) setShowAgreementSheet;

  static const platform = MethodChannel('com.tommasogiovannini.gemma/assets');

  Timer? _monitoringTimer;
  bool _cancelRequested = false;

  DownloadPageLogic({
    required this.target,
    required this.setDownloadStatus,
    required this.setProgress,
    required this.setErrorMessages,
    required this.setShowAgreementSheet,
  });

  String get currentModelName => modelName;

  String get currentModelFullName => modelFullName;

  String get currentDownloadUrl => downloadUrl;

  String get currentModelCardUrl => modelCardUrl;

  bool get canCopyFromAssets => false;

  void dispose() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  Future<bool> checkIfModelExists() async {
    final name = currentModelName;

    // [수정] 웹 환경 처리
    if (kIsWeb) {
      Logger.info(
        'Web platform detected. Assuming model exists in assets/models/',
      );
      // 웹에서는 파일 시스템 확인을 건너뛰고 바로 완료 상태로 만듭니다.
      setDownloadStatus(DownloadStatus.completed);
      return true;
    }

    if (modelRuntime == 'litert_lm') {
      final modelFile = File(
        '${(await getApplicationDocumentsDirectory()).path}/$name',
      );

      if (await DownloadStateManager.hasValidCompletedModelCache(modelFile)) {
        Logger.info('Using cached LiteRT-LM model at ${modelFile.path}');
        setDownloadStatus(DownloadStatus.completed);
        return true;
      }

      if (await _singleModelFileIsValid(modelFile)) {
        Logger.info('Found complete LiteRT-LM model at ${modelFile.path}');
        await DownloadStateManager.saveDownloadCompleted(modelFile: modelFile);
        setDownloadStatus(DownloadStatus.completed);
        return true;
      }

      Logger.debug(
        'LiteRT-LM model file not found or invalid: ${modelFile.path}.',
      );
      return _attemptCopyFromAssets();
    }

    final modelDir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$name',
    );
    final manifest = File('${modelDir.path}/release-manifest.json');
    final config = File('${modelDir.path}/mlc-chat-config.json');
    final tokenizer = File('${modelDir.path}/tokenizer.json');

    if (await manifest.exists() &&
        await config.exists() &&
        await tokenizer.exists()) {
      if (await _manifestFilesExist(modelDir, manifest)) {
        Logger.info('Found complete MLC model directory at ${modelDir.path}');
        setDownloadStatus(DownloadStatus.completed);
        return true;
      }
    }

    Logger.debug(
      'Model directory not found or incomplete at ${modelDir.path}.',
    );

    final copied = await _attemptCopyFromAssets();
    if (copied) {
      return true;
    }

    return false;
  }

  Future<bool> _attemptCopyFromAssets() async {
    if (!canCopyFromAssets) return false;

    // [수정] 웹에서는 Native Channel 호출 불가 (assets 직접 참조하므로 복사 불필요)
    if (kIsWeb) {
      return true;
    }

    setDownloadStatus(DownloadStatus.copying);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = '${dir.path}/$currentModelName';
      final assetName = 'assets/models/$currentModelName';

      Logger.info('Starting native copy from $assetName to $targetPath');

      setProgress(null);

      final bool result = await platform.invokeMethod('copyAsset', {
        'assetName': assetName,
        'targetPath': targetPath,
      });

      if (result) {
        Logger.info('Model copied from assets successfully (Native).');
        setDownloadStatus(DownloadStatus.completed);
        return true;
      } else {
        throw Exception("Native copy returned false");
      }
    } catch (e) {
      Logger.error('Asset copy failed: $e');
      setDownloadStatus(DownloadStatus.notStarted);
      setProgress(null);
      setErrorMessages(['Failed to copy model from assets (Native Error).']);
      return false;
    }
  }

  Future<void> forceCopyFromAssets() async {
    await _attemptCopyFromAssets();
  }

  Future<void> retryVerification() async {
    setDownloadStatus(DownloadStatus.checkingAccess);
    final exists = await checkIfModelExists();
    if (!exists) {
      handleError('Verification failed: Model file not found.');
    }
  }

  Future<void> checkForOngoingDownloads() async {
    // [수정] 웹에서는 진행 중인 다운로드 체크 로직 건너뜀 (다운로드가 없으므로)
    if (kIsWeb) {
      await checkIfModelExists();
      return;
    }

    try {
      setDownloadStatus(DownloadStatus.checkingAccess);

      if (target == DownloadTarget.mainModel) {
        final exists = await checkIfModelExists();
        if (!exists) {
          setDownloadStatus(DownloadStatus.notStarted);
        }
        return;
      }

      final savedState = await DownloadStateManager.getDownloadState();
      final savedTaskId = await DownloadStateManager.getDownloadTaskId();

      if (savedState == 'in_progress' && savedTaskId != null) {
        DownloadManager.attachToTask(savedTaskId);
        final tasks = await DownloadManager.getAllTasks();
        final task = tasks.firstWhere(
          (t) => t.taskId == savedTaskId,
          orElse: () => DownloadTask(
            taskId: '',
            status: DownloadTaskStatus.undefined,
            progress: 0,
            url: '',
            filename: null,
            savedDir: '',
            timeCreated: 0,
            allowCellular: true,
          ),
        );

        if (task.taskId.isEmpty) {
          await DownloadStateManager.clearDownloadState();
          return;
        }

        if (task.filename != currentModelName) return;

        switch (task.status) {
          case DownloadTaskStatus.paused:
            setDownloadStatus(DownloadStatus.paused);
            monitorDownload(task.taskId);
            break;
          case DownloadTaskStatus.running:
          case DownloadTaskStatus.enqueued:
            setDownloadStatus(DownloadStatus.downloading);
            monitorDownload(task.taskId);
            break;
          case DownloadTaskStatus.complete:
            if (await checkIfModelExists()) {
              await _markCurrentModelDownloadCompleted();
              setDownloadStatus(DownloadStatus.completed);
            } else {
              await DownloadStateManager.clearDownloadState();
            }
            break;
          case DownloadTaskStatus.failed:
            setDownloadStatus(DownloadStatus.failed);
            await DownloadStateManager.clearDownloadState();
            break;
          default:
            await DownloadStateManager.clearDownloadState();
            break;
        }
      } else if (savedState == 'completed') {
        if (!await checkIfModelExists()) {
          await DownloadStateManager.clearDownloadState();
          setDownloadStatus(DownloadStatus.notStarted);
        }
      } else {
        final exists = await checkIfModelExists();
        if (!exists) {
          setDownloadStatus(DownloadStatus.notStarted);
        }
      }
    } catch (e) {
      Logger.error('Error checking for ongoing downloads: $e');
      await DownloadStateManager.clearDownloadState();
      setDownloadStatus(DownloadStatus.notStarted);
    }
  }

  // ... (나머지 다운로드 관련 메서드들은 웹에서 호출되지 않거나 DownloadManager에서 차단되므로 그대로 둡니다.)

  Future<void> startDownload() async {
    // [수정] 웹에서 실수로 호출되었을 경우 방어
    if (kIsWeb) {
      Logger.warning(
        'Download attempted on Web. Treating as completed if asset exists.',
      );
      await checkIfModelExists();
      return;
    }

    setDownloadStatus(DownloadStatus.checkingAccess);
    setErrorMessages([]);

    Logger.info('Starting download process for $currentModelFullName');

    final url = currentDownloadUrl;
    final responseCode = await DownloadManager.checkModelAccess(url);

    if (responseCode == 200 || responseCode == 302) {
      await downloadModel(null);
      return;
    } else if (responseCode < 0) {
      handleError('Network error. Please check your connection.');
      return;
    }

    await handleAuthentication();
  }

  // (이하 메서드 생략 - 변경사항 없음)
  Future<void> handleAuthentication() async {
    // ... (기존 코드)
    // web_auth_2는 웹 지원하지만, 여기서는 로컬 사용이 목적이므로 넘어갑니다.
    // 필요시 기존 코드 유지
    setDownloadStatus(DownloadStatus.authenticating);
    final tokenStatus = await TokenManager.getTokenStatus();

    switch (tokenStatus) {
      case TokenStatus.notStored:
      case TokenStatus.expired:
        await startOAuthFlow();
        break;
      case TokenStatus.valid:
        final token = await TokenManager.getStoredToken();
        final responseCode = await DownloadManager.checkModelAccess(
          currentDownloadUrl,
          token?.accessToken,
        );

        if (responseCode == 200 || responseCode == 302) {
          await downloadModel(token?.accessToken);
        } else if (responseCode == 403) {
          showUserAgreement();
        } else {
          await startOAuthFlow();
        }
        break;
    }
  }

  Future<void> startOAuthFlow() async {
    try {
      final authUrl = await HuggingFaceOAuth.generateAuthUrl();
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'com.tommasogiovannini.gemma',
      );
      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];

      if (code != null) {
        await handleAuthorizationCode(code);
      } else {
        handleError('Authorization failed: No code received');
      }
    } catch (e) {
      if (e.toString().contains('CANCELED') ||
          e.toString().contains('USER_CANCELED')) {
        setDownloadStatus(DownloadStatus.notStarted);
      } else {
        handleError('Authentication failed: $e');
      }
    }
  }

  Future<void> handleAuthorizationCode(String code) async {
    setDownloadStatus(DownloadStatus.authenticating);
    try {
      final tokenData = await HuggingFaceOAuth.exchangeCodeForToken(code);
      if (tokenData != null) {
        final responseCode = await DownloadManager.checkModelAccess(
          currentDownloadUrl,
          tokenData.accessToken,
        );

        if (responseCode == 200 || responseCode == 302) {
          await downloadModel(tokenData.accessToken);
        } else if (responseCode == 403) {
          showUserAgreement();
        } else {
          handleError('Failed to access model with token');
        }
      } else {
        handleError('Token exchange failed');
      }
    } catch (e) {
      handleError('Authentication error: $e');
    }
  }

  void showUserAgreement() {
    setDownloadStatus(DownloadStatus.awaitingLicenseAcceptance);
    setShowAgreementSheet(true);
  }

  Future<void> downloadModel(String? accessToken) async {
    setDownloadStatus(DownloadStatus.downloading);
    _cancelRequested = false;

    try {
      if (modelRuntime == 'litert_lm') {
        await _downloadSingleModelFile(accessToken);
      } else {
        await _downloadMlcRepository(accessToken);
      }
      if (_cancelRequested) {
        setDownloadStatus(DownloadStatus.notStarted);
        return;
      }
      await _markCurrentModelDownloadCompleted();
      setDownloadStatus(DownloadStatus.completed);
    } catch (e) {
      if (_cancelRequested) {
        setDownloadStatus(DownloadStatus.notStarted);
      } else {
        handleError('Failed to download Gemma 4 model: $e');
      }
    }
  }

  Future<void> _downloadMlcRepository(String? accessToken) async {
    final client = http.Client();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/$modelName');
      await modelDir.create(recursive: true);

      final manifestUri = Uri.parse(downloadUrl);
      final manifestResponse = await client.get(
        manifestUri,
        headers: _authHeaders(accessToken),
      );
      if (manifestResponse.statusCode != 200) {
        throw Exception(
          'manifest HTTP ${manifestResponse.statusCode}: ${manifestResponse.reasonPhrase}',
        );
      }

      final manifestFile = File('${modelDir.path}/release-manifest.json');
      await manifestFile.writeAsBytes(manifestResponse.bodyBytes);

      final manifestJson =
          jsonDecode(utf8.decode(manifestResponse.bodyBytes))
              as Map<String, dynamic>;
      final files = (manifestJson['files'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final totalBytes = files.fold<int>(
        0,
        (total, file) => total + ((file['size_bytes'] as num?)?.toInt() ?? 0),
      );

      var downloadedBytes = 0;
      for (final fileInfo in files) {
        if (_cancelRequested) break;

        final relativePath = fileInfo['path'].toString();
        if (!_isSafeManifestPath(relativePath)) {
          throw Exception('unsafe manifest path: $relativePath');
        }
        final expectedSize = (fileInfo['size_bytes'] as num?)?.toInt() ?? 0;
        final targetFile = File('${modelDir.path}/$relativePath');
        await targetFile.parent.create(recursive: true);

        if (await targetFile.exists() &&
            expectedSize > 0 &&
            await targetFile.length() == expectedSize &&
            await _matchesManifestHash(targetFile, fileInfo)) {
          downloadedBytes += expectedSize;
          _reportRepositoryProgress(downloadedBytes, totalBytes);
          continue;
        }

        final request = http.Request(
          'GET',
          Uri.parse(_fileDownloadUrl(relativePath)),
        );
        request.headers.addAll(_authHeaders(accessToken));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw Exception('$relativePath HTTP ${response.statusCode}');
        }

        final sink = targetFile.openWrite();
        try {
          await for (final chunk in response.stream) {
            if (_cancelRequested) break;
            sink.add(chunk);
            downloadedBytes += chunk.length;
            _reportRepositoryProgress(downloadedBytes, totalBytes);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (_cancelRequested) {
          await targetFile.delete().catchError((_) => targetFile);
          break;
        }
      }

      if (!_cancelRequested &&
          !await _manifestFilesExist(modelDir, manifestFile)) {
        throw Exception('download verification failed');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _downloadSingleModelFile(String? accessToken) async {
    final client = http.Client();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetFile = File('${dir.path}/$modelName');
      await targetFile.parent.create(recursive: true);

      if (await _singleModelFileIsValid(targetFile)) {
        setProgress(
          DownloadProgress(
            totalBytes: 100,
            downloadedBytes: 100,
            downloadRate: 0,
            remainingTime: Duration.zero,
            status: DownloadTaskStatus.complete,
          ),
        );
        return;
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers.addAll(_authHeaders(accessToken));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('model HTTP ${response.statusCode}');
      }

      var downloadedBytes = 0;
      final sink = targetFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequested) break;
          sink.add(chunk);
          downloadedBytes += chunk.length;
          _reportRepositoryProgress(downloadedBytes, modelExpectedBytes);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (_cancelRequested) {
        await targetFile.delete().catchError((_) => targetFile);
        return;
      }

      if (!await _singleModelFileIsValid(targetFile)) {
        throw Exception('download verification failed');
      }
    } finally {
      client.close();
    }
  }

  Map<String, String> _authHeaders(String? accessToken) {
    if (accessToken == null || accessToken.isEmpty) return const {};
    return {'Authorization': 'Bearer $accessToken'};
  }

  String _fileDownloadUrl(String relativePath) {
    final encodedPath = relativePath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return '$modelCardUrl/resolve/main/$encodedPath?download=true';
  }

  void _reportRepositoryProgress(int downloadedBytes, int totalBytes) {
    final percent = totalBytes <= 0
        ? 0
        : ((downloadedBytes / totalBytes) * 100).clamp(0, 100).round();
    setProgress(
      DownloadProgress(
        totalBytes: 100,
        downloadedBytes: percent,
        downloadRate: 0,
        remainingTime: Duration.zero,
        status: DownloadTaskStatus.running,
      ),
    );
  }

  Future<bool> _manifestFilesExist(
    Directory modelDir,
    File manifestFile,
  ) async {
    try {
      final manifestJson =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final files = (manifestJson['files'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final fileInfo in files) {
        final relativePath = fileInfo['path'].toString();
        if (!_isSafeManifestPath(relativePath)) return false;
        final expectedSize = (fileInfo['size_bytes'] as num?)?.toInt() ?? 0;
        final file = File('${modelDir.path}/$relativePath');
        if (!await file.exists()) return false;
        if (expectedSize > 0 && await file.length() != expectedSize) {
          return false;
        }
        if (!await _matchesManifestHash(file, fileInfo)) {
          return false;
        }
      }
      return true;
    } catch (e) {
      Logger.error('Error verifying model manifest: $e');
      return false;
    }
  }

  bool _isSafeManifestPath(String relativePath) {
    if (relativePath.isEmpty) return false;
    if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
      return false;
    }
    final normalized = relativePath.replaceAll('\\', '/');
    return !normalized.split('/').contains('..');
  }

  Future<bool> _matchesManifestHash(
    File file,
    Map<String, dynamic> fileInfo,
  ) async {
    final expectedHash = fileInfo['sha256']?.toString();
    if (expectedHash == null || expectedHash.isEmpty) return true;
    final actualHash = await file.openRead().transform(sha256).single;
    return actualHash.toString().toLowerCase() == expectedHash.toLowerCase();
  }

  Future<bool> _singleModelFileIsValid(File file) async {
    if (!await file.exists()) return false;
    if (modelExpectedBytes > 0 && await file.length() != modelExpectedBytes) {
      return false;
    }
    if (modelExpectedSha256.isEmpty) return true;
    final actualHash = await file.openRead().transform(sha256).single;
    return actualHash.toString().toLowerCase() ==
        modelExpectedSha256.toLowerCase();
  }

  void monitorDownload(String taskId) {
    _monitoringTimer?.cancel();

    _monitoringTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      try {
        final tasks = await DownloadManager.getAllTasks();
        final task = tasks.firstWhere(
          (task) => task.taskId == taskId,
          orElse: () => DownloadTask(
            taskId: '',
            status: DownloadTaskStatus.undefined,
            progress: 0,
            url: '',
            filename: null,
            savedDir: '',
            timeCreated: 0,
            allowCellular: true,
          ),
        );

        if (task.taskId.isEmpty) {
          timer.cancel();
          _monitoringTimer = null;
          return;
        }

        setProgress(
          DownloadProgress(
            totalBytes: 100,
            downloadedBytes: task.progress,
            downloadRate: 0,
            remainingTime: Duration.zero,
            status: task.status,
          ),
        );

        switch (task.status) {
          case DownloadTaskStatus.complete:
            timer.cancel();
            _monitoringTimer = null;
            setDownloadStatus(DownloadStatus.completed);
            await _markCurrentModelDownloadCompleted();
            break;
          case DownloadTaskStatus.failed:
            timer.cancel();
            _monitoringTimer = null;
            setDownloadStatus(DownloadStatus.failed);
            await DownloadStateManager.clearDownloadState();
            handleError('Download failed');
            break;
          case DownloadTaskStatus.canceled:
            timer.cancel();
            _monitoringTimer = null;
            setDownloadStatus(DownloadStatus.notStarted);
            await DownloadStateManager.clearDownloadState();
            break;
          case DownloadTaskStatus.paused:
            setDownloadStatus(DownloadStatus.paused);
            break;
          case DownloadTaskStatus.running:
            setDownloadStatus(DownloadStatus.downloading);
            break;
          default:
            break;
        }
      } catch (e) {
        timer.cancel();
        handleError('Error monitoring download: $e');
      }
    });
  }

  void handleError(String error) {
    setDownloadStatus(DownloadStatus.failed);
    setErrorMessages([error]);
    Logger.error(error);
  }

  Future<void> showCancelConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Download?'),
          content: const Text('Progress will be lost.'),
          actions: [
            TextButton(
              child: const Text('Keep Downloading'),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await cancelDownload();
    }
  }

  Future<void> cancelDownload() async {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _cancelRequested = true;
    await DownloadManager.cancelAndDeleteDownload();
    await DownloadStateManager.clearDownloadState();
    setDownloadStatus(DownloadStatus.notStarted);
    setProgress(null);
  }

  Future<void> pauseDownload() async {
    handleError(
      'Pause is not supported for this model download. Cancel and retry instead.',
    );
  }

  Future<void> resumeDownload() async {
    await startDownload();
  }

  Future<void> _markCurrentModelDownloadCompleted() async {
    if (modelRuntime == 'litert_lm') {
      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File('${dir.path}/$modelName');
      await DownloadStateManager.saveDownloadCompleted(modelFile: modelFile);
      return;
    }

    await DownloadStateManager.saveDownloadCompleted();
  }

  Future<void> openLicenseAgreement() async {
    setShowAgreementSheet(false);
    if (await canLaunchUrl(Uri.parse(currentModelCardUrl))) {
      await launchUrl(
        Uri.parse(currentModelCardUrl),
        mode: LaunchMode.externalApplication,
      );
      setDownloadStatus(DownloadStatus.awaitingLicenseAcceptance);
    }
  }

  void cancelLicenseAgreement() {
    setShowAgreementSheet(false);
    setDownloadStatus(DownloadStatus.notStarted);
  }
}
