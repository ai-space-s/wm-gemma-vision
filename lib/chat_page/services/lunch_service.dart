// lib/chat_page/services/lunch_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Meal menu service.
///
/// Fetches meal menu data from the Flask meal server.
class LunchService {
  static final LunchService _instance = LunchService._internal();
  static LunchService get instance => _instance;

  static const defaultBaseUrl = String.fromEnvironment(
    'LUNCH_SERVER_BASE_URL',
    defaultValue: 'https://demo.krestine.cc',
  );

  LunchService({
    http.Client? client,
    String baseUrl = defaultBaseUrl,
    Duration timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl,
       _timeout = timeout;

  LunchService._internal()
    : _client = http.Client(),
      _baseUrl = defaultBaseUrl,
      _timeout = const Duration(seconds: 8);

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  Future<String> getMealMenu(String dateStr, {String meal = 'all'}) async {
    final normalizedMeal = _normalizeMeal(meal);
    if (normalizedMeal == null) {
      return jsonEncode({
        'status': 'error',
        'code': 'invalid_meal',
        'source': 'lunch_server',
        'message': 'Meal must be all, breakfast, lunch, or dinner.',
      });
    }

    late final DateTime date;
    try {
      date = _parseDate(dateStr);
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'code': 'invalid_date',
        'source': 'lunch_server',
        'message': 'Meal date must be resolved before the server call: $e',
      });
    }

    final uri = _buildUri(_formatDate(date), normalizedMeal);

    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);

      final decoded = _decodeJsonObject(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonEncode(decoded);
      }

      return jsonEncode({
        'status': 'error',
        'code': 'server_error',
        'date': _formatDate(date),
        'httpStatus': response.statusCode,
        'message':
            decoded['message']?.toString() ??
            'Lunch server returned HTTP ${response.statusCode}.',
      });
    } on TimeoutException {
      return _fetchFailed(date, 'Lunch server request timed out.');
    } catch (e) {
      return _fetchFailed(date, 'Failed to fetch lunch menu: $e');
    }
  }

  static String? formatMealMenuResponse(
    String responseJson, {
    String requestedMeal = 'all',
    DateTime? now,
  }) {
    final decoded = jsonDecode(responseJson);
    if (decoded is! Map<String, dynamic>) return null;

    final status = decoded['status']?.toString() ?? '';
    if (status != 'ok') {
      final message = _cleanText(decoded['message']);
      if (message.isEmpty) return '식단 정보를 가져오지 못했습니다.';
      return '식단 정보를 가져오지 못했습니다: $message';
    }

    final dateLabel = _dateDisplayLabel(_cleanText(decoded['date']), now);
    final menu = decoded['menu'];
    if (menu is Map<String, dynamic>) {
      return _formatSingleMealMenu(
        menu,
        meal: _cleanText(decoded['meal']).isNotEmpty
            ? _cleanText(decoded['meal'])
            : requestedMeal,
        dateLabel: dateLabel,
      );
    }

    final meals = decoded['meals'];
    if (meals is Map<String, dynamic>) {
      final normalizedMeal = _normalizeMealForFormatting(requestedMeal);
      if (normalizedMeal != 'all') {
        final mealRecord = meals[normalizedMeal];
        if (mealRecord is Map<String, dynamic>) {
          final recordMenu = mealRecord['menu'];
          if (recordMenu is Map<String, dynamic>) {
            return _formatSingleMealMenu(
              recordMenu,
              meal: normalizedMeal,
              dateLabel: dateLabel,
            );
          }
        }
      }

      final sections = <String>[];
      for (final mealKey in ['breakfast', 'lunch', 'dinner']) {
        final mealRecord = meals[mealKey];
        if (mealRecord is! Map<String, dynamic>) continue;
        if (mealRecord['hasMeal'] == false) continue;

        final recordMenu = mealRecord['menu'];
        if (recordMenu is! Map<String, dynamic>) continue;

        final formatted = _formatMenuFields(recordMenu);
        if (formatted.isEmpty) continue;
        sections.add(
          '${_mealSubject(mealKey, dateLabel)} 메뉴는 다음과 같습니다.\n$formatted',
        );
      }

      if (sections.isNotEmpty) return sections.join('\n\n');
    }

    return null;
  }

  static String _formatSingleMealMenu(
    Map<String, dynamic> menu, {
    required String meal,
    required String dateLabel,
  }) {
    final fields = _formatMenuFields(menu);
    if (fields.isEmpty) {
      return '${_mealSubject(meal, dateLabel)} 메뉴 정보가 없습니다.';
    }
    return '${_mealSubject(meal, dateLabel)} 메뉴는 다음과 같습니다.\n$fields';
  }

  static String _formatMenuFields(Map<String, dynamic> menu) {
    final lines = <String>[];
    final main = _cleanText(menu['main']);
    final soup = _cleanText(menu['soup']);
    final sideDishes = _cleanTextList(menu['sideDishes']);
    final dessert = _cleanText(menu['dessert']);
    final drink = _cleanText(menu['drink']);

    if (main.isNotEmpty) lines.add('메인 : $main');
    if (soup.isNotEmpty) lines.add('국 : $soup');
    if (sideDishes.isNotEmpty) lines.add('반찬 : ${sideDishes.join(', ')}');
    if (dessert.isNotEmpty) lines.add('후식 : $dessert');
    if (drink.isNotEmpty) lines.add('음료 : $drink');

    return lines.join('\n');
  }

  static String _mealDisplayName(String meal) {
    switch (_normalizeMealForFormatting(meal)) {
      case 'breakfast':
        return '아침';
      case 'lunch':
        return '점심';
      case 'dinner':
        return '저녁';
      default:
        return '식단';
    }
  }

  static String _mealSubject(String meal, String dateLabel) {
    final mealName = _mealDisplayName(meal);
    if (dateLabel.isEmpty) return mealName;
    return '$dateLabel $mealName';
  }

  static String _dateDisplayLabel(String dateText, DateTime? now) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateText);
    if (match == null) return '';

    final target = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final todaySource = now ?? DateTime.now();
    final today = DateTime(
      todaySource.year,
      todaySource.month,
      todaySource.day,
    );
    final dayDelta = target.difference(today).inDays;
    if (dayDelta == 0) return '오늘';
    if (dayDelta == 1) return '내일';
    if (dayDelta == -1) return '어제';
    return '${target.month}월 ${target.day}일';
  }

  static String _normalizeMealForFormatting(String meal) {
    switch (meal.trim().toLowerCase()) {
      case 'breakfast':
      case '아침':
      case '조식':
        return 'breakfast';
      case 'lunch':
      case '점심':
      case '중식':
        return 'lunch';
      case 'dinner':
      case '저녁':
      case '석식':
        return 'dinner';
      default:
        return 'all';
    }
  }

  static List<String> _cleanTextList(Object? value) {
    if (value == null) return const [];
    if (value is String) {
      return value
          .replaceAll('\r', '\n')
          .split('\n')
          .map(_cleanText)
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is Iterable) {
      return value.map(_cleanText).where((item) => item.isNotEmpty).toList();
    }
    final text = _cleanText(value);
    return text.isEmpty ? const [] : [text];
  }

  static String _cleanText(Object? value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  DateTime _parseDate(String dateStr) {
    final normalized = dateStr.trim().toLowerCase();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(normalized);
    if (match == null) {
      throw FormatException('Invalid date format: $dateStr');
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw FormatException('Invalid calendar date: $dateStr');
    }
    return parsed;
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _normalizeMeal(String meal) {
    switch (meal.trim().toLowerCase()) {
      case 'all':
      case '전체':
        return 'all';
      case 'breakfast':
      case '아침':
      case '조식':
        return 'breakfast';
      case 'lunch':
      case '점심':
      case '중식':
        return 'lunch';
      case 'dinner':
      case '저녁':
      case '석식':
        return 'dinner';
    }
    return null;
  }

  Uri _buildUri(String date, String meal) {
    final base = Uri.parse(_baseUrl);
    final path = [
      if (base.path.isNotEmpty) base.path.replaceFirst(RegExp(r'/$'), ''),
      'api',
      'meals',
    ].join('/');
    return base.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: {'date': date, 'meal': meal},
    );
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Lunch server response must be a JSON object.');
  }

  String _fetchFailed(DateTime date, String message) {
    return jsonEncode({
      'status': 'error',
      'code': 'fetch_failed',
      'source': 'lunch_server',
      'date': _formatDate(date),
      'message': message,
    });
  }
}
