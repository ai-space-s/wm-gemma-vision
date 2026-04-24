// lib/chat_page/services/geocoding_service.dart
import 'dart:convert';
import 'dart:io';

class GeocodingService {
  static final GeocodingService instance = GeocodingService._internal();

  GeocodingService._internal({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  GeocodingService.forTesting({required HttpClient Function() clientFactory})
    : _clientFactory = clientFactory;

  static const String _baseUrl = 'nominatim.openstreetmap.org';
  static const String _searchEndpoint = '/search';
  static const String _reverseEndpoint = '/reverse';
  static const String _userAgent = 'GemmaVision/1.0 (https://gemmavision.com/)';
  static DateTime? _lastRequestAt;

  final HttpClient Function() _clientFactory;

  Future<GeocodingResult> geocode(String locationName) async {
    final query = locationName.trim();
    if (query.isEmpty) {
      return GeocodingResult.notFound('Location name is required.');
    }

    final uri = Uri.https(_baseUrl, _searchEndpoint, {
      'q': query,
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
    });

    final response = await _getJson(uri);
    if (response is! List || response.isEmpty) {
      return GeocodingResult.notFound('Location not found: $query');
    }

    final first = response.first;
    if (first is! Map<String, dynamic>) {
      return GeocodingResult.notFound('Invalid geocoding response.');
    }

    final latitude = double.tryParse(first['lat']?.toString() ?? '');
    final longitude = double.tryParse(first['lon']?.toString() ?? '');
    if (latitude == null || longitude == null) {
      return GeocodingResult.notFound('Geocoding response has no coordinates.');
    }

    return GeocodingResult.found(
      latitude: latitude,
      longitude: longitude,
      displayName: first['display_name']?.toString() ?? query,
    );
  }

  Future<GeocodingResult> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https(_baseUrl, _reverseEndpoint, {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'json',
      'addressdetails': '1',
    });

    final response = await _getJson(uri);
    if (response is! Map<String, dynamic>) {
      return GeocodingResult.notFound('Invalid reverse geocoding response.');
    }

    final responseLat = double.tryParse(response['lat']?.toString() ?? '');
    final responseLon = double.tryParse(response['lon']?.toString() ?? '');

    return GeocodingResult.found(
      latitude: responseLat ?? latitude,
      longitude: responseLon ?? longitude,
      displayName: response['display_name']?.toString() ?? '현재 위치',
    );
  }

  Future<dynamic> _getJson(Uri uri) async {
    await _respectPublicNominatimRateLimit();

    final client = _clientFactory();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Nominatim returned status code ${response.statusCode}: $responseBody',
          uri: uri,
        );
      }

      return jsonDecode(responseBody);
    } finally {
      client.close();
    }
  }

  Future<void> _respectPublicNominatimRateLimit() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      const minimumGap = Duration(seconds: 1);
      if (elapsed < minimumGap) {
        await Future<void>.delayed(minimumGap - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}

class GeocodingResult {
  const GeocodingResult._({
    required this.found,
    this.latitude,
    this.longitude,
    this.displayName,
    this.message,
  });

  factory GeocodingResult.found({
    required double latitude,
    required double longitude,
    required String displayName,
  }) {
    return GeocodingResult._(
      found: true,
      latitude: latitude,
      longitude: longitude,
      displayName: displayName,
    );
  }

  factory GeocodingResult.notFound(String message) {
    return GeocodingResult._(found: false, message: message);
  }

  final bool found;
  final double? latitude;
  final double? longitude;
  final String? displayName;
  final String? message;
}
