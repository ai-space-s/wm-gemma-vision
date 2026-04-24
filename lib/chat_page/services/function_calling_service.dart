// lib/chat_page/services/function_calling_service.dart
import 'dart:convert';

import '../../app_settings.dart';
import 'geocoding_service.dart';
import 'location_service.dart';
import 'lunch_service.dart';
import 'weather_service.dart';

/// Registry-backed tool calling service.
///
/// To add a new function call, implement [ChatFunctionTool] and register it in
/// [_buildDefaultTools]. Keep intent detection conservative enough that normal
/// chat falls through to the regular Gemma conversation.
class FunctionCallingService {
  static final FunctionCallingService instance =
      FunctionCallingService._internal();

  FunctionCallingService._internal({
    DateTime Function()? clock,
    List<ChatFunctionTool>? tools,
  }) : _clock = clock ?? DateTime.now,
       _tools = tools ?? _buildDefaultTools(clock ?? DateTime.now);

  FunctionCallingService.forTesting({required DateTime now})
    : _clock = (() => now),
      _tools = _buildDefaultTools(() => now);

  final DateTime Function() _clock;
  final List<ChatFunctionTool> _tools;

  Future<FunctionCall?> predict(String userQuery) async {
    if (!AppSettings.instance.enableFunctionCalling) return null;

    final normalized = userQuery.toLowerCase().trim();
    if (normalized.isEmpty) return null;

    for (final tool in _tools) {
      final call = await tool.tryBuildCall(
        originalQuery: userQuery,
        normalizedQuery: normalized,
        now: _clock(),
      );
      if (call != null) return call;
    }
    return null;
  }

  Future<String> execute(FunctionCall call) async {
    for (final tool in _tools) {
      if (tool.name == call.name) {
        try {
          return await tool.execute(call.args);
        } catch (e) {
          return jsonEncode({
            'status': 'error',
            'message': 'Execution failed: $e',
          });
        }
      }
    }

    return jsonEncode({
      'status': 'error',
      'message': 'Unknown function: ${call.name}',
    });
  }

  static List<ChatFunctionTool> _buildDefaultTools(DateTime Function() clock) {
    return [LunchMenuFunctionTool(clock: clock), WeatherFunctionTool()];
  }
}

abstract class ChatFunctionTool {
  String get name;

  Future<FunctionCall?> tryBuildCall({
    required String originalQuery,
    required String normalizedQuery,
    required DateTime now,
  });

  Future<String> execute(Map<String, dynamic> args);
}

class LunchMenuFunctionTool implements ChatFunctionTool {
  LunchMenuFunctionTool({required DateTime Function() clock}) : _clock = clock;

  final DateTime Function() _clock;

  @override
  String get name => 'get_meal_menu';

  @override
  Future<FunctionCall?> tryBuildCall({
    required String originalQuery,
    required String normalizedQuery,
    required DateTime now,
  }) async {
    if (!_looksLikeMealMenuRequest(normalizedQuery)) return null;

    return FunctionCall(
      name: name,
      args: {
        'date': _extractDate(normalizedQuery),
        'meal': _extractMeal(normalizedQuery),
      },
    );
  }

  @override
  Future<String> execute(Map<String, dynamic> args) {
    final date = args['date']?.toString() ?? _formatDate(_clock());
    final meal = args['meal']?.toString() ?? 'all';
    return LunchService.instance.getMealMenu(date, meal: meal);
  }

  bool _looksLikeMealMenuRequest(String query) {
    final asksMenu =
        query.contains('급식') ||
        query.contains('식단') ||
        query.contains('메뉴') ||
        query.contains('lunch menu') ||
        query.contains('school lunch') ||
        query.contains("what's for lunch") ||
        query.contains('whats for lunch');
    if (asksMenu) return true;

    final mentionsMeal =
        query.contains('아침') ||
        query.contains('조식') ||
        query.contains('점심') ||
        query.contains('중식') ||
        query.contains('저녁') ||
        query.contains('석식') ||
        query.contains('breakfast') ||
        query.contains('lunch') ||
        query.contains('dinner');
    if (!mentionsMeal) return false;

    return query.contains('메뉴') ||
        query.contains('뭐') ||
        query.contains('무엇') ||
        query.contains('추천') ||
        query.contains('알려') ||
        query.contains('보여') ||
        query.contains('조회') ||
        query.contains('확인') ||
        query.contains('골라') ||
        query.contains('정해') ||
        query.contains('나와') ||
        query.contains('menu') ||
        query.contains('recommend') ||
        query.contains('suggest') ||
        query.contains('tell me') ||
        query.contains('show me');
  }

  String _extractMeal(String query) {
    final breakfast =
        query.contains('아침') ||
        query.contains('조식') ||
        query.contains('breakfast');
    final lunch =
        query.contains('점심') || query.contains('중식') || query.contains('lunch');
    final dinner =
        query.contains('저녁') ||
        query.contains('석식') ||
        query.contains('dinner');
    final count = [breakfast, lunch, dinner].where((value) => value).length;
    if (count != 1) return 'all';
    if (breakfast) return 'breakfast';
    if (lunch) return 'lunch';
    return 'dinner';
  }

  String _extractDate(String normalizedQuery) {
    final explicitDate = _extractExplicitDate(normalizedQuery);
    if (explicitDate != null) return explicitDate;

    final now = _clock();
    if (normalizedQuery.contains('모레') ||
        normalizedQuery.contains('day after tomorrow')) {
      return _formatDate(now.add(const Duration(days: 2)));
    }
    if (normalizedQuery.contains('내일') ||
        normalizedQuery.contains('tomorrow')) {
      return _formatDate(now.add(const Duration(days: 1)));
    }
    if (normalizedQuery.contains('어제') ||
        normalizedQuery.contains('yesterday')) {
      return _formatDate(now.subtract(const Duration(days: 1)));
    }

    final weekdayDate = _extractWeekdayRelativeDate(normalizedQuery);
    if (weekdayDate != null) return _formatDate(weekdayDate);

    return _formatDate(now);
  }

  String? _extractExplicitDate(String query) {
    final isoMatch = RegExp(
      r'(\d{4})[-./년]\s*(\d{1,2})[-./월]\s*(\d{1,2})',
    ).firstMatch(query);
    if (isoMatch != null) {
      return _formatDate(
        DateTime(
          int.parse(isoMatch.group(1)!),
          int.parse(isoMatch.group(2)!),
          int.parse(isoMatch.group(3)!),
        ),
      );
    }

    final koreanMonthDay = RegExp(
      r'(\d{1,2})\s*월\s*(\d{1,2})\s*일',
    ).firstMatch(query);
    if (koreanMonthDay != null) {
      return _formatDate(
        DateTime(
          _clock().year,
          int.parse(koreanMonthDay.group(1)!),
          int.parse(koreanMonthDay.group(2)!),
        ),
      );
    }

    return null;
  }

  DateTime? _extractWeekdayRelativeDate(String query) {
    final weekdays = <String, int>{
      '월요일': DateTime.monday,
      '월욜': DateTime.monday,
      '화요일': DateTime.tuesday,
      '수요일': DateTime.wednesday,
      '목요일': DateTime.thursday,
      '금요일': DateTime.friday,
      '토요일': DateTime.saturday,
      '일요일': DateTime.sunday,
      'monday': DateTime.monday,
      'mon': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'tue': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'wed': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'thu': DateTime.thursday,
      'friday': DateTime.friday,
      'fri': DateTime.friday,
      'saturday': DateTime.saturday,
      'sat': DateTime.saturday,
      'sunday': DateTime.sunday,
      'sun': DateTime.sunday,
    };

    int? targetWeekday;
    for (final entry in weekdays.entries) {
      if (query.contains(entry.key)) {
        targetWeekday = entry.value;
        break;
      }
    }
    if (targetWeekday == null) return null;

    final now = _clock();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));

    if (query.contains('다다음 주') || query.contains('다다음주')) {
      return startOfWeek.add(Duration(days: 14 + targetWeekday - 1));
    }
    if (query.contains('다음 주') ||
        query.contains('다음주') ||
        query.contains('next week')) {
      return startOfWeek.add(Duration(days: 7 + targetWeekday - 1));
    }
    if (query.contains('지난 주') ||
        query.contains('지난주') ||
        query.contains('last week')) {
      return startOfWeek.add(Duration(days: targetWeekday - 8));
    }
    if (query.contains('이번 주') ||
        query.contains('이번주') ||
        query.contains('this week')) {
      return startOfWeek.add(Duration(days: targetWeekday - 1));
    }
    if (query.contains('다음') || query.contains('next')) {
      final daysUntil = (targetWeekday - now.weekday) % 7;
      return now.add(Duration(days: daysUntil == 0 ? 7 : daysUntil));
    }

    return startOfWeek.add(Duration(days: targetWeekday - 1));
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class WeatherFunctionTool implements ChatFunctionTool {
  @override
  String get name => 'get_weather';

  @override
  Future<FunctionCall?> tryBuildCall({
    required String originalQuery,
    required String normalizedQuery,
    required DateTime now,
  }) async {
    if (!_looksLikeWeatherRequest(normalizedQuery)) return null;

    final locationText = _extractLocationText(normalizedQuery);
    if (locationText == null) {
      return FunctionCall(name: name, args: {'useCurrentLocation': true});
    }

    return FunctionCall(name: name, args: {'locationName': locationText});
  }

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    double? latitude;
    double? longitude;
    var locationName = args['locationName']?.toString();

    if (args['useCurrentLocation'] == true) {
      try {
        final current = await LocationService.instance.getCurrentLocation();
        latitude = current.latitude;
        longitude = current.longitude;
        final reverse = await GeocodingService.instance.reverseGeocode(
          latitude: latitude,
          longitude: longitude,
        );
        locationName = reverse.found
            ? reverse.displayName
            : current.provider == null
            ? '현재 위치'
            : '현재 위치 (${current.provider})';
      } catch (gpsError) {
        try {
          final fallback = await LocationService.instance.getIpBasedLocation();
          latitude = fallback.latitude;
          longitude = fallback.longitude;
          locationName =
              fallback.displayName ??
              (fallback.provider == null
                  ? '현재 위치(IP 기반, 부정확할 수 있음)'
                  : '현재 위치(IP 기반, ${fallback.provider}, 부정확할 수 있음)');
        } catch (fallbackError) {
          return jsonEncode({
            'status': 'error',
            'message':
                '현재 위치를 확인하지 못했습니다. GPS 오류: $gpsError. IP 기반 위치 조회 오류: $fallbackError',
          });
        }
      }
    } else {
      if (locationName == null || locationName.trim().isEmpty) {
        return jsonEncode({
          'status': 'error',
          'message': 'Location name is required for weather lookup.',
        });
      }

      final geocoding = await GeocodingService.instance.geocode(locationName);
      if (!geocoding.found ||
          geocoding.latitude == null ||
          geocoding.longitude == null) {
        return jsonEncode({
          'status': 'error',
          'message':
              geocoding.message ??
              'Could not find coordinates for $locationName.',
        });
      }

      latitude = geocoding.latitude;
      longitude = geocoding.longitude;
      locationName = geocoding.displayName ?? locationName;
    }

    if (latitude == null || longitude == null) {
      return jsonEncode({
        'status': 'error',
        'message': 'Valid latitude and longitude are required.',
      });
    }

    return WeatherService.instance.getWeather(
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
    );
  }

  bool _looksLikeWeatherRequest(String query) {
    return query.contains('날씨') ||
        query.contains('기온') ||
        query.contains('온도') ||
        query.contains('비 와') ||
        query.contains('비와') ||
        query.contains('weather') ||
        query.contains('temperature') ||
        query.contains('rain') ||
        query.contains('forecast');
  }

  String? _extractLocationText(String query) {
    var location = query;
    final patterns = [
      '알려주세요',
      '보여주세요',
      '말해주세요',
      '알려 줘',
      '보여 줘',
      '말해 줘',
      '오늘',
      '지금',
      '현재',
      '내일',
      '모레',
      '날씨',
      '기온',
      '온도',
      '비 와',
      '비와',
      '어떤가요',
      '어떤지',
      '어때',
      '어때?',
      '알려줘',
      '알려',
      '보여줘',
      '주세요',
      '줘',
      '요',
      '조회',
      '확인',
      'today',
      'now',
      'current',
      'tomorrow',
      'weather',
      'temperature',
      'rain',
      'forecast',
      'tell me',
      'show me',
      'what is',
      'what\'s',
      'like',
      '?',
    ];

    for (final pattern in patterns) {
      location = location.replaceAll(pattern, ' ');
    }

    location = location.replaceAll(RegExp(r'\s+'), ' ').trim();
    location = location.replaceFirst(RegExp(r'(에서|에는|에서의|의|은|는|이|가)$'), '');
    if (location.isEmpty) return null;
    return location;
  }
}

class FunctionCall {
  final String name;
  final Map<String, dynamic> args;

  FunctionCall({required this.name, required this.args});
}
