// widgets/camera_preview_box.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// Widget for displaying phone camera preview
class CameraPreviewBox extends StatelessWidget {
  final CameraController camera;

  const CameraPreviewBox({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final ratio = camera.value.aspectRatio;
        var w = constraints.maxWidth;
        var h = w / ratio;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * ratio;
        }
        return Center(
          child: SizedBox(width: w, height: h, child: CameraPreview(camera)),
        );
      },
    );
  }
}
