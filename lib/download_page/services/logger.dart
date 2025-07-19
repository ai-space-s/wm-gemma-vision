// download_page/services/logger.dart

import 'dart:async';
import '../models/models.dart';

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
