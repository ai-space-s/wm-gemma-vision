// lib/chat_page/services/error_dialog_service.dart
import 'package:flutter/material.dart';

/// User-friendly error dialogs for AI model initialization failures
class ErrorDialogService {
  /// Show detailed error dialog when AI model fails to load with recovery options
  static Future<String?> showInitializationErrorDialog(
    BuildContext context,
  ) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false, // Force user to choose an action
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon with gradient background
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
                    Icons.warning_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // Clear title explaining the issue
                Text(
                  'AI Model Failed to Load',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Detailed explanation of possible causes
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Possible causes:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // List of common causes with icons
                      ..._buildErrorCauses(),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Helpful suggestion box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue[600],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Try closing other apps to free up memory, or restart your device. If nothing else works try deleting the app and reinstalling it.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[800],
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons with clear hierarchy
                Column(
                  children: [
                    // Primary action: Try Again
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue[400]!, Colors.blue[600]!],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue[400]!.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop('retry'),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Try Again',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Secondary action: Return to model setup
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(context).pop('download'),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Return to Model Setup',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Simple dialog when retry attempts fail - directs user to model setup
  static Future<void> showRetryFailedDialog(
    BuildContext context,
    VoidCallback onGoToSetup,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[600], size: 28),
            const SizedBox(width: 12),
            const Text('Retry Failed'),
          ],
        ),
        content: const Text(
          'The AI model still cannot be loaded. This might be a device compatibility issue or the model file may need to be re-downloaded. If nothing else works try deleting the app and reinstalling it.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onGoToSetup();
            },
            child: const Text('Go to Model Setup'),
          ),
        ],
      ),
    );
  }

  /// Build list of common error causes with icons for visual clarity
  static List<Widget> _buildErrorCauses() {
    final causes = [
      {'icon': Icons.memory, 'text': 'Insufficient device memory (RAM)'},
      {
        'icon': Icons.settings_applications,
        'text': 'Backend compatibility issue',
      },
      {'icon': Icons.device_unknown, 'text': 'Device performance constraints'},
      {'icon': Icons.folder_open, 'text': 'Model format incompatibility'},
    ];

    return causes
        .map(
          (cause) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  cause['icon'] as IconData,
                  size: 16,
                  color: Colors.orange[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cause['text'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}
