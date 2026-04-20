// lib/download_page/logic/download_logic.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
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

  DownloadPageLogic({
    required this.target,
    required this.setDownloadStatus,
    required this.setProgress,
    required this.setErrorMessages,
    required this.setShowAgreementSheet,
  });

  String get currentModelName =>
      target == DownloadTarget.mainModel ? modelName : functionModelName;

  String get currentModelFullName =>
      target == DownloadTarget.mainModel ? modelFullName : functionModelFullName;

  String get currentDownloadUrl =>
      target == DownloadTarget.mainModel ? downloadUrl : functionModelDownloadUrl;

  String get currentModelCardUrl =>
      target == DownloadTarget.mainModel ? modelCardUrl : functionModelCardUrl;

  bool get canCopyFromAssets => target == DownloadTarget.mainModel;

  void dispose() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  Future<bool> checkIfModelExists() async {
    final name = currentModelName;

    // [수정] 웹 환경 처리
    if (kIsWeb) {
      Logger.info('Web platform detected. Assuming model exists in assets/models/');
      // 웹에서는 파일 시스템 확인을 건너뛰고 바로 완료 상태로 만듭니다.
      setDownloadStatus(DownloadStatus.completed);
      return true;
    }

    final tasks = await DownloadManager.getAllTasks();
    DownloadTask? task;
    for (final t in tasks) {
      if (t.filename == name && t.status == DownloadTaskStatus.complete) {
        task = t;
        break;
      }
    }

    final String filePath = task != null && task.filename != null
        ? '${task.savedDir}/${task.filename}'
        : '${(await getApplicationDocumentsDirectory()).path}/$name';

    final file = File(filePath);
    if (await file.exists()) {
      final size = await file.length();
      if (size > 0) {
        Logger.info('Found model file ($size bytes) at $filePath');
        setDownloadStatus(DownloadStatus.completed);
        return true;
      }
    }

    Logger.debug('Model file not found at $filePath. Checking assets...');

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

  Future<void> checkForOngoingDownloads(BuildContext context) async {
    // [수정] 웹에서는 진행 중인 다운로드 체크 로직 건너뜀 (다운로드가 없으므로)
    if (kIsWeb) {
      await checkIfModelExists();
      return;
    }

    try {
      final savedState = await DownloadStateManager.getDownloadState();
      final savedTaskId = await DownloadStateManager.getDownloadTaskId();

      if (savedState == 'in_progress' && savedTaskId != null) {
        DownloadManager.attachToTask(savedTaskId);
        final tasks = await DownloadManager.getAllTasks();
        final task = tasks.firstWhere(
              (t) => t.taskId == savedTaskId,
          orElse: () => DownloadTask(taskId: '', status: DownloadTaskStatus.undefined, progress: 0, url: '', filename: null, savedDir: '', timeCreated: 0, allowCellular: true),
        );

        if (task.taskId.isEmpty) {
          await DownloadStateManager.clearDownloadState();
          return;
        }

        if (task.filename != currentModelName) return;

        switch (task.status) {
          case DownloadTaskStatus.paused:
            setDownloadStatus(DownloadStatus.paused);
            monitorDownload(task.taskId, context);
            break;
          case DownloadTaskStatus.running:
          case DownloadTaskStatus.enqueued:
            setDownloadStatus(DownloadStatus.downloading);
            monitorDownload(task.taskId, context);
            break;
          case DownloadTaskStatus.complete:
            if (await checkIfModelExists()) {
              await DownloadStateManager.saveDownloadCompleted();
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
        }
      } else {
        await checkIfModelExists();
      }
    } catch (e) {
      Logger.error('Error checking for ongoing downloads: $e');
      await DownloadStateManager.clearDownloadState();
    }
  }

  // ... (나머지 다운로드 관련 메서드들은 웹에서 호출되지 않거나 DownloadManager에서 차단되므로 그대로 둡니다.)

  Future<void> startDownload() async {
    // [수정] 웹에서 실수로 호출되었을 경우 방어
    if (kIsWeb) {
      Logger.warning('Download attempted on Web. Treating as completed if asset exists.');
      await checkIfModelExists();
      return;
    }

    setDownloadStatus(DownloadStatus.checkingAccess);
    setErrorMessages([]);

    Logger.info('Starting download process for $currentModelFullName');

    final url = currentDownloadUrl;
    final responseCode = await DownloadManager.checkModelAccess(url);

    if (responseCode == 200) {
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

        if (responseCode == 200) {
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
      if (e.toString().contains('CANCELED') || e.toString().contains('USER_CANCELED')) {
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

        if (responseCode == 200) {
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
    await DownloadManager.cleanupFailedDownloads();

    final taskId = await DownloadManager.startDownload(
      url: currentDownloadUrl,
      fileName: currentModelName,
      accessToken: accessToken,
    );

    if (taskId != null) {
      await DownloadStateManager.saveDownloadInProgress(taskId);
      monitorDownload(taskId, null);
    } else {
      handleError('Failed to start download');
    }
  }

  void monitorDownload(String taskId, BuildContext? context) {
    _monitoringTimer?.cancel();

    _monitoringTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final tasks = await DownloadManager.getAllTasks();
        final task = tasks.firstWhere(
              (task) => task.taskId == taskId,
          orElse: () => DownloadTask(taskId: '', status: DownloadTaskStatus.undefined, progress: 0, url: '', filename: null, savedDir: '', timeCreated: 0, allowCellular: true),
        );

        if (task.taskId.isEmpty) {
          timer.cancel();
          _monitoringTimer = null;
          return;
        }

        setProgress(DownloadProgress(
          totalBytes: 100,
          downloadedBytes: task.progress,
          downloadRate: 0,
          remainingTime: Duration.zero,
          status: task.status,
        ));

        switch (task.status) {
          case DownloadTaskStatus.complete:
            timer.cancel();
            _monitoringTimer = null;
            setDownloadStatus(DownloadStatus.completed);
            await DownloadStateManager.saveDownloadCompleted();
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
            TextButton(child: const Text('Keep Downloading'), onPressed: () => Navigator.pop(context, false)),
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context, true)),
          ],
        );
      },
    );

    if (result == true) {
      await cancelDownload();
      if (target == DownloadTarget.functionModel) {
        Navigator.of(context).pop(false);
      }
    }
  }

  Future<void> cancelDownload() async {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    await DownloadManager.cancelAndDeleteDownload();
    await DownloadStateManager.clearDownloadState();
    setDownloadStatus(DownloadStatus.notStarted);
    setProgress(null);
  }

  Future<void> pauseDownload() async {
    await DownloadManager.pauseDownload();
    setDownloadStatus(DownloadStatus.paused);
  }

  Future<void> resumeDownload() async {
    final newTaskId = await DownloadManager.resumeDownload();
    if (newTaskId == null) {
      handleError('Unable to resume download');
      return;
    }
    await DownloadStateManager.saveDownloadInProgress(newTaskId);
    monitorDownload(newTaskId, null);
    setDownloadStatus(DownloadStatus.downloading);
  }

  Future<void> openLicenseAgreement() async {
    setShowAgreementSheet(false);
    if (await canLaunchUrl(Uri.parse(currentModelCardUrl))) {
      await launchUrl(Uri.parse(currentModelCardUrl), mode: LaunchMode.externalApplication);
      setDownloadStatus(DownloadStatus.awaitingLicenseAcceptance);
    }
  }

  void cancelLicenseAgreement() {
    setShowAgreementSheet(false);
    setDownloadStatus(DownloadStatus.notStarted);
  }
}