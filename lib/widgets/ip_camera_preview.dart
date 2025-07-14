// widgets/ip_camera_preview_box.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Widget for displaying IP camera preview
class IpCameraPreviewBox extends StatelessWidget {
  final String ipCameraUrl;
  final Function(InAppWebViewController)? onWebViewCreated;

  const IpCameraPreviewBox({
    Key? key,
    required this.ipCameraUrl,
    this.onWebViewCreated,
  }) : super(key: key);

  String get _htmlContent =>
      '''
    <!DOCTYPE html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {
            margin: 0;
            padding: 0;
            background-color: black;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            overflow: hidden;
          }
          img {
            max-width: 100%;
            max-height: 100%;
            width: auto;
            height: auto;
            object-fit: contain;
          }
        </style>
      </head>
      <body>
        <img src="$ipCameraUrl" onerror="this.style.display='none'; document.getElementById('error').style.display='block';" />
        <div id="error" style="display:none; color:white; text-align:center;">
          <p>Connecting to IP Camera...</p>
          <p style="font-size:12px;">$ipCameraUrl</p>
        </div>
      </body>
    </html>
  ''';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _htmlContent,
          baseUrl: WebUri(ipCameraUrl),
          encoding: 'utf-8',
          mimeType: 'text/html',
        ),
        onWebViewCreated: onWebViewCreated,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          userAgent: "Mozilla/5.0",
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
      ),
    );
  }
}
