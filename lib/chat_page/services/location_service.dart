// lib/chat_page/services/location_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService instance = LocationService._internal();

  LocationService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.tommasogiovannini.gemma/location',
  );

  Future<DeviceLocation> getCurrentLocation() async {
    if (kIsWeb) {
      throw UnsupportedError('Current location is not supported on Web.');
    }

    var permission = await Permission.locationWhenInUse.status;
    if (permission.isDenied) {
      permission = await Permission.locationWhenInUse.request();
    }

    if (!permission.isGranted) {
      throw StateError('Location permission was not granted.');
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCurrentLocation',
    );
    if (result == null) {
      throw StateError('Location lookup returned no result.');
    }

    final latitude = double.tryParse(result['latitude'].toString());
    final longitude = double.tryParse(result['longitude'].toString());
    if (latitude == null || longitude == null) {
      throw StateError('Location lookup returned invalid coordinates.');
    }

    return DeviceLocation(
      latitude: latitude,
      longitude: longitude,
      provider: result['provider']?.toString(),
      displayName: result['displayName']?.toString(),
    );
  }

  Future<DeviceLocation> getIpBasedLocation() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'IP-based native location is not supported on Web.',
      );
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getIpBasedLocation',
    );
    if (result == null) {
      throw StateError('IP-based location lookup returned no result.');
    }

    final latitude = double.tryParse(result['latitude'].toString());
    final longitude = double.tryParse(result['longitude'].toString());
    if (latitude == null || longitude == null) {
      throw StateError(
        'IP-based location lookup returned invalid coordinates.',
      );
    }

    return DeviceLocation(
      latitude: latitude,
      longitude: longitude,
      provider: result['provider']?.toString(),
      displayName: result['displayName']?.toString(),
    );
  }
}

class DeviceLocation {
  DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.provider,
    this.displayName,
  });

  final double latitude;
  final double longitude;
  final String? provider;
  final String? displayName;
}
