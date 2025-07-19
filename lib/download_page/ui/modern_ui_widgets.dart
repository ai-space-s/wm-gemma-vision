// download_page/ui/modern_ui_widgets.dart

import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../models/models.dart';

class ModernUIWidgets {
  // Modern gradient button
  static Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required String text,
    required IconData icon,
    List<Color>? gradientColors,
    bool isSecondary = false,
    double? width,
  }) {
    final colors =
        gradientColors ??
        (isSecondary
            ? [Colors.grey[400]!, Colors.grey[500]!]
            : [const Color(0xFF2196F3), const Color(0xFF1976D2)]);

    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onPressed != null
              ? colors
              : [Colors.grey[300]!, Colors.grey[400]!],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: colors[0].withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Download icon without circular progress
  static Widget buildDownloadIcon(
    DownloadStatus status,
    DownloadProgress? progress,
  ) {
    Widget iconWidget;
    Color iconColor = const Color(0xFF2196F3);

    switch (status) {
      case DownloadStatus.notStarted:
      case DownloadStatus.cancelled:
      case DownloadStatus.failed:
        iconWidget = Icon(Icons.download_rounded, size: 80, color: iconColor);
        break;
      case DownloadStatus.checkingAccess:
      case DownloadStatus.authenticating:
        iconWidget = SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        );
        break;
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        iconWidget = Icon(
          status == DownloadStatus.paused
              ? Icons.pause_rounded
              : Icons.download_rounded,
          size: 80,
          color: iconColor,
        );
        break;
      case DownloadStatus.completed:
        iconWidget = Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
            ),
          ),
          child: const Icon(Icons.check_rounded, size: 40, color: Colors.white),
        );
        break;
      case DownloadStatus.awaitingLicenseAcceptance:
        iconWidget = Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.orange[400]!, Colors.orange[600]!],
            ),
          ),
          child: const Icon(
            Icons.assignment_rounded,
            size: 40,
            color: Colors.white,
          ),
        );
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: iconWidget,
    );
  }

  // Modern status message with consistent text color
  static Widget buildStatusMessage(
    DownloadStatus status,
    DownloadProgress? progress,
    List<String> errorMessages,
  ) {
    String title;
    String subtitle;
    Color textColor = Colors.grey[800]!;

    switch (status) {
      case DownloadStatus.notStarted:
        title = "Ready to Download";
        subtitle =
            "You'll need to create a free Hugging Face account to accept the model license and download. Requires 3.14GB of storage space.";
        break;
      case DownloadStatus.checkingAccess:
        title = "Checking Access";
        subtitle = "Verifying model availability and permissions...";
        break;
      case DownloadStatus.authenticating:
        title = "Authenticating";
        subtitle = "Connecting to your Hugging Face account...";
        break;
      case DownloadStatus.awaitingLicenseAcceptance:
        title = "License Agreement Required";
        subtitle =
            "Please review and accept the model license agreement on Hugging Face to proceed with the download";
        break;
      case DownloadStatus.downloading:
        title = "Downloading";
        subtitle =
            "This may take a few minutes, feel free to come back later. The download will continue in the background.";
        break;
      case DownloadStatus.paused:
        title = "Download Paused";
        subtitle =
            "Your download has been paused. Tap Resume to continue downloading.";
        break;
      case DownloadStatus.completed:
        title = "Download Complete!";
        subtitle =
            "The AI model is ready to use. You can now start chatting offline.";
        break;
      case DownloadStatus.failed:
        title = "Download Failed";
        subtitle = errorMessages.isNotEmpty
            ? "${errorMessages.last} Please try again or check your connection."
            : "Something went wrong during the download. Please try again.";
        break;
      case DownloadStatus.cancelled:
        // This case should not normally be reached since we reset to notStarted,
        // but included for exhaustive matching
        title = "Ready to Download";
        subtitle =
            "You'll need to create a free Hugging Face account to accept the model license and download. Requires 3.14GB of storage space.";
        break;
    }

    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 16,
            color: textColor.withOpacity(0.7),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        // Show percentage between subtitle and progress bar
        if (progress != null &&
            (status == DownloadStatus.downloading ||
                status == DownloadStatus.paused)) ...[
          const SizedBox(height: 20),
          Text(
            "${progress.progressPercent}%",
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // Progress bar with left-to-right alignment
  static Widget buildProgressBar(
    DownloadProgress? progress,
    DownloadStatus status,
  ) {
    if (progress == null ||
        (status != DownloadStatus.downloading &&
            status != DownloadStatus.paused)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Colors.grey[200],
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.progress,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: status == DownloadStatus.paused
                    ? [Colors.orange[400]!, Colors.orange[600]!]
                    : [const Color(0xFF2196F3), const Color(0xFF1976D2)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Action buttons with proper spacing and conditional cancel button
  static Widget buildActionButtons(
    DownloadStatus status,
    VoidCallback onStartDownload,
    VoidCallback onPauseDownload,
    VoidCallback onResumeDownload,
    VoidCallback onCancelDownload,
    VoidCallback onGoToChat,
  ) {
    switch (status) {
      case DownloadStatus.notStarted:
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return _buildGradientButton(
          onPressed: onStartDownload,
          text: 'Download',
          icon: Icons.download_rounded,
          width: double.infinity,
        );

      case DownloadStatus.awaitingLicenseAcceptance:
        return _buildGradientButton(
          onPressed: onStartDownload,
          text: 'Start Download',
          icon: Icons.download_rounded,
          width: double.infinity,
        );

      case DownloadStatus.downloading:
        return Row(
          children: [
            Expanded(
              child: _buildGradientButton(
                onPressed: onPauseDownload,
                text: 'Pause',
                icon: Icons.pause_rounded,
                isSecondary: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildGradientButton(
                onPressed: onCancelDownload,
                text: 'Cancel',
                icon: Icons.close_rounded,
                gradientColors: [Colors.red[400]!, Colors.red[600]!],
              ),
            ),
          ],
        );

      case DownloadStatus.paused:
        return _buildGradientButton(
          onPressed: onResumeDownload,
          text: 'Resume',
          icon: Icons.play_arrow_rounded,
          width: double.infinity,
        );

      case DownloadStatus.completed:
        // Directly navigate to chat instead of showing button
        WidgetsBinding.instance.addPostFrameCallback((_) => onGoToChat());
        return const SizedBox.shrink();

      default:
        return const SizedBox.shrink();
    }
  }

  // Simple logs button only
  static Widget buildLogsButton(BuildContext context, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.only(top: 16, right: 16),
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: IconButton(
            icon: Icon(Icons.list_alt_rounded, color: Colors.grey[700]),
            onPressed: onPressed,
            tooltip: 'View Logs',
          ),
        ),
      ),
    );
  }

  // License agreement bottom sheet
  static Widget buildLicenseBottomSheet(
    BuildContext context,
    VoidCallback onCancel,
    VoidCallback onViewLicense,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.orange[400]!, Colors.orange[600]!],
              ),
            ),
            child: const Icon(
              Icons.assignment_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'License Agreement Required',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This model requires acceptance of license terms on Hugging Face. Please review and accept the license agreement to continue with the download.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _buildGradientButton(
                  onPressed: onCancel,
                  text: 'Cancel',
                  icon: Icons.close_rounded,
                  gradientColors: [Colors.grey[400]!, Colors.grey[500]!],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGradientButton(
                  onPressed: onViewLicense,
                  text: 'View License',
                  icon: Icons.open_in_new_rounded,
                  gradientColors: [Colors.orange[400]!, Colors.orange[600]!],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
