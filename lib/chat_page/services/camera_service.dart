// lib/chat_page/services/camera_service.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CameraService extends ChangeNotifier with WidgetsBindingObserver {
  /* ---------------------------------------------------------------- static */
  static CameraService? _instance;
  static CameraService get instance {
    // Create new instance if disposed or null
    if (_instance == null || _instance!._disposed) {
      debugPrint('[CameraService] Creating new instance');
      _instance = CameraService._internal();
    }
    return _instance!;
  }

  /* -------------------------------------------------------------- lifecycle */
  CameraService._internal() {
    WidgetsBinding.instance.addObserver(this); // NEW
    debugPrint('[CameraService] Service created');
  }

  // App lifecycle → release / renew camera
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NEW
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // Release the hardware while in background
        _cleanupCamera();
        break;

      case AppLifecycleState.resumed:
        // Re‑create controller & restart preview
        restart();
        break;

      default:
        break;
    }
  }

  /* ----------------------------------------------------------- camera state */
  CameraController? _camera;
  bool _cameraInitialized = false;
  bool _cameraError = false;

  /* ------------------------------------------------------------ bookkeeping */
  bool _isInitializing = false;
  bool _disposed = false;
  Completer<void>? _initCompleter; // Synchronise initialise()

  /* --------------------------------------------------------------- getters */
  CameraController? get camera => _camera;
  bool get cameraInitialized => _cameraInitialized;
  bool get cameraError => _cameraError;

  bool get canCapture =>
      !_disposed && _cameraInitialized && !_cameraError && _camera != null;

  /* ------------------------------------------------------------ initialise */
  Future<void> initialize() async {
    if (_disposed) return;

    if (_isInitializing) {
      // Wait for ongoing init
      return _initCompleter?.future ?? Future.value();
    }

    await _initializePhoneCamera();
  }

  Future<void> _initializePhoneCamera() async {
    if (_disposed) return;

    if (_isInitializing) {
      return _initCompleter?.future ?? Future.value();
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      debugPrint('[CameraService] Starting camera initialization…');

      // Clean existing controller
      await _cleanupCamera();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available');

      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _camera = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _camera!.initialize();
      _camera!.addListener(_onCameraError);

      _cameraError = false;
      _cameraInitialized = true;
      debugPrint('[CameraService] Camera initialized successfully');
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[CameraService] Camera initialization error: $e');
      _cameraError = true;
      _cameraInitialized = false;
      await _cleanupCamera();
      _initCompleter!.completeError(e);
    } finally {
      _isInitializing = false;
      _initCompleter = null;
      _safeNotifyListeners();
    }
  }

  /* -------------------------------------------------------- error handling */
  void _onCameraError() {
    if (_disposed || _camera == null) return;

    if (_camera!.value.hasError) {
      debugPrint(
        '[CameraService] Camera error detected: ${_camera!.value.errorDescription}',
      );
      _cameraError = true;
      _cameraInitialized = false;
      _safeNotifyListeners();

      // Try to restart after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed && _cameraError) restart();
      });
    }
  }

  /* -------------------------------------------------------------- cleaning */
  Future<void> _cleanupCamera() async {
    if (_camera != null) {
      try {
        _camera!.removeListener(_onCameraError);
        if (_camera!.value.isInitialized) await _camera!.dispose();
      } catch (e) {
        debugPrint('[CameraService] Error during camera cleanup: $e');
      } finally {
        _camera = null;
        _cameraInitialized = false;
      }
    }
  }

  /* -------------------------------------------------------------- restart */
  Future<void> restart() async {
    if (_disposed) return;

    debugPrint('[CameraService] Restarting camera…');
    _isInitializing = false;
    _initCompleter = null;

    await _cleanupCamera();
    _cameraError = false;
    await initialize();
  }

  /* ---------------------------------------------------------- notifications */
  void _safeNotifyListeners() {
    if (!_disposed && hasListeners) {
      try {
        notifyListeners();
      } catch (e) {
        debugPrint('[CameraService] Error notifying listeners: $e');
      }
    }
  }

  /* ---------------------------------------------------------------- dispose */
  @override
  void dispose() {
    if (_disposed) return;

    WidgetsBinding.instance.removeObserver(this); // NEW
    debugPrint('[CameraService] Disposing service…');
    _disposed = true;

    // Complete any pending operations
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      _initCompleter!.complete();
    }
    _initCompleter = null;

    // Camera cleanup (fire‑and‑forget)
    _cleanupCamera().catchError((e) {
      debugPrint('[CameraService] Error during disposal: $e');
    });

    super.dispose();

    // Allow new instance later
    if (_instance == this) _instance = null;
  }
}
