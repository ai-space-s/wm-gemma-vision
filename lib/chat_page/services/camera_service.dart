// lib/chat_page/services/camera_service.dart
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CameraService extends ChangeNotifier {
  static CameraService? _instance;
  static CameraService get instance {
    // Create new instance if disposed or null
    if (_instance == null || _instance!._disposed) {
      debugPrint('[CameraService] Creating new instance');
      _instance = CameraService._internal();
    }
    return _instance!;
  }

  CameraService._internal() {
    debugPrint('[CameraService] Service created');
  }

  // Camera state
  CameraController? _camera;
  bool _cameraInitialized = false;
  bool _cameraError = false;

  // Lifecycle tracking
  bool _isInitializing = false;
  bool _disposed = false;

  // Getters
  CameraController? get camera => _camera;
  bool get cameraInitialized => _cameraInitialized;
  bool get cameraError => _cameraError;

  /// Initialize the camera service
  Future<void> initialize() async {
    if (_disposed) {
      debugPrint('[CameraService] Cannot initialize - service disposed');
      return;
    }

    if (_isInitializing) {
      debugPrint('[CameraService] Already initializing, waiting...');
      // Wait for current initialization to complete
      while (_isInitializing && !_disposed) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    await _initializePhoneCamera();
  }

  /// Initialize phone camera
  Future<void> _initializePhoneCamera() async {
    if (_disposed) return;

    try {
      _isInitializing = true;
      debugPrint('[CameraService] Starting camera initialization...');

      // Clean up existing camera
      await _cleanupCamera();

      if (_disposed) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Find back camera, fallback to first available
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      if (_disposed) return;

      _camera = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _camera!.initialize();

      if (_disposed) {
        await _cleanupCamera();
        return;
      }

      _cameraInitialized = true;
      _cameraError = false;
      debugPrint('[CameraService] Camera initialized successfully');
    } catch (e) {
      debugPrint('[CameraService] Camera initialization error: $e');
      _cameraError = true;
      _cameraInitialized = false;
      await _cleanupCamera();
    } finally {
      _isInitializing = false;
      if (!_disposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Clean up camera resources
  Future<void> _cleanupCamera() async {
    if (_camera != null) {
      try {
        if (_camera!.value.isInitialized) {
          await _camera!.dispose();
        }
      } catch (e) {
        debugPrint('[CameraService] Error during camera cleanup: $e');
      } finally {
        _camera = null;
        _cameraInitialized = false;
      }
    }
  }

  /// Safely notify listeners
  void _safeNotifyListeners() {
    if (!_disposed && hasListeners) {
      try {
        notifyListeners();
      } catch (e) {
        debugPrint('[CameraService] Error notifying listeners: $e');
      }
    }
  }

  /// Check if camera is ready for capture
  bool get canCapture {
    if (_disposed) return false;
    return _cameraInitialized && !_cameraError && _camera != null;
  }

  /// Restart camera (useful for error recovery)
  Future<void> restart() async {
    if (_disposed) return;

    debugPrint('[CameraService] Restarting camera...');
    await _cleanupCamera();
    _cameraError = false;
    await initialize();
  }

  /// Dispose the service
  @override
  void dispose() {
    if (_disposed) return;

    debugPrint('[CameraService] Disposing service...');
    _disposed = true;
    _isInitializing = false;

    // Clean up camera without awaiting to prevent blocking
    _cleanupCamera().catchError((e) {
      debugPrint('[CameraService] Error during disposal: $e');
    });

    super.dispose();

    // Clear the static instance so a new one can be created
    if (_instance == this) {
      _instance = null;
    }
  }
}
