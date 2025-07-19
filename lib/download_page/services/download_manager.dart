// download_page/services/download_manager.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'logger.dart';

class DownloadManager {
  static String? _currentTaskId;
  static final ReceivePort _port = ReceivePort();

  static void attachToTask(String taskId) {
    _currentTaskId = taskId;
  }

  static Future<void> initialize() async {
    // --- DO NOT call FlutterDownloader.initialize() here ---
    // It has already been called once in main().
    // All we do now is (re)wire the port so the UI isolate
    // can receive progress updates.

    // Remove any previous mapping to avoid "port already registered" errors.
    IsolateNameServer.removePortNameMapping('downloader_send_port');

    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );

    // Listen for messages coming from the background isolate.
    _port.listen((dynamic data) {
      final id = data[0] as String;
      final status = DownloadTaskStatus.fromInt(data[1] as int);
      final progress = data[2] as int;
      Logger.debug('Task $id: $status, $progress%');
    });
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

  static Future<String?> resumeDownload() async {
    if (_currentTaskId == null) {
      Logger.warning('No paused task to resume');
      return null;
    }

    try {
      // flutter_downloader creates a brand‑new taskID when resuming
      final newTaskId = await FlutterDownloader.resume(taskId: _currentTaskId!);

      if (newTaskId != null) {
        _currentTaskId = newTaskId; // 🔑 switch to the fresh job ID
        Logger.info('Download resumed with new ID: $newTaskId');
      } else {
        Logger.warning('Resume returned a null taskId');
      }
      return newTaskId;
    } catch (e) {
      Logger.error('Error while resuming download: $e');
      return null;
    }
  }

  static Future<void> cancelDownload() async {
    if (_currentTaskId != null) {
      await FlutterDownloader.cancel(taskId: _currentTaskId!);
      Logger.info('Download cancelled');
      _currentTaskId = null;
    }
  }

  /// Completely cancels the download and deletes all associated files
  static Future<void> cancelAndDeleteDownload() async {
    if (_currentTaskId == null) {
      Logger.info('No current task to cancel');
      return;
    }

    try {
      // Get task details before cancelling to find the file path
      final tasks = await getAllTasks();
      final currentTask = tasks.firstWhere(
        (task) => task.taskId == _currentTaskId,
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

      // Cancel the download task
      await FlutterDownloader.cancel(taskId: _currentTaskId!);
      Logger.info('Download task cancelled: $_currentTaskId');

      // Remove the task from flutter_downloader's database and delete the file
      await FlutterDownloader.remove(
        taskId: _currentTaskId!,
        shouldDeleteContent: true,
      );
      Logger.info('Download task removed from database with file deletion');

      // Additional cleanup: manually delete any remaining files
      if (currentTask.taskId.isNotEmpty &&
          currentTask.filename != null &&
          currentTask.savedDir.isNotEmpty) {
        await _deleteDownloadFiles(currentTask.savedDir, currentTask.filename!);
      }

      // Also clean up any other model files that might exist
      await _cleanupModelFiles();

      _currentTaskId = null;
      Logger.info('Download completely cancelled and all files deleted');
    } catch (e) {
      Logger.error('Error during complete download cancellation: $e');
      _currentTaskId = null;
    }
  }

  /// Delete specific download files
  static Future<void> _deleteDownloadFiles(
    String savedDir,
    String filename,
  ) async {
    try {
      if (savedDir.isEmpty || filename.isEmpty) return;

      final filePath = '$savedDir/$filename';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        Logger.info('Manually deleted file: $filePath');
      }

      // Also check for any partial files with common download extensions
      final partialExtensions = ['.part', '.tmp', '.download', '.crdownload'];
      for (final ext in partialExtensions) {
        final partialFile = File('$filePath$ext');
        if (await partialFile.exists()) {
          await partialFile.delete();
          Logger.info('Deleted partial file: $filePath$ext');
        }
      }
    } catch (e) {
      Logger.error('Error deleting download files: $e');
    }
  }

  /// Clean up any model files in the app directory
  static Future<void> _cleanupModelFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelExtensions = ['.gguf', '.bin', '.safetensors', '.pt', '.pth'];

      final List<FileSystemEntity> files = dir.listSync();
      for (final file in files) {
        if (file is File) {
          final filename = file.path.split('/').last.toLowerCase();

          // Check if it's a model file by extension or if it contains "gemma" or "model"
          final isModelFile =
              modelExtensions.any((ext) => filename.endsWith(ext)) ||
              filename.contains('gemma') ||
              filename.contains('model');

          if (isModelFile) {
            await file.delete();
            Logger.info('Cleaned up model file: ${file.path}');
          }
        }
      }
    } catch (e) {
      Logger.error('Error cleaning up model files: $e');
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

        // Additional manual cleanup - only if filename is not null
        if (task.filename != null && task.savedDir.isNotEmpty) {
          await _deleteDownloadFiles(task.savedDir, task.filename!);
        }
      }
    } catch (e) {
      Logger.error('Error cleaning up failed downloads: $e');
    }
  }

  static Future<List<DownloadTask>> getAllTasks() async {
    return await FlutterDownloader.loadTasks() ?? [];
  }
}
