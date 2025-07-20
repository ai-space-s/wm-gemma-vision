// lib/chat_page/widgets/settings_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Modern light theme settings dialog
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
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Configure your AI assistant',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // System context section
                      _buildSectionTitle('System Context'),
                      const SizedBox(height: 12),
                      _buildLightContainer(
                        child: TextField(
                          controller: ctxCtl,
                          maxLines: 3,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Enter system context for AI responses...',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This context will guide all AI responses',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Backend section
                      _buildSectionTitle('AI Backend'),
                      const SizedBox(height: 12),
                      _buildLightContainer(
                        child: DropdownButtonFormField<PreferredBackend>(
                          value: tmpBackend,
                          dropdownColor: Colors.white,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 16,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                          items: PreferredBackend.values
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Row(
                                    children: [
                                      Icon(
                                        b == PreferredBackend.cpu
                                            ? Icons.memory_rounded
                                            : Icons.developer_board_rounded,
                                        color: Colors.blue.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(b.name.toUpperCase()),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => tmpBackend = v!),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Keyboard shortcuts section
                      _buildSectionTitle('Keyboard Shortcuts'),
                      const SizedBox(height: 12),
                      _buildShortcutsContainer(),
                    ],
                  ),
                ),
              ),

              // Action buttons - Fixed overflow issue
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 2),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // If screen is too narrow, stack buttons vertically
                    if (constraints.maxWidth < 200) {
                      return Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: _buildActionButton(
                              label: 'Cancel',
                              onPressed: () => Navigator.pop(ctx, false),
                              isPrimary: false,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _buildActionButton(
                              label: 'Save Changes',
                              onPressed: () => Navigator.pop(ctx, true),
                              isPrimary: true,
                            ),
                          ),
                        ],
                      );
                    } else {
                      // Otherwise, use row layout
                      return Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              label: 'Cancel',
                              onPressed: () => Navigator.pop(ctx, false),
                              isPrimary: false,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildActionButton(
                              label: 'Save Changes',
                              onPressed: () => Navigator.pop(ctx, true),
                              isPrimary: true,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Call dismiss callback if provided
  onDismiss?.call();

  if (result == true) {
    await onSave(ctxCtl.text.trim(), tmpBackend);
  }
}

Widget _buildSectionTitle(String title) {
  return Text(
    title,
    style: TextStyle(
      color: Colors.grey.shade800,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  );
}

Widget _buildLightContainer({required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200, width: 2),
    ),
    child: child,
  );
}

Widget _buildShortcutsContainer() {
  final shortcuts = [
    ('F1', 'Send with photo'),
    ('F2', 'Push-to-talk (hold)'),
    ('F3', 'New chat'),
    ('F4', 'Find exit'),
    ('F5', 'Describe room'),
    ('F6', 'Read text'),
    ('F7', 'Tell me what you see'),
    ('F8', 'Toggle settings'),
    ('F9', 'Send text only'),
    ('F10', 'Toggle messages'),
  ];

  return _buildLightContainer(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: shortcuts
            .map((shortcut) => _buildShortcutRow(shortcut.$1, shortcut.$2))
            .toList(),
      ),
    ),
  );
}

Widget _buildShortcutRow(String key, String action) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            action,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

Widget _buildActionButton({
  required String label,
  required VoidCallback onPressed,
  required bool isPrimary,
}) {
  return Container(
    height: 50,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            gradient: isPrimary
                ? const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  )
                : null,
            color: isPrimary ? null : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary ? Colors.transparent : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
