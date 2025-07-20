// lib/chat_page/services/camera_service.dart
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CameraService extends ChangeNotifier with WidgetsBindingObserver {
  /* ---------------------------------------------------------------- static */
  static CameraService? _instance;
  static CameraService get instance {
    if (_instance == null || _instance!._disposed) {
      debugPrint('[CameraService] Creating new instance');
      _instance = CameraService._internal();
    }
    return _instance!;
  }

  /* -------------------------------------------------------------- lifecycle */
  CameraService._internal() {
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[CameraService] Service created');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _cleanupCamera(); // release while in background
        break;
      case AppLifecycleState.resumed:
        restart(); // bring it back
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
  Completer<void>? _initCompleter;

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
      return _initCompleter?.future ?? Future.value();
    }

    await _initializePhoneCamera();
  }

  /// Waits until the app is RESUMED (crucial for iOS) and one frame rendered.
  Future<void> _ensureForegroundReady() async {
    if (!Platform.isIOS) return; // Android unaffected

    while (WidgetsBinding.instance.lifecycleState !=
        AppLifecycleState.resumed) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Ensure at least one frame has been drawn – avoids AVFoundation race.
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    await completer.future;
  }

  Future<void> _initializePhoneCamera() async {
    if (_disposed) return;

    if (_isInitializing) {
      return _initCompleter?.future ?? Future.value();
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      await _ensureForegroundReady();

      debugPrint('[CameraService] Starting camera initialization…');
      await _cleanupCamera();

      // Early disposal check
      if (_disposed) {
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available');

      final description = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Another disposal check before creating controller
      if (_disposed) {
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
        return;
      }

      _camera = CameraController(
        description,
        // Use max resolution for best capture quality
        // Note: This may impact performance on older devices
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Verify camera controller was created
      final camera = _camera;
      if (camera == null) {
        throw Exception('Failed to create camera controller');
      }

      // Check disposal one more time before initialize
      if (_disposed) {
        await camera.dispose();
        _camera = null;
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
        return;
      }

      await camera.initialize();

      // Final disposal check after initialization
      if (_disposed) {
        await camera.dispose();
        _camera = null;
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
        return;
      }

      // Only add listener if we're still not disposed
      camera.addListener(_onCameraError);

      _cameraError = false;
      _cameraInitialized = true;
      debugPrint('[CameraService] Camera initialized successfully');
      debugPrint('[CameraService] Preview size: ${camera.value.previewSize}');

      // Safe completion check
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    } catch (e) {
      debugPrint('[CameraService] Camera initialization error: $e');
      _cameraError = true;
      _cameraInitialized = false;
      await _cleanupCamera();

      // Safe error completion check
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.completeError(e);
      }
    } finally {
      _isInitializing = false;
      _initCompleter = null;
      _safeNotifyListeners();
    }
  }

  /* --------------------------------------------------------- image capture */
  /// Captures a high-quality image
  Future<XFile?> captureImage() async {
    if (!canCapture) {
      debugPrint('[CameraService] Cannot capture - camera not ready');
      return null;
    }

    try {
      debugPrint('[CameraService] Capturing image...');
      final image = await _camera!.takePicture();
      debugPrint('[CameraService] Image captured: ${image.path}');
      return image;
    } catch (e) {
      debugPrint('[CameraService] Error capturing image: $e');
      return null;
    }
  }

  /// Gets information about the captured image resolution
  Size? get captureResolution {
    if (_camera?.description == null) return null;

    // Note: Actual capture resolution depends on the camera hardware
    // and the ResolutionPreset used. The preview size is different from capture size.
    return _camera!.value.previewSize;
  }

  /* -------------------------------------------------------- error handling */
  void _onCameraError() {
    if (_disposed || _camera == null) return;

    if (_camera!.value.hasError) {
      debugPrint(
        '[CameraService] Runtime camera error: '
        '${_camera!.value.errorDescription}',
      );
      _cameraError = true;
      _cameraInitialized = false;
      _safeNotifyListeners();

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

    WidgetsBinding.instance.removeObserver(this);
    debugPrint('[CameraService] Disposing service…');
    _disposed = true;

    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      _initCompleter!.complete();
    }
    _initCompleter = null;

    _cleanupCamera().catchError((e) {
      debugPrint('[CameraService] Error during disposal: $e');
    });

    super.dispose();

    if (_instance == this) _instance = null;
  }
}
