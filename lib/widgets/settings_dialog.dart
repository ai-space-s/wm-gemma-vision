import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:gemma_chat/services/camera_service.dart';

/// Show settings dialog with improved accessibility
Future<void> showSettingsDialog({
  required BuildContext context,
  required String systemCtx,
  required double speechRate,
  required PreferredBackend backend,
  required CameraSource cameraSource,
  required String ipCameraUrl,
  required Function(String, double, PreferredBackend, CameraSource, String)
  onSave,
  VoidCallback? onDismiss,
}) async {
  final ctxCtl = TextEditingController(text: systemCtx);
  final ipCtl = TextEditingController(text: ipCameraUrl);

  double tmpRate = speechRate;
  PreferredBackend tmpBackend = backend;
  CameraSource tmpCameraSource = cameraSource;

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

              // Camera source dropdown
              Semantics(
                label:
                    'Camera source. Dropdown button. Current value: ${tmpCameraSource == CameraSource.phone ? "Phone camera" : "IP camera"}',
                button: true,
                child: Focus(
                  child: DropdownButtonFormField<CameraSource>(
                    value: tmpCameraSource,
                    items: const [
                      DropdownMenuItem(
                        value: CameraSource.phone,
                        child: Text('Phone camera'),
                      ),
                      DropdownMenuItem(
                        value: CameraSource.ip,
                        child: Text('IP camera'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => tmpCameraSource = v!),
                    decoration: const InputDecoration(
                      labelText: 'Camera source',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),

              // IP camera URL (conditional)
              if (tmpCameraSource == CameraSource.ip) ...[
                const SizedBox(height: 16),
                Semantics(
                  label: 'IP camera URL. Text field',
                  textField: true,
                  child: Focus(
                    child: TextField(
                      controller: ipCtl,
                      decoration: const InputDecoration(
                        labelText: 'IP camera URL',
                        hintText: 'http://192.168.4.1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],

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
                label: 'Controller button mappings reference',
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
                        'Controller mappings:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildMappingRow('A button', 'Describe room'),
                      _buildMappingRow('B button', 'Tell me what you see'),
                      _buildMappingRow('X button', 'Find exit'),
                      _buildMappingRow('Y button', 'Read text'),
                      _buildMappingRow('Plus button', 'New chat'),
                      _buildMappingRow('Star button', 'Show messages'),
                      _buildMappingRow('Heart button', 'Toggle settings'),
                      _buildMappingRow(
                        'Right trigger',
                        'Start or stop dictation',
                      ),
                      _buildMappingRow('Left trigger', 'Enter or activate'),
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
    await onSave(
      ctxCtl.text.trim(),
      tmpRate,
      tmpBackend,
      tmpCameraSource,
      ipCtl.text,
    );
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
            width: 100,
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
