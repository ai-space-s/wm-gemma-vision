// download_page/model_download_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gemma_chat/chat_page/gemma_vision_chat.dart';

import 'models/enums.dart';
import 'models/models.dart';
import 'services/logger.dart';
import 'services/download_manager.dart';
import 'logic/download_logic.dart';
import 'ui/modern_ui_widgets.dart';
import 'ui/ui_helpers.dart';

class ModelDownloadPage extends StatefulWidget {
  const ModelDownloadPage({Key? key}) : super(key: key);

  @override
  State<ModelDownloadPage> createState() => _ModelDownloadPageState();
}

class _ModelDownloadPageState extends State<ModelDownloadPage> {
  DownloadStatus _downloadStatus = DownloadStatus.notStarted;
  DownloadProgress? _progress;
  List<String> _errorMessages = [];
  bool _showAgreementSheet = false;
  late StreamSubscription _logSubscription;
  late DownloadPageLogic _logic;

  @override
  void initState() {
    super.initState();
    _initializeLogic();
    _initializeDownloader();
    _checkDownloadState();
    _setupLogListener();
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  void _initializeLogic() {
    _logic = DownloadPageLogic(
      setDownloadStatus: (status) => setState(() => _downloadStatus = status),
      setProgress: (progress) => setState(() => _progress = progress),
      setErrorMessages: (messages) => setState(() => _errorMessages = messages),
      setShowAgreementSheet: (show) =>
          setState(() => _showAgreementSheet = show),
    );
  }

  void _setupLogListener() {
    _logSubscription = Logger.logStream.listen((logEntry) {
      setState(() {});
    });
  }

  Future<void> _initializeDownloader() async {
    await DownloadManager.initialize();
    Logger.info('Download manager initialized');
  }

  Future<void> _checkDownloadState() async {
    await _logic.checkForOngoingDownloads(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Spacer to push content towards center
                  const Spacer(flex: 1),

                  // Main content area - centered
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Download icon
                      ModernUIWidgets.buildDownloadIcon(
                        _downloadStatus,
                        _progress,
                      ),

                      const SizedBox(height: 32),

                      // Status message
                      ModernUIWidgets.buildStatusMessage(
                        _downloadStatus,
                        _progress,
                        _errorMessages,
                      ),

                      const SizedBox(height: 24),

                      // Progress bar
                      ModernUIWidgets.buildProgressBar(
                        _progress,
                        _downloadStatus,
                      ),

                      const SizedBox(height: 40),

                      // Action buttons
                      ModernUIWidgets.buildActionButtons(
                        _downloadStatus,
                        () => _logic.startDownload(),
                        () => _logic.pauseDownload(),
                        () => _logic.resumeDownload(),
                        () => _logic.showCancelConfirmation(context),
                        () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => ChatPage()),
                        ),
                      ),
                    ],
                  ),

                  // Spacer to balance the layout
                  const Spacer(flex: 1),

                  // Error info button at bottom if there are errors
                  if (_errorMessages.isNotEmpty &&
                      _downloadStatus == DownloadStatus.failed) ...[
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: TextButton.icon(
                        onPressed: () =>
                            UIHelpers.showErrorDialog(context, _errorMessages),
                        icon: Icon(Icons.error_outline, color: Colors.red[600]),
                        label: Text(
                          'View Error Details',
                          style: TextStyle(color: Colors.red[600]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),

            // Logs button positioned at top right
            ModernUIWidgets.buildLogsButton(
              context,
              () => UIHelpers.showLogsDialog(context),
            ),
          ],
        ),
      ),
      bottomSheet: _showAgreementSheet
          ? ModernUIWidgets.buildLicenseBottomSheet(
              context,
              () => _logic.cancelLicenseAgreement(),
              () => _logic.openLicenseAgreement(),
            )
          : null,
    );
  }
}
