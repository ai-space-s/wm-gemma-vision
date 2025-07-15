import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CameraSource { phone, ip }

class CameraService extends ChangeNotifier {
  static final CameraService _instance = CameraService._internal();
  static CameraService get instance => _instance;
  CameraService._internal();

  // Camera management
  CameraController? _camera;
  bool _cameraInitialized = false;
  bool _cameraError = false;

  // Camera source configuration
  CameraSource _cameraSource = CameraSource.phone;
  String _ipCameraUrl = 'http://192.168.4.1';
  InAppWebViewController? _ipCameraWebView;

  // Getters
  CameraController? get camera => _camera;
  bool get cameraInitialized => _cameraInitialized;
  bool get cameraError => _cameraError;
  CameraSource get cameraSource => _cameraSource;
  String get ipCameraUrl => _ipCameraUrl;
  InAppWebViewController? get ipCameraWebView => _ipCameraWebView;

  /// Initialize camera service with saved preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _cameraSource = CameraSource.values[prefs.getInt('camera_source') ?? 0];
    _ipCameraUrl = prefs.getString('ip_camera_url') ?? 'http://192.168.4.1';

    // Only initialize phone camera if that's the selected source
    if (_cameraSource == CameraSource.phone) {
      await initializePhoneCamera();
    }
  }

  /// Initialize phone camera
  Future<void> initializePhoneCamera() async {
    if (_camera != null) return; // Already initialized

    try {
      final cams = await availableCameras();
      if (cams.isNotEmpty) {
        final backCamera = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first,
        );

        _camera = CameraController(
          backCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _camera!.initialize();

        _cameraInitialized = true;
        _cameraError = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      _cameraInitialized = false;
      _cameraError = true;
      notifyListeners();
    }
  }

  /// Update camera source and URL
  Future<void> updateCameraSettings({
    required CameraSource newSource,
    required String newUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final sourceChanged = _cameraSource != newSource;
    final urlChanged = _ipCameraUrl != newUrl;

    if (sourceChanged || urlChanged) {
      _cameraSource = newSource;
      _ipCameraUrl = newUrl;

      await prefs.setInt('camera_source', _cameraSource.index);
      await prefs.setString('ip_camera_url', _ipCameraUrl);

      // If switching to phone camera and not initialized, initialize it
      if (_cameraSource == CameraSource.phone && _camera == null) {
        await initializePhoneCamera();
      }

      notifyListeners();
    }
  }

  /// Set IP camera web view controller
  void setIpCameraWebView(InAppWebViewController controller) {
    _ipCameraWebView = controller;
  }

  /// Take a picture with the phone camera
  Future<XFile?> takePicture() async {
    if (_camera == null || !_cameraInitialized || _cameraError) {
      return null;
    }

    try {
      return await _camera!.takePicture();
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  /// Capture screenshot from IP camera
  Future<Uint8List?> captureIpCameraScreenshot() async {
    if (_ipCameraWebView == null) return null;

    try {
      return await _ipCameraWebView!.takeScreenshot();
    } catch (e) {
      debugPrint('Error capturing IP camera screenshot: $e');
      return null;
    }
  }

  /// Get current camera image based on source
  Future<dynamic> getCurrentImage() async {
    switch (_cameraSource) {
      case CameraSource.phone:
        return await takePicture();
      case CameraSource.ip:
        return await captureIpCameraScreenshot();
    }
  }

  /// Check if camera is ready for capture
  bool get isReadyForCapture {
    switch (_cameraSource) {
      case CameraSource.phone:
        return _cameraInitialized && !_cameraError && _camera != null;
      case CameraSource.ip:
        return _ipCameraWebView != null;
    }
  }

  /// Dispose camera resources
  @override
  void dispose() {
    _camera?.dispose();
    _camera = null;
    _cameraInitialized = false;
    _cameraError = false;
    _ipCameraWebView = null;
    super.dispose();
  }
}
