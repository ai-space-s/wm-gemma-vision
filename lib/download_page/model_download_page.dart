// lib/download_page/model_download_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../chat_page/gemma_vision_chat.dart'; // [수정] 경로가 프로젝트 구조에 맞게 수정됨 (상위 폴더 확인 필요)
// 만약 같은 lib 폴더 내라면: import '../chat_page/gemma_vision_chat.dart';
// 제공해주신 파일 경로(lib/download_page/...)를 기준으로 import 경로를 조정했습니다.
// 원래 제공된 코드의 import 'package:gemma_chat/...' 부분은 패키지명에 따라 다를 수 있으므로
// 제공해주신 파일 구조에 맞춰 상대 경로로 수정하거나, 원래 import를 유지합니다.
// 여기서는 안전하게 원래 import를 유지하되, 문맥상 필요한 ChatPage가 있는 곳을 가리킵니다.

import 'models/enums.dart';
import 'models/models.dart';
import 'services/logger.dart';
import 'services/download_manager.dart';
import 'logic/download_logic.dart';
import 'ui/modern_ui_widgets.dart';
import 'ui/ui_helpers.dart';

class ModelDownloadPage extends StatefulWidget {
  final DownloadTarget target;

  const ModelDownloadPage({
    super.key,
    this.target = DownloadTarget.mainModel, // Default to main model
  });

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
    _logic.dispose();
    super.dispose();
  }

  void _initializeLogic() {
    _logic = DownloadPageLogic(
      target: widget.target,
      setDownloadStatus: (status) => setState(() => _downloadStatus = status),
      setProgress: (progress) => setState(() => _progress = progress),
      setErrorMessages: (messages) => setState(() => _errorMessages = messages),
      setShowAgreementSheet: (show) =>
          setState(() => _showAgreementSheet = show),
    );
  }

  void _setupLogListener() {
    _logSubscription = Logger.logStream.listen((logEntry) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeDownloader() async {
    await DownloadManager.initialize();
    Logger.info('Download manager initialized for ${widget.target}');
  }

  Future<void> _checkDownloadState() async {
    // 기존 로직: 진행 중인 다운로드나 파일 존재 여부 확인
    await _logic.checkForOngoingDownloads(context);

    // [추가] 모델이 이미 존재하여 'completed' 상태가 되었다면 자동으로 스킵
    if (_downloadStatus == DownloadStatus.completed && mounted) {
      Logger.info('Model already exists. Auto-skipping download page.');
      // UI가 그려진 후 이동하도록 약간의 지연을 주거나 바로 이동 가능하지만,
      // 사용자 경험상 잠깐의 로딩 후 넘어가는 것이 자연스러우므로 바로 호출합니다.
      _handleNavigation(true);
    }
  }

  // 다운로드 완료/취소 후 네비게이션 처리
  void _handleNavigation(bool success) {
    if (!mounted) return;

    if (widget.target == DownloadTarget.mainModel) {
      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ChatPage()),
        );
      }
    } else {
      // For FunctionGemma, we return to Settings Page with result
      Navigator.of(context).pop(success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.target == DownloadTarget.mainModel
        ? "Gemma Vision Model"
        : "Function Calling Model";

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: widget.target == DownloadTarget.functionModel
          ? AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () =>
              Navigator.of(context).pop(false), // 취소 시 false 반환
        ),
      )
          : null, // Main model usually shows as full screen splash
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(flex: 1),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 모델 이름 표시
                      Text(
                        _logic.currentModelFullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      ModernUIWidgets.buildDownloadIcon(
                        _downloadStatus,
                        _progress,
                      ),

                      const SizedBox(height: 32),

                      ModernUIWidgets.buildStatusMessage(
                        _downloadStatus,
                        _progress,
                        _errorMessages,
                      ),

                      const SizedBox(height: 24),

                      ModernUIWidgets.buildProgressBar(
                        _progress,
                        _downloadStatus,
                      ),

                      const SizedBox(height: 40),

                      ModernUIWidgets.buildActionButtons(
                        _downloadStatus,
                            () => _logic.startDownload(),
                            () => _logic.pauseDownload(),
                            () => _logic.resumeDownload(),
                            () => _logic.showCancelConfirmation(context),
                            () => _handleNavigation(true), // Success callback
                      ),
                    ],
                  ),
                  const Spacer(flex: 1),

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