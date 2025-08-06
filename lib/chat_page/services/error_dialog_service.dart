// lib/chat_page/services/error_dialog_service.dart
import 'package:flutter/material.dart';
import 'package:gemma_chat/download_page/services/download_manager.dart';
import 'package:gemma_chat/download_page/services/download_state_manager.dart';

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
                // Error icon with gradient background
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.red[400]!, Colors.red[600]!],
                    ),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // Clear title explaining the issue
                Text(
                  'Failed to Load Model',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Clear explanation of what happened
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
                        'Possible cause:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.download_done,
                            size: 18,
                            color: Colors.orange[600],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Model did not download correctly - the file may be corrupted or incomplete',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                Column(
                  children: [
                    // Primary action: Delete & Retry Download
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
                          onPressed: () async {
                            // Show loading while deleting
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext context) {
                                return Dialog(
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(width: 20),
                                        const Text(
                                          'Deleting corrupted model...',
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );

                            // Delete the model files
                            await DownloadManager.cancelAndDeleteDownload();
                            await DownloadStateManager.clearDownloadState();

                            // Use the nuclear cleanup to be absolutely sure
                            await DownloadManager.cleanupAllModelFiles();

                            // Close loading dialog
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }

                            // Return to caller with 'delete' action
                            if (context.mounted) {
                              Navigator.of(context).pop('delete');
                            }
                          },
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Delete Model & Retry Download',
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

                    // Secondary action: Quit app
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop('quit'),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Quit App',
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

  /// Simple dialog when retry attempts fail
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
            const Text('Model Still Not Working'),
          ],
        ),
        content: const Text(
          'The model file appears to be corrupted. Please use "Delete Model & Retry Download" to clean up and download a fresh copy.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onGoToSetup();
            },
            child: const Text('Go to Setup'),
          ),
        ],
      ),
    );
  }
}
