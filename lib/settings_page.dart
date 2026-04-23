// lib/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'app_settings.dart';
import 'chat_page/services/gemma_service.dart';
import 'chat_page/widgets/semantic_material_button.dart';
import 'chat_page/widgets/semantic_button_registry.dart';
import 'prompt_settings_page.dart';

/// Settings page for configuring AI system context, controller layout, and processing backend
/// Optimized for accessibility with comprehensive keyboard navigation and screen reader support
class SettingsPage extends StatefulWidget {
  final String systemContext;
  final MlcBackend backend;

  const SettingsPage({
    super.key,
    required this.systemContext,
    required this.backend,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late MlcBackend _selectedBackend;
  bool _hasChanges = false;
  late bool _hapticsEnabled;
  late bool _earconsEnabled;
  late bool _highContrastEnabled;
  late bool _toolCallingEnabled;
  late AppFontSize _fontSize;

  late final bool _initialHapticsEnabled;
  late final bool _initialEarconsEnabled;
  late final bool _initialHighContrastEnabled;
  late final bool _initialToolCallingEnabled;
  late final AppFontSize _initialFontSize;

  /// Platform detection for accessibility-specific features
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Color get _backgroundColor => _highContrastEnabled
      ? Colors.black
      : Theme.of(context).colorScheme.surface;
  Color get _textColor => _highContrastEnabled ? Colors.white : Colors.black87;
  Color get _secondaryTextColor =>
      _highContrastEnabled ? Colors.white70 : Colors.grey.shade600;
  Color get _containerColor =>
      _highContrastEnabled ? Colors.grey.shade900 : Colors.white;
  Color get _borderColor =>
      _highContrastEnabled ? Colors.white24 : Colors.grey.shade300;

  /// Page-wide focus scope for comprehensive keyboard navigation
  final FocusScopeNode _pageScope = FocusScopeNode(
    debugLabel: 'SettingsPageScope',
  );

  @override
  void initState() {
    super.initState();
    _selectedBackend = widget.backend;
    final settings = AppSettings.instance;
    _hapticsEnabled = settings.hapticsEnabled;
    _earconsEnabled = settings.earconsEnabled;
    _highContrastEnabled = settings.highContrastEnabled;
    _toolCallingEnabled = settings.enableFunctionCalling;
    _fontSize = settings.fontSize;

    _initialHapticsEnabled = _hapticsEnabled;
    _initialEarconsEnabled = _earconsEnabled;
    _initialHighContrastEnabled = _highContrastEnabled;
    _initialToolCallingEnabled = _toolCallingEnabled;
    _initialFontSize = _fontSize;
  }

  @override
  void dispose() {
    _pageScope.dispose();
    SemanticButtonRegistry.clear(); // Clean up accessibility state
    super.dispose();
  }

  /// Track changes to enable/disable save button and show unsaved changes indicator
  void _refreshHasChanges() {
    setState(() {
      _hasChanges =
          _selectedBackend != widget.backend ||
          _hapticsEnabled != _initialHapticsEnabled ||
          _earconsEnabled != _initialEarconsEnabled ||
          _highContrastEnabled != _initialHighContrastEnabled ||
          _toolCallingEnabled != _initialToolCallingEnabled ||
          _fontSize != _initialFontSize;
    });
  }

  /// Handle backend selection with change tracking
  void _onBackendChanged(MlcBackend? backend) {
    if (backend != null) {
      setState(() => _selectedBackend = backend);
      _refreshHasChanges();
    }
  }

  /// Save changes and return to chat page
  Future<void> _save() async {
    await AppSettings.instance.update(
      hapticsEnabled: _hapticsEnabled,
      earconsEnabled: _earconsEnabled,
      highContrastEnabled: _highContrastEnabled,
      enableFunctionCalling: _toolCallingEnabled,
      fontSize: _fontSize,
    );
    if (!mounted) return;

    Navigator.of(context).pop({'backend': _selectedBackend});
  }

  /// Cancel changes and return to chat page
  void _cancel() => Navigator.of(context).pop();

  void _openControllerSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ControllerSettingsPage()),
    );
  }

  void _openPromptSettings() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (context) => const PromptSettingsPage()),
        )
        .then((_) {
          setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = _fontSize == AppFontSize.large ? 1.6 : 1.0;

    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.tab): const NextFocusIntent(),
      LogicalKeySet(LogicalKeyboardKey.tab, LogicalKeyboardKey.shift):
          const PreviousFocusIntent(),

      LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
    };

    if (_isIOS) {
      shortcuts[LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.alt,
            LogicalKeyboardKey.space,
          )] =
          const ActivateIntent();
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                SemanticButtonRegistry.invokeCurrentSemanticTap();
                return null;
              },
            ),
          },
          child: FocusScope(
            node: _pageScope,
            child: Scaffold(
              backgroundColor: _backgroundColor,
              appBar: AppBar(
                elevation: 0,
                backgroundColor: _backgroundColor,
                iconTheme: IconThemeData(color: _textColor),
                systemOverlayStyle: _highContrastEnabled
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                leading: Focus(
                  autofocus: true,
                  child: SemanticMaterialButton(
                    label: 'Back',
                    hint: 'Double-tap to return to chat',
                    onPressed: _cancel,
                    child: Icon(
                      Icons.arrow_back_ios_rounded,
                      color: _highContrastEnabled ? Colors.white : Colors.blue,
                      semanticLabel: 'Back to chat',
                    ),
                  ),
                ),
                title: Semantics(
                  header: true,
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                actions: [
                  if (_hasChanges)
                    SemanticMaterialButton(
                      label: 'Save',
                      hint: 'Double-tap to save changes and return to chat',
                      onPressed: _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: _highContrastEnabled
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF4CAF50),
                                    Color(0xFF388E3C),
                                  ],
                                ),
                          color: _highContrastEnabled ? Colors.white : null,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Save',
                          style: TextStyle(
                            color: _highContrastEnabled
                                ? Colors.black
                                : Colors.white,
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
                      _wrapFocus(_buildAccessibilityAdvice()),
                      const SizedBox(height: 32),

                      _wrapFocus(
                        _buildSectionHeader(
                          'Prompts',
                          'Customize AI behavior and quick actions',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _wrapFocus(_buildPromptSettingsButton()),

                      const SizedBox(height: 40),

                      _wrapFocus(
                        _buildSectionHeader(
                          'Feedback',
                          'Haptics and earcons for controller use',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _wrapFocus(
                        _buildToggleTile(
                          title: 'Haptic feedback',
                          subtitle: 'Vibrate the phone for actions',
                          value: _hapticsEnabled,
                          onChanged: (value) {
                            setState(() => _hapticsEnabled = value);
                            _refreshHasChanges();
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _wrapFocus(
                        _buildToggleTile(
                          title: 'Earcons',
                          subtitle: 'Play short UI sounds',
                          value: _earconsEnabled,
                          onChanged: (value) {
                            setState(() => _earconsEnabled = value);
                            _refreshHasChanges();
                          },
                        ),
                      ),

                      const SizedBox(height: 40),

                      _wrapFocus(
                        _buildSectionHeader(
                          'Display',
                          'High contrast and text size',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _wrapFocus(
                        _buildToggleTile(
                          title: 'High contrast theme',
                          subtitle: 'Improve readability in bright conditions',
                          value: _highContrastEnabled,
                          onChanged: (value) {
                            setState(() => _highContrastEnabled = value);
                            _refreshHasChanges();
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _wrapFocus(_buildFontSizeToggle()),

                      const SizedBox(height: 40),

                      _wrapFocus(
                        _buildSectionHeader('Other', 'Additional settings'),
                      ),
                      const SizedBox(height: 16),
                      // [수정] 옵션 이름 및 설명 변경
                      _wrapFocus(_buildFunctionCallingToggle()),
                      const SizedBox(height: 12),
                      _wrapFocus(_buildControllerSettingsButton()),

                      const SizedBox(height: 40),

                      _wrapFocus(_buildBackendSelector()),
                      const SizedBox(height: 40),

                      _buildActionRow(),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapFocus(Widget child) => Focus(child: child);

  Widget _buildAccessibilityAdvice() {
    final platform = _isIOS
        ? 'iOS VoiceOver'
        : _isAndroid
        ? 'Android TalkBack'
        : 'your screen reader';
    return Semantics(
      label:
          'Controller tip: For best experience, temporarily turn off $platform when using a controller.',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: _highContrastEnabled
              ? LinearGradient(colors: [Colors.grey.shade900, Colors.black])
              : LinearGradient(
                  colors: [Colors.blue.shade50, Colors.indigo.shade50],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _highContrastEnabled ? Colors.white : Colors.blue.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: _highContrastEnabled
                  ? Colors.yellow
                  : Colors.blue.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'For best experience, temporarily turn off $platform when using a controller.',
                style: TextStyle(
                  color: _highContrastEnabled
                      ? Colors.white
                      : Colors.blue.shade700,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String desc) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            color: _textColor,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(desc, style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
    ],
  );

  BoxDecoration _boxDecoration() => BoxDecoration(
    color: _containerColor,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _borderColor),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );

  Widget _buildPromptSettingsButton() {
    return SemanticMaterialButton(
      label: 'Manage Prompts',
      hint: 'Double-tap to customize system prompts and quick actions',
      onPressed: _openPromptSettings,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: _highContrastEnabled ? Colors.white : Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage Prompts',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edit system context & commands',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: _secondaryTextColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControllerSettingsButton() {
    return SemanticMaterialButton(
      label: 'Controller Settings',
      hint: 'Double-tap to view controller layout and setup instructions',
      onPressed: _openControllerSettings,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            Icon(
              Icons.gamepad_rounded,
              color: _highContrastEnabled ? Colors.white : Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controller Settings',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View layout and setup info',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: _secondaryTextColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final content = SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: _textColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: _secondaryTextColor, fontSize: 13),
      ),
      value: value,
      activeThumbColor: _highContrastEnabled ? Colors.white : null,
      activeTrackColor: _highContrastEnabled ? Colors.grey : null,
      onChanged: onChanged,
    );

    return Container(decoration: _boxDecoration(), child: content);
  }

  Widget _buildFunctionCallingToggle() {
    return _buildToggleTile(
      title: 'Enable tool calling',
      subtitle: 'Use built-in tools for requests such as lunch and weather.',
      value: _toolCallingEnabled,
      onChanged: (value) {
        setState(() => _toolCallingEnabled = value);
        _refreshHasChanges();
      },
    );
  }

  Widget _buildFontSizeToggle() {
    final isLarge = _fontSize == AppFontSize.large;

    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(20),
      child: isLarge
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Text size',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Normal or large',
                  style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildFontSizeButtons(),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Text size',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Normal or large',
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _buildFontSizeButtons(),
              ],
            ),
    );
  }

  Widget _buildFontSizeButtons() => Container(
    decoration: BoxDecoration(
      color: _highContrastEnabled ? Colors.grey.shade800 : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: _borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: _fontSize == AppFontSize.large
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.start,
      children: [
        _fontSizeOption(AppFontSize.normal, 'Normal'),
        _fontSizeOption(AppFontSize.large, 'Large'),
      ],
    ),
  );

  Widget _fontSizeOption(AppFontSize size, String label) {
    final selected = _fontSize == size;
    final selectedColor = _highContrastEnabled
        ? Colors.white
        : Colors.blue.shade600;

    return SemanticMaterialButton(
      label: '$label text size',
      hint:
          'Double-tap to select ${label.toLowerCase()} size${selected ? ', currently selected' : ''}',
      onPressed: () {
        setState(() => _fontSize = size);
        _refreshHasChanges();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (_highContrastEnabled ? Colors.black : Colors.white)
                : _textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBackendSelector() {
    final isLarge = _fontSize == AppFontSize.large;

    final content = [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Processing Backend',
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'Choose processing method',
            style: TextStyle(color: _secondaryTextColor, fontSize: 13),
          ),
        ],
      ),
      const SizedBox(width: 16),
      _buildBackendToggle(),
    ];

    return Semantics(
      label: 'Processing backend selector',
      child: Container(
        decoration: _boxDecoration(),
        padding: const EdgeInsets.all(20),
        child: isLarge
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content[0],
                  const SizedBox(height: 16),
                  _buildBackendToggle(),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content[0]),
                  content[2],
                ],
              ),
      ),
    );
  }

  Widget _buildBackendToggle() => Container(
    decoration: BoxDecoration(
      color: _highContrastEnabled ? Colors.grey.shade800 : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: _borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: _fontSize == AppFontSize.large
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.start,
      children: [
        _backendOption(MlcBackend.cpu, 'CPU', Icons.memory_rounded),
        _backendOption(MlcBackend.gpu, 'GPU', Icons.developer_board_rounded),
      ],
    ),
  );

  Widget _backendOption(MlcBackend b, String lbl, IconData icn) {
    final selected = _selectedBackend == b;
    final selectedColor = _highContrastEnabled
        ? Colors.white
        : Colors.blue.shade600;

    return SemanticMaterialButton(
      label: '$lbl backend',
      hint:
          'Double-tap to select ${lbl.toLowerCase()} processing${selected ? ', currently selected' : ''}',
      onPressed: () => _onBackendChanged(b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icn,
              size: 18,
              color: selected
                  ? (_highContrastEnabled ? Colors.black : Colors.white)
                  : _secondaryTextColor,
            ),
            const SizedBox(width: 8),
            Text(
              lbl,
              style: TextStyle(
                color: selected
                    ? (_highContrastEnabled ? Colors.black : Colors.white)
                    : _textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() => Row(
    children: [
      Expanded(
        child: _actionBtn(
          'Cancel',
          'Double-tap to cancel changes and return to chat',
          _cancel,
          primary: false,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: _actionBtn(
          'Save Changes',
          _hasChanges
              ? 'Double-tap to save changes and return to chat'
              : 'No changes to save',
          _hasChanges ? _save : null,
          primary: true,
          enabled: _hasChanges,
        ),
      ),
    ],
  );

  Widget _actionBtn(
    String lbl,
    String hint,
    VoidCallback? onTap, {
    required bool primary,
    bool enabled = true,
  }) {
    if (!enabled || onTap == null) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: _highContrastEnabled
              ? Colors.grey.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Center(
          child: Text(
            lbl,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    Color? bgColor;
    Color txtColor;
    if (_highContrastEnabled) {
      bgColor = primary ? Colors.white : Colors.grey.shade900;
      txtColor = primary ? Colors.black : Colors.white;
    } else {
      bgColor = primary ? null : Colors.white;
      txtColor = primary ? Colors.white : Colors.grey.shade700;
    }

    return SemanticMaterialButton(
      label: lbl,
      hint: hint,
      onPressed: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: (_highContrastEnabled || !primary)
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
                ),
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary ? Colors.transparent : _borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: primary
                  ? Colors.green.withValues(alpha: .2)
                  : Colors.black.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            lbl,
            style: TextStyle(color: txtColor, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class ControllerSettingsPage extends StatelessWidget {
  const ControllerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Controller Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Controller Layout',
              'Button assignments for your controller',
            ),
            const SizedBox(height: 20),
            _buildShortcutsTable(),
            const SizedBox(height: 40),
            _buildSectionHeader(
              'Controller Setup',
              'If a sighted person is available, they can follow this picture to help set up your controller. You don\'t have to, but it can make things easier.',
            ),
            const SizedBox(height: 16),
            _buildControllerSetup(),
            const SizedBox(height: 40),
            _buildBackButton(context),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String desc) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
    ],
  );

  Widget _buildShortcutsTable() {
    const data = [
      ('Right Bumper (R1)', 'F1', 'Send with photo'),
      ('Large Right Trigger (R2)', 'F2', 'Toggle voice input'),
      ('Plus button (Center Top-Right)', 'F3', 'New chat'),
      ('X top round button', 'F4', 'What is this?'),
      ('A right round button', 'F5', 'Describe room'),
      ('Y left round button', 'F6', 'Read text'),
      ('B bottom round button', 'F7', 'Tell me what you see'),
      ('Heart button (Center Bottom-Right)', 'F8', 'Toggle settings'),
      ('Small Left Bumper (L1)', 'F9', 'Send text only'),
      ('Star button (Center Bottom-Left)', 'F10', 'Toggle show messages'),
      ('Minus button (Center Top-Left)', 'Enter', 'Activate button'),
      ('User Mapped (e.g. L2)', 'F11', 'Connection Test (Vibration)'),
      ('User Mapped (Reserved)', 'F12', 'Wake App (Background)'),
    ];

    Widget row(String a, String b, String c, {bool header = false}) {
      final styleH = TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Colors.grey.shade900,
      );
      final styleA = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade800,
      );
      final styleB = const TextStyle(
        fontSize: 14,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      );
      final styleC = TextStyle(fontSize: 14, color: Colors.grey.shade700);

      Widget cell(String t, TextStyle s, {bool key = false}) => Expanded(
        flex: key ? 1 : 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(t, style: s),
        ),
      );

      final r = Row(
        children: [
          cell(a, header ? styleH : styleA),
          cell(b, header ? styleH : styleB, key: true),
          cell(c, header ? styleH : styleC),
        ],
      );

      return header
          ? Container(
              color: Colors.grey.shade300.withValues(alpha: .4),
              child: r,
            )
          : Focus(
              child: Semantics(
                label: '$a, key $b, action: $c',
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: r,
                ),
              ),
            );
    }

    return Column(
      children: [
        row('Button', 'Key', 'Action', header: true),
        for (final s in data) row(s.$1, s.$2, s.$3),
      ],
    );
  }

  Widget _buildControllerSetup() {
    BoxDecoration boxDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'Image showing the physical controller layout. A sighted helper can refer to it during setup.',
          image: true,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: boxDecoration(),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/controller_setup.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.gamepad,
                        size: 50,
                        color: Colors.grey,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Photo of controller layout',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return SemanticMaterialButton(
      label: 'Back',
      hint: 'Double-tap to return to settings page',
      onPressed: () => Navigator.of(context).pop(),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'Back',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
