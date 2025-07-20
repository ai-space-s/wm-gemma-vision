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
        // Check if camera is initialized
        if (!camera.value.isInitialized) {
          return Center(
            child: Container(
              width: constraints.maxWidth * 0.8,
              height: constraints.maxHeight * 0.6,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }

        // Get camera preview size and swap width/height for proper orientation
        final previewSize = camera.value.previewSize;
        if (previewSize == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Calculate dimensions that fit within constraints while maintaining aspect ratio
        // Note: We swap width/height here because camera preview size is in landscape orientation
        final cameraAspectRatio = previewSize.height / previewSize.width;

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
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Use the swapped dimensions like in your working code
                  width: previewSize.height,
                  height: previewSize.width,
                  child: CameraPreview(camera),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
