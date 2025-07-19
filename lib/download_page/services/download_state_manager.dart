// download_page/services/download_state_manager.dart

import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'logger.dart';

class DownloadStateManager {
  static Future<void> saveDownloadInProgress(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(downloadStateKey, 'in_progress');
    await prefs.setString(downloadTaskIdKey, taskId);
    Logger.info('Saved download state: in_progress with task ID: $taskId');
  }

  static Future<void> saveDownloadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(downloadStateKey, 'completed');
    await prefs.remove(downloadTaskIdKey);
    Logger.info('Saved download state: completed');
  }

  static Future<void> clearDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(downloadStateKey);
    await prefs.remove(downloadTaskIdKey);
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
}
