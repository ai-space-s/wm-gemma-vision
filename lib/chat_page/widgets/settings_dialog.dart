// lib/chat_page/widgets/settings_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Show settings dialog (simplified - no speech rate, help moved here)
Future<void> showSettingsDialog({
  required BuildContext context,
  required String systemCtx,
  required PreferredBackend backend,
  required Function(String, PreferredBackend) onSave,
  VoidCallback? onDismiss,
}) async {
  final ctxCtl = TextEditingController(text: systemCtx);

  PreferredBackend tmpBackend = backend;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Semantics(header: true, child: const Text('Settings')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // System context with better accessibility
              Semantics(
                label: 'System context. Text field. Current value: $systemCtx',
                textField: true,
                child: Focus(
                  child: TextField(
                    controller: ctxCtl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'System context',
                      border: OutlineInputBorder(),
                      helperText: 'Context given to AI for all responses',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Backend dropdown
              Semantics(
                label:
                    'AI Backend. Dropdown button. Current value: ${tmpBackend.name.toUpperCase()}',
                button: true,
                child: Focus(
                  child: DropdownButtonFormField<PreferredBackend>(
                    value: tmpBackend,
                    items: PreferredBackend.values
                        .map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text(b.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => tmpBackend = v!),
                    decoration: const InputDecoration(
                      labelText: 'Backend',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Controller legend with improved semantics
              Semantics(
                label: 'Keyboard shortcuts reference',
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Keyboard shortcuts:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildMappingRow('F1', 'Send with photo'),
                      _buildMappingRow('F2', 'Push-to-talk (hold)'),
                      _buildMappingRow('F3', 'New chat'),
                      _buildMappingRow('F4', 'Find exit'),
                      _buildMappingRow('F5', 'Describe room'),
                      _buildMappingRow('F6', 'Read text'),
                      _buildMappingRow('F7', 'Tell me what you see'),
                      _buildMappingRow('F8', 'Toggle settings'),
                      _buildMappingRow('F9', 'Send text only'),
                      _buildMappingRow('F10', 'Toggle messages'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Cancel button',
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
          ),
          Semantics(
            button: true,
            label: 'Save button',
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );

  // Call dismiss callback if provided
  onDismiss?.call();

  if (result == true) {
    await onSave(ctxCtl.text.trim(), tmpBackend);
  }
}

Widget _buildMappingRow(String button, String action) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Semantics(
      label: '$button: $action',
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              button,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(': $action'),
        ],
      ),
    ),
  );
}
