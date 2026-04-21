import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'logger.dart';

/// Persists download state for crash recovery (survives app restarts/kills)
class DownloadStateManager {
  /// Save download as in-progress with task ID for recovery
  static Future<void> saveDownloadInProgress(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(downloadStateKey, 'in_progress');
    await prefs.setString(downloadTaskIdKey, taskId);
    Logger.info('Saved download state: in_progress with task ID: $taskId');
  }

  /// Mark download as completed and clean up task ID
  static Future<void> saveDownloadCompleted({File? modelFile}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(downloadStateKey, 'completed');
    await prefs.remove(downloadTaskIdKey); // Don't need task ID anymore
    await prefs.setString(downloadedModelSignatureKey, modelCacheSignature);

    if (modelFile != null && await modelFile.exists()) {
      await prefs.setString(downloadedModelPathKey, modelFile.path);
      await prefs.setInt(downloadedModelBytesKey, await modelFile.length());
      await prefs.setInt(
        downloadedModelModifiedMsKey,
        (await modelFile.lastModified()).millisecondsSinceEpoch,
      );
    }

    Logger.info('Saved download state: completed');
  }

  /// Reset download state (fresh start or after cancellation)
  static Future<void> clearDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(downloadStateKey);
    await prefs.remove(downloadTaskIdKey);
    await prefs.remove(downloadedModelSignatureKey);
    await prefs.remove(downloadedModelPathKey);
    await prefs.remove(downloadedModelBytesKey);
    await prefs.remove(downloadedModelModifiedMsKey);
    Logger.info('Cleared download state');
  }

  static Future<String?> getDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(downloadStateKey);
  }

  static Future<String?> getDownloadTaskId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(downloadTaskIdKey);
  }

  static Future<bool> hasValidCompletedModelCache(File modelFile) async {
    try {
      if (!await modelFile.exists()) return false;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(downloadStateKey) != 'completed') return false;
      if (prefs.getString(downloadedModelSignatureKey) != modelCacheSignature) {
        return false;
      }
      if (prefs.getString(downloadedModelPathKey) != modelFile.path) {
        return false;
      }

      final cachedBytes = prefs.getInt(downloadedModelBytesKey);
      final cachedModifiedMs = prefs.getInt(downloadedModelModifiedMsKey);
      if (cachedBytes == null || cachedModifiedMs == null) return false;

      final actualBytes = await modelFile.length();
      final actualModifiedMs =
          (await modelFile.lastModified()).millisecondsSinceEpoch;
      return actualBytes == cachedBytes &&
          actualBytes == modelExpectedBytes &&
          actualModifiedMs == cachedModifiedMs;
    } catch (e) {
      Logger.error('Error reading completed model cache: $e');
      return false;
    }
  }
}
