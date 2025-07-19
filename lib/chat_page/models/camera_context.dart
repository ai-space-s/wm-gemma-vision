// lib/chat_page/models/camera_context.dart
import 'package:camera/camera.dart';
import '../services/camera_service.dart';

/// Encapsulates camera-related context (phone camera only)
class CameraContext {
  final bool cameraInitialized;
  final bool cameraError;
  final CameraController? camera;

  const CameraContext({
    required this.cameraInitialized,
    required this.cameraError,
    this.camera,
  });

  /// Create CameraContext from CameraService
  factory CameraContext.fromService(CameraService service) {
    return CameraContext(
      cameraInitialized: service.cameraInitialized,
      cameraError: service.cameraError,
      camera: service.camera,
    );
  }
}
