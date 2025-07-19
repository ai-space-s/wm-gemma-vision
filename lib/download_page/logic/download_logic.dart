// download_page/logic/download_logic.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:gemma_chat/chat_page/gemma_vision_chat.dart';
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
  final Function(DownloadStatus) setDownloadStatus;
  final Function(DownloadProgress?) setProgress;
  final Function(List<String>) setErrorMessages;
  final Function(bool) setShowAgreementSheet;

  DownloadPageLogic({
    required this.setDownloadStatus,
    required this.setProgress,
    required this.setErrorMessages,
    required this.setShowAgreementSheet,
  });

  /// Returns true when the model file is present and > 0 bytes.
  /// Also updates the UI state to `DownloadStatus.completed`.
  Future<bool> checkIfModelExists() async {
    // 1)  Find a completed task whose filename matches our model.
    final tasks = await DownloadManager.getAllTasks();
    DownloadTask? task;
    for (final t in tasks) {
      if (t.filename == modelName && t.status == DownloadTaskStatus.complete) {
        task = t;
        break;
      }
    }

    // 2)  Prefer the exact path reported by flutter_downloader,
    //     otherwise fall back to the app‑documents directory.
    final String filePath = task != null && task.filename != null
        ? '${task.savedDir}/${task.filename}'
        : '${(await getApplicationDocumentsDirectory()).path}/$modelName';

    // 3)  Validate the file.
    final file = File(filePath);
    if (await file.exists()) {
      final size = await file.length();
      if (size > 0) {
        Logger.info('Found model file ($size bytes) at $filePath');
        setDownloadStatus(DownloadStatus.completed);
        return true;
      }
    }

    Logger.debug('Model file not found at $filePath');
    return false;
  }

  Future<void> checkForOngoingDownloads(BuildContext context) async {
    try {
      final savedState = await DownloadStateManager.getDownloadState();
      final savedTaskId = await DownloadStateManager.getDownloadTaskId();

      Logger.info(
        'Checking download state - saved: $savedState, taskId: $savedTaskId',
      );

      if (savedState == 'in_progress' && savedTaskId != null) {
        Logger.info(
          'Found saved download in progress with task ID: $savedTaskId',
        );

        // 🔑  Re-attach the manager so pause/resume work again
        DownloadManager.attachToTask(savedTaskId);

        // Query the task list
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
          Logger.warning('Task ID not found in download manager');
          await DownloadStateManager.clearDownloadState();
          return;
        }

        Logger.info(
          'Found download task: ${task.taskId}, '
          'status: ${task.status}, progress: ${task.progress}%',
        );

        switch (task.status) {
          case DownloadTaskStatus.paused:
            setDownloadStatus(DownloadStatus.paused);
            monitorDownload(task.taskId, context);
            Logger.info('Found paused download, showing resume option');
            break;
          case DownloadTaskStatus.running:
          case DownloadTaskStatus.enqueued:
            setDownloadStatus(DownloadStatus.downloading);
            monitorDownload(task.taskId, context);
            break;
          case DownloadTaskStatus.complete:
            if (await checkIfModelExists()) {
              await DownloadStateManager.saveDownloadCompleted();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => ChatPage()),
                );
              });
            } else {
              await DownloadStateManager.clearDownloadState();
            }
            break;
          case DownloadTaskStatus.failed:
            setDownloadStatus(DownloadStatus.failed);
            await DownloadStateManager.clearDownloadState();
            handleError('Download failed while app was in background');
            break;
          case DownloadTaskStatus.canceled:
          default:
            await DownloadStateManager.clearDownloadState();
            break;
        }
      } else if (savedState == 'completed') {
        if (await checkIfModelExists()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => ChatPage()),
            );
          });
        } else {
          await DownloadStateManager.clearDownloadState();
        }
      } else {
        await checkIfModelExists(); // just in case the file is already there
      }
    } catch (e) {
      Logger.error('Error checking for ongoing downloads: $e');
      await DownloadStateManager.clearDownloadState();
    }
  }

  Future<void> startDownload() async {
    setDownloadStatus(DownloadStatus.checkingAccess);
    setErrorMessages([]);

    Logger.info('Starting download process for $modelFullName');

    // Check if model needs authentication
    final responseCode = await DownloadManager.checkModelAccess(downloadUrl);

    if (responseCode == 200) {
      // Public model - download directly
      await downloadModel(null);
      return;
    } else if (responseCode < 0) {
      handleError('Network error. Please check your connection.');
      return;
    }

    // Model needs authentication
    await handleAuthentication();
  }

  Future<void> handleAuthentication() async {
    setDownloadStatus(DownloadStatus.authenticating);

    Logger.info('Model requires authentication');

    final tokenStatus = await TokenManager.getTokenStatus();

    switch (tokenStatus) {
      case TokenStatus.notStored:
      case TokenStatus.expired:
        await startOAuthFlow();
        break;
      case TokenStatus.valid:
        final token = await TokenManager.getStoredToken();
        final responseCode = await DownloadManager.checkModelAccess(
          downloadUrl,
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
      Logger.info('Starting OAuth flow');
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
        Logger.info('OAuth flow cancelled by user');
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
          downloadUrl,
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
        handleError('Failed to exchange authorization code for token');
      }
    } catch (e) {
      handleError('Authentication error: $e');
    }
  }

  void showUserAgreement() {
    setDownloadStatus(DownloadStatus.awaitingLicenseAcceptance);
    setShowAgreementSheet(true);
    Logger.info('Model requires license acceptance');
  }

  Future<void> downloadModel(String? accessToken) async {
    setDownloadStatus(DownloadStatus.downloading);

    // Clean up any old failed downloads first
    await DownloadManager.cleanupFailedDownloads();

    final taskId = await DownloadManager.startDownload(
      url: downloadUrl,
      fileName: modelName,
      accessToken: accessToken,
    );

    if (taskId != null) {
      // Save that we have a download in progress
      await DownloadStateManager.saveDownloadInProgress(taskId);
      monitorDownload(taskId, null); // Pass null context for monitoring
    } else {
      handleError('Failed to start download');
    }
  }

  void monitorDownload(String taskId, BuildContext? context) {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
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

          // Download completed
          setDownloadStatus(DownloadStatus.completed);
          await DownloadStateManager.saveDownloadCompleted();
          Logger.info('Download completed successfully');

          // Navigate to ChatPage immediately
          if (context != null && context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => ChatPage()),
            );
          }
          break;
        case DownloadTaskStatus.failed:
          timer.cancel();
          setDownloadStatus(DownloadStatus.failed);
          await DownloadStateManager.clearDownloadState();
          handleError('Download failed');
          break;
        case DownloadTaskStatus.canceled:
          timer.cancel();
          // Reset to original download state instead of showing "cancelled"
          setDownloadStatus(DownloadStatus.notStarted);
          setProgress(null);
          await DownloadStateManager.clearDownloadState();
          Logger.info('Download was cancelled and reset to initial state');
          break;
        case DownloadTaskStatus.paused:
          setDownloadStatus(DownloadStatus.paused);
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
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.red[400]!, Colors.red[600]!],
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Cancel Download?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'Are you sure you want to cancel the download? All progress will be lost and any downloaded files will be completely deleted.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Keep Downloading',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red[400]!, Colors.red[600]!],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red[400]!.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel Download',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true) {
      await cancelDownload();
    }
  }

  Future<void> cancelDownload() async {
    await DownloadManager.cancelAndDeleteDownload();
    await DownloadStateManager.clearDownloadState();
    setDownloadStatus(DownloadStatus.notStarted);
    setProgress(null);
    Logger.info('Download cancelled and completely cleaned up');
  }

  Future<void> pauseDownload() async {
    await DownloadManager.pauseDownload();
    // Keep the download state as in_progress when paused
    setDownloadStatus(DownloadStatus.paused);
  }

  Future<void> resumeDownload() async {
    // Ask the manager to resume; get the new taskID.
    final newTaskId = await DownloadManager.resumeDownload();
    if (newTaskId == null) {
      handleError('Unable to resume download (not resumable?)');
      return;
    }

    // Persist the fresh ID so we survive process death
    await DownloadStateManager.saveDownloadInProgress(newTaskId);

    // Start listening to progress from the correct task
    monitorDownload(newTaskId, null);

    setDownloadStatus(DownloadStatus.downloading);
  }

  Future<void> openLicenseAgreement() async {
    setShowAgreementSheet(false);

    if (await canLaunchUrl(Uri.parse(modelCardUrl))) {
      await launchUrl(
        Uri.parse(modelCardUrl),
        mode: LaunchMode.externalApplication,
      );
      Logger.info('Opened license agreement in browser');

      // After opening the license, set state to allow manual retry
      setDownloadStatus(DownloadStatus.awaitingLicenseAcceptance);
    }
  }

  void cancelLicenseAgreement() {
    setShowAgreementSheet(false);
    setDownloadStatus(DownloadStatus.notStarted);
  }
}
