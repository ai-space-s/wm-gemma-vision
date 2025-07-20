// lib/chat_page/handlers/initialization_handler.dart
import 'package:flutter/material.dart';
import 'package:gemma_chat/download_page/model_download_page.dart';
import '../services/error_dialog_service.dart';
import '../services/bootstrap_manager.dart';

class InitializationHandler {
  static Future<void> handleInitError({
    required BuildContext context,
    required bool mounted,
    required bool disposed,
    required bool redirectedOnError,
    required void Function(bool) setRedirectedOnError,
  }) async {
    if (disposed || !mounted) return;

    debugPrint("Gemma service initialization failed");

    if (!mounted || redirectedOnError || disposed) return;
    setRedirectedOnError(true);

    try {
      if (mounted && !disposed && context.mounted) {
        final result = await ErrorDialogService.showInitializationErrorDialog(
          context,
        );

        if (result == 'retry') {
          await retryInitialization(
            context: context,
            mounted: () => mounted,
            disposed: () => disposed,
          );
        } else {
          navigateToDownloadPage(context);
        }
      }
    } catch (e) {
      debugPrint("Error showing initialization error dialog: $e");
      navigateToDownloadPage(context);
    }
  }

  static Future<void> retryInitialization({
    required BuildContext context,
    required bool Function() mounted,
    required bool Function() disposed,
  }) async {
    if (disposed() || !mounted()) return;

    try {
      debugPrint("[InitializationHandler] Retrying initialization...");

      // Reset bootstrap manager state
      BootstrapManager.reset();

      // Small delay to let UI update
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint(
        "[InitializationHandler] Retry completed - app should restart bootstrap",
      );
    } catch (e) {
      debugPrint("[InitializationHandler] Retry failed: $e");
      if (mounted() && !disposed()) {
        await ErrorDialogService.showRetryFailedDialog(
          context,
          () => navigateToDownloadPage(context),
        );
      }
    }
  }

  static void navigateToDownloadPage(BuildContext context) {
    try {
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ModelDownloadPage()),
        );
      }
    } catch (e) {
      debugPrint("Error navigating to download page: $e");
    }
  }
}
