// lib/chat_page/services/weather_service.dart
import 'dart:convert';
import 'dart:io';

/// Service to fetch weather using Open-Meteo API
class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  static WeatherService get instance => _instance;

  WeatherService._internal();

  static const String _baseUrl = 'api.open-meteo.com';
  static const String _endpoint = '/v1/forecast';

  /// Fetches weather data.
  Future<String> getWeather({
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    final client = HttpClient();
    try {
      double targetLat = latitude;
      double targetLon = longitude;

      if (targetLat < -90 ||
          targetLat > 90 ||
          targetLon < -180 ||
          targetLon > 180 ||
          (targetLat == 0.0 && targetLon == 0.0)) {
        return jsonEncode({
          "status": "error",
          "message":
              "Valid latitude and longitude are required for weather lookup.",
        });
      }

      final queryParams = {
        'latitude': targetLat.toString(),
        'longitude': targetLon.toString(),
        'current':
            'temperature_2m,wind_speed_10m,weather_code,relative_humidity_2m',
        'temperature_unit': 'celsius',
        'wind_speed_unit': 'kmh', // Use km/h as requested
      };

      final uri = Uri.https(_baseUrl, _endpoint, queryParams);

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, "application/json");
      request.headers.set(HttpHeaders.userAgentHeader, "GemmaFunctionApp/1.0");

      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody);
        return _formatWeatherData(data, targetLat, targetLon, locationName);
      } else {
        return jsonEncode({
          "status": "error",
          "message": "API returned status code ${response.statusCode}",
        });
      }
    } catch (e) {
      return jsonEncode({
        "status": "error",
        "message": "Failed to fetch weather: $e",
      });
    } finally {
      client.close();
    }
  }

  String _formatWeatherData(
    Map<String, dynamic> data,
    double lat,
    double lon,
    String? locationName,
  ) {
    try {
      final current = data['current'];
      final temp = current['temperature_2m'];
      final windSpeed = current['wind_speed_10m'];
      final humidity = current['relative_humidity_2m'];
      final weatherCode = int.tryParse(current['weather_code'].toString()) ?? 0;
      final units = data['current_units'];

      final weatherDesc = _getWeatherDescription(weatherCode);

      // Return a structured JSON string for the LLM to read easily
      return jsonEncode({
        "status": "ok",
        if (locationName != null && locationName.isNotEmpty)
          "location_name": locationName,
        "location_coords": "$lat, $lon",
        "temperature": "$temp${units['temperature_2m']}",
        "condition": weatherDesc,
        "wind_speed": "$windSpeed${units['wind_speed_10m']}",
        "humidity": "$humidity${units['relative_humidity_2m']}",
      });
    } catch (e) {
      return jsonEncode({
        "status": "error",
        "message": "Error parsing weather data: $e",
      });
    }
  }

  String _getWeatherDescription(int code) {
    // WMO Weather interpretation codes (WW)
    switch (code) {
      case 0:
        return "Clear sky";
      case 1:
        return "Mainly clear";
      case 2:
        return "Partly cloudy";
      case 3:
        return "Overcast";
      case 45:
      case 48:
        return "Fog";
      case 51:
      case 53:
      case 55:
        return "Drizzle";
      case 61:
      case 63:
      case 65:
        return "Rain";
      case 71:
      case 73:
      case 75:
        return "Snow";
      case 95:
      case 96:
      case 99:
        return "Thunderstorm";
      default:
        return "Unknown";
    }
  }
}
