// widgets/camera_preview_box.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// Widget for displaying phone camera preview with proper aspect ratio
class CameraPreviewBox extends StatelessWidget {
  final CameraController camera;

  const CameraPreviewBox({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get the camera's aspect ratio
        final cameraAspectRatio = camera.value.aspectRatio;

        // Calculate dimensions that fit within constraints while maintaining aspect ratio
        double previewWidth = constraints.maxWidth;
        double previewHeight = previewWidth / cameraAspectRatio;

        // If calculated height exceeds available height, scale down
        if (previewHeight > constraints.maxHeight) {
          previewHeight = constraints.maxHeight;
          previewWidth = previewHeight * cameraAspectRatio;
        }

        return Center(
          child: Container(
            width: previewWidth,
            height: previewHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: CameraPreview(camera),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
