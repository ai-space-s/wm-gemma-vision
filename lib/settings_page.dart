// lib/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'dart:io';
import 'chat_page/widgets/semantic_material_button.dart';
import 'chat_page/widgets/semantic_button_registry.dart';

class SettingsPage extends StatefulWidget {
  final String systemContext;
  final PreferredBackend backend;

  const SettingsPage({
    Key? key,
    required this.systemContext,
    required this.backend,
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _systemContextController;
  late PreferredBackend _selectedBackend;
  bool _hasChanges = false;

  // Platform detection
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _systemContextController = TextEditingController(
      text: widget.systemContext,
    );
    _selectedBackend = widget.backend;

    // Listen for changes
    _systemContextController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _systemContextController.removeListener(_onTextChanged);
    _systemContextController.dispose();
    SemanticButtonRegistry.clear();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasChanges =
          _systemContextController.text.trim() != widget.systemContext.trim() ||
          _selectedBackend != widget.backend;
    });
  }

  void _onBackendChanged(PreferredBackend? backend) {
    if (backend != null) {
      setState(() {
        _selectedBackend = backend;
        _hasChanges =
            _systemContextController.text.trim() !=
                widget.systemContext.trim() ||
            _selectedBackend != widget.backend;
      });
    }
  }

  void _saveSettings() {
    Navigator.of(context).pop({
      'systemContext': _systemContextController.text.trim(),
      'backend': _selectedBackend,
    });
  }

  void _cancelSettings() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <LogicalKeySet, Intent>{
      // Arrow navigation
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.tab): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.tab, LogicalKeyboardKey.shift):
          const PreviousFocusIntent(),

      // Standard activation
      LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
    };

    // Add iOS-specific VoiceOver shortcut
    if (_isIOS) {
      shortcuts[LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.alt,
            LogicalKeyboardKey.space,
          )] =
          const ActivateIntent();
    }

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: {
          // Cross-platform ActivateIntent handler
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              SemanticButtonRegistry.invokeCurrentSemanticTap();
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
            leading: SemanticMaterialButton(
              label: 'Back',
              hint: 'Double-tap to go back to chat',
              onPressed: _cancelSettings,
              child: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.blue,
              ),
            ),
            title: const Text(
              'Settings',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              if (_hasChanges)
                SemanticMaterialButton(
                  label: 'Save',
                  hint: 'Double-tap to save changes and return to chat',
                  onPressed: _saveSettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 16),
            ],
          ),
          body: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // System Context Section
                  _buildSectionHeader(
                    'System Context',
                    'This context guides all AI responses',
                  ),
                  const SizedBox(height: 16),

                  Semantics(
                    label: 'System context text field',
                    hint:
                        'Enter the context that will guide all AI responses. Currently ${_systemContextController.text.length} characters.',
                    textField: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _systemContextController,
                        maxLines: 5,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 16,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter system context for AI responses...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(20),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // AI Backend Section
                  _buildSectionHeader(
                    'AI Backend',
                    'Choose processing method for AI operations',
                  ),
                  const SizedBox(height: 16),

                  _buildBackendSelector(),

                  const SizedBox(height: 32),

                  // Keyboard Shortcuts Section
                  _buildSectionHeader(
                    'Keyboard Shortcuts',
                    'Available keyboard commands for the app',
                  ),
                  const SizedBox(height: 16),

                  _buildShortcutsSection(),

                  const SizedBox(height: 40),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: 'Cancel',
                          hint:
                              'Double-tap to cancel changes and return to chat',
                          onPressed: _cancelSettings,
                          isPrimary: false,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildActionButton(
                          label: 'Save Changes',
                          hint: _hasChanges
                              ? 'Double-tap to save changes and return to chat'
                              : 'No changes to save',
                          onPressed: _hasChanges ? _saveSettings : null,
                          isPrimary: true,
                          isEnabled: _hasChanges,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackendSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Focus(
        onFocusChange: (hasFocus) {
          debugPrint('Backend dropdown focus change: $hasFocus');
        },
        child: DropdownButtonFormField<PreferredBackend>(
          value: _selectedBackend,
          dropdownColor: Colors.white,
          isExpanded: true,
          itemHeight: 64, // Set explicit item height to prevent overflow
          style: TextStyle(color: Colors.grey.shade800, fontSize: 16),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(20),
          ),
          items: PreferredBackend.values.map((backend) {
            return DropdownMenuItem(
              value: backend,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: backend == PreferredBackend.cpu
                          ? Colors.blue.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      backend == PreferredBackend.cpu
                          ? Icons.memory_rounded
                          : Icons.developer_board_rounded,
                      color: backend == PreferredBackend.cpu
                          ? Colors.blue.shade600
                          : Colors.green.shade600,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          backend.name.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          backend == PreferredBackend.cpu
                              ? 'General processing'
                              : 'Accelerated processing',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                            height: 1.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: _onBackendChanged,
          // Custom semantics for the dropdown
          hint: Semantics(
            label: 'AI backend selection dropdown',
            hint:
                'Choose between CPU or GPU processing. Currently selected: ${_selectedBackend.name.toUpperCase()}. Press Enter to open dropdown.',
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildShortcutsSection() {
    final shortcuts = [
      ('F1', 'Send with photo', 'Send your message with camera photo'),
      ('F2', 'Toggle voice input', 'Start or stop voice recording'),
      ('F3', 'New chat', 'Clear conversation and start fresh'),
      ('F4', 'Find exit', 'Quick action for navigation assistance'),
      ('F5', 'Describe room', 'Quick action to describe surroundings'),
      ('F6', 'Read text', 'Quick action to read visible text'),
      ('F7', 'Tell me what you see', 'Quick action for scene description'),
      ('F8', 'Toggle settings', 'Open or close this settings page'),
      ('F9', 'Send text only', 'Send your message without photo'),
      ('F10', 'Toggle messages', 'Show or hide conversation history'),
      ('Enter', 'Activate button', 'Activate the currently focused element'),
      if (_isIOS)
        (
          'Ctrl+Opt+Space',
          'VoiceOver activate',
          'VoiceOver double-tap gesture',
        ),
      if (!_isIOS)
        ('Enter/Space', 'TalkBack activate', 'TalkBack double-tap gesture'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Semantics(
        label: 'Keyboard shortcuts reference',
        hint: 'List of ${shortcuts.length} available keyboard shortcuts',
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: shortcuts.length,
          separatorBuilder: (context, index) => const Divider(height: 20),
          itemBuilder: (context, index) {
            final shortcut = shortcuts[index];
            return _buildShortcutRow(shortcut.$1, shortcut.$2, shortcut.$3);
          },
        ),
      ),
    );
  }

  Widget _buildShortcutRow(String key, String action, String description) {
    return Semantics(
      label: 'Shortcut: $key - $action',
      hint: description,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String hint,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isEnabled = true,
  }) {
    // If disabled, return non-interactive button
    if (!isEnabled || onPressed == null) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // Enabled button with semantic wrapper
    return SemanticMaterialButton(
      label: label,
      hint: hint,
      onPressed: onPressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
                )
              : null,
          color: isPrimary ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary ? Colors.transparent : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isPrimary ? Colors.white : Colors.grey.shade700,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
