// lib/download_page/ui/modern_ui_widgets.dart

import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../models/models.dart';

class ModernUIWidgets {
  static Widget buildDownloadIcon(
      DownloadStatus status,
      DownloadProgress? progress,
      ) {
    IconData icon;
    Color color;
    bool animate = false;

    switch (status) {
      case DownloadStatus.notStarted:
        icon = Icons.cloud_download_outlined;
        color = Colors.blue;
        break;
      case DownloadStatus.checkingAccess:
      case DownloadStatus.authenticating:
        icon = Icons.lock_open_rounded;
        color = Colors.orange;
        animate = true;
        break;
      case DownloadStatus.awaitingLicenseAcceptance:
        icon = Icons.assignment_outlined;
        color = Colors.purple;
        break;
      case DownloadStatus.downloading:
        icon = Icons.downloading_rounded;
        color = Colors.blue;
        animate = true;
        break;
      case DownloadStatus.copying: // [추가] 복사 중 아이콘
        icon = Icons.file_copy_rounded;
        color = Colors.teal;
        animate = true;
        break;
      case DownloadStatus.paused:
        icon = Icons.pause_circle_outline_rounded;
        color = Colors.amber;
        break;
      case DownloadStatus.completed:
        icon = Icons.check_circle_outline_rounded;
        color = Colors.green;
        break;
      case DownloadStatus.failed:
        icon = Icons.error_outline_rounded;
        color = Colors.red;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 120,
      width: 120,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: animate
          ? _PulsingIcon(icon: icon, color: color)
          : Icon(icon, size: 64, color: color),
    );
  }

  static Widget buildStatusMessage(
      DownloadStatus status,
      DownloadProgress? progress,
      List<String> errorMessages,
      ) {
    String title;
    String subtitle;

    switch (status) {
      case DownloadStatus.notStarted:
        title = 'Ready to Download';
        subtitle = 'Tap the button below to start';
        break;
      case DownloadStatus.checkingAccess:
        title = 'Checking Access';
        subtitle = 'Verifying model availability...';
        break;
      case DownloadStatus.authenticating:
        title = 'Authenticating';
        subtitle = 'Please sign in to continue';
        break;
      case DownloadStatus.awaitingLicenseAcceptance:
        title = 'License Agreement';
        subtitle = 'Please accept the license terms';
        break;
      case DownloadStatus.downloading:
        title = 'Downloading Model';
        subtitle = progress != null
            ? '${progress.downloadedBytes}% completed'
            : 'Starting download...';
        break;
      case DownloadStatus.copying: // [추가] 복사 중 메시지
        title = 'Copying Model';
        subtitle = 'Copying model files from assets...';
        break;
      case DownloadStatus.paused:
        title = 'Download Paused';
        subtitle = 'Tap resume to continue';
        break;
      case DownloadStatus.completed:
        title = 'Download Complete';
        subtitle = 'Model is ready to use';
        break;
      case DownloadStatus.failed:
        title = 'Download Failed';
        subtitle = errorMessages.isNotEmpty
            ? errorMessages.first
            : 'An unknown error occurred';
        break;
    }

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Widget buildProgressBar(
      DownloadProgress? progress,
      DownloadStatus status,
      ) {
    if (status == DownloadStatus.notStarted ||
        status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.awaitingLicenseAcceptance) {
      return const SizedBox(height: 4, width: 200); // Placeholder
    }

    // Checking/Auth state
    if (status == DownloadStatus.checkingAccess ||
        status == DownloadStatus.authenticating) {
      return const SizedBox(
        width: 200,
        child: LinearProgressIndicator(minHeight: 4),
      );
    }

    // Downloading/Copying/Paused state
    final value = (progress?.downloadedBytes ?? 0) / 100.0;

    return Column(
      children: [
        SizedBox(
          width: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                status == DownloadStatus.paused ? Colors.amber : Colors.blue,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget buildActionButtons(
      DownloadStatus status,
      VoidCallback onStart,
      VoidCallback onPause,
      VoidCallback onResume,
      VoidCallback onCancel,
      VoidCallback onContinue, {
        VoidCallback? onRetryLoad, // [추가] 로드 재시도 콜백
        VoidCallback? onReCopy,    // [추가] 복사 재시도 콜백
      }) {
    switch (status) {
      case DownloadStatus.notStarted:
        return _buildButton('Start Download', onStart);

      case DownloadStatus.downloading:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton('Pause', onPause, isSecondary: true),
            const SizedBox(width: 16),
            _buildButton('Cancel', onCancel, isDestructive: true),
          ],
        );

      case DownloadStatus.copying: // [추가] 복사 중에는 버튼 숨김 (취소 불가 가정 또는 필요시 추가)
        return const SizedBox.shrink();

      case DownloadStatus.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton('Resume', onResume),
            const SizedBox(width: 16),
            _buildButton('Cancel', onCancel, isDestructive: true),
          ],
        );

      case DownloadStatus.completed:
        return _buildButton('Continue', onContinue);

      case DownloadStatus.awaitingLicenseAcceptance:
      case DownloadStatus.checkingAccess:
      case DownloadStatus.authenticating:
        return const SizedBox.shrink();

      case DownloadStatus.failed:
      // [수정] 실패 시 여러 복구 옵션 제공
        return Column(
          children: [
            _buildButton('Retry Download', onStart), // 기존: 삭제 후 재다운로드

            if (onRetryLoad != null) ...[
              const SizedBox(height: 12),
              _buildButton('Retry Model Load', onRetryLoad, isSecondary: true),
            ],

            if (onReCopy != null) ...[
              const SizedBox(height: 12),
              _buildButton('Re-copy Model', onReCopy, isSecondary: true),
            ],
          ],
        );
    }
  }

  static Widget _buildButton(
      String label,
      VoidCallback onPressed, {
        bool isSecondary = false,
        bool isDestructive = false,
      }) {
    Color bgColor;
    Color textColor;

    if (isDestructive) {
      bgColor = Colors.red[50]!;
      textColor = Colors.red[700]!;
    } else if (isSecondary) {
      bgColor = Colors.grey[200]!;
      textColor = Colors.grey[800]!;
    } else {
      bgColor = Colors.blue;
      textColor = Colors.white;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            border: isDestructive ? Border.all(color: Colors.red[200]!) : null,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            constraints: const BoxConstraints(minWidth: 140),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget buildLogsButton(BuildContext context, VoidCallback onPressed) {
    return Positioned(
      top: 0,
      right: 0,
      child: IconButton(
        icon: const Icon(Icons.terminal_rounded, color: Colors.grey),
        onPressed: onPressed,
        tooltip: 'Show Logs',
      ),
    );
  }

  // (BottomSheet 코드는 변경 없음, 생략 가능하지만 전체 코드 요청이므로 포함하거나 유지)
  static Widget buildLicenseBottomSheet(
      BuildContext context,
      VoidCallback onCancel,
      VoidCallback onOpenBrowser,
      ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'License Agreement Required',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'To download this model, you must accept the license agreement on HuggingFace.',
            style: TextStyle(fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onOpenBrowser,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('View License on HuggingFace'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Icon(widget.icon, size: 64, color: widget.color),
    );
  }
}