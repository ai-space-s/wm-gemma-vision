// lib/prompt_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_settings.dart';
import 'chat_page/config/system_prompts.dart';
import 'chat_page/widgets/semantic_material_button.dart';

class PromptSettingsPage extends StatefulWidget {
  const PromptSettingsPage({super.key});

  @override
  State<PromptSettingsPage> createState() => _PromptSettingsPageState();
}

class _PromptSettingsPageState extends State<PromptSettingsPage> {
  late TextEditingController _systemCtxController;
  late TextEditingController _roomController;
  late TextEditingController _seeController;
  late TextEditingController _whatController;
  late TextEditingController _readController;

  bool _hasChanges = false;
  final AppSettings _settings = AppSettings.instance;

  // Colors for High Contrast Support
  bool get _hc => _settings.highContrastEnabled;
  Color get _bg => _hc ? Colors.black : Theme.of(context).colorScheme.surface;
  Color get _text => _hc ? Colors.white : Colors.black87;
  Color get _secText => _hc ? Colors.white70 : Colors.grey.shade600;
  Color get _cardBg => _hc ? Colors.grey.shade900 : Colors.white;
  Color get _border => _hc ? Colors.white24 : Colors.grey.shade300;

  @override
  void initState() {
    super.initState();
    _systemCtxController = TextEditingController(text: _settings.systemContext);
    _roomController = TextEditingController(text: _settings.promptDescribeRoom);
    _seeController = TextEditingController(text: _settings.promptWhatYouSee);
    _whatController = TextEditingController(text: _settings.promptWhatIsThis);
    _readController = TextEditingController(text: _settings.promptReadText);

    _systemCtxController.addListener(_checkChanges);
    _roomController.addListener(_checkChanges);
    _seeController.addListener(_checkChanges);
    _whatController.addListener(_checkChanges);
    _readController.addListener(_checkChanges);
  }

  void _checkChanges() {
    final changed =
        _systemCtxController.text != _settings.systemContext ||
            _roomController.text != _settings.promptDescribeRoom ||
            _seeController.text != _settings.promptWhatYouSee ||
            _whatController.text != _settings.promptWhatIsThis ||
            _readController.text != _settings.promptReadText;

    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  @override
  void dispose() {
    _systemCtxController.dispose();
    _roomController.dispose();
    _seeController.dispose();
    _whatController.dispose();
    _readController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _settings.updatePrompts(
      systemContext: _systemCtxController.text,
      describeRoom: _roomController.text,
      whatYouSee: _seeController.text,
      whatIsThis: _whatController.text,
      readText: _readController.text,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        iconTheme: IconThemeData(color: _text),
        elevation: 0,
        title: Text('Prompt Settings', style: TextStyle(color: _text)),
        actions: [
          if (_hasChanges)
            SemanticMaterialButton(
              label: 'Save',
              onPressed: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: _hc ? Colors.white : Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Save',
                  style: TextStyle(
                    color: _hc ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildPromptSection(
              title: 'System Context',
              desc: 'Defines the AI persona and behavior.',
              controller: _systemCtxController,
              defaultText: SystemPrompts.defaultSystemContext,
              maxLines: 5,
            ),
            const SizedBox(height: 24),
            _buildPromptSection(
              title: 'Describe Room (F5)',
              desc: 'Prompt for room layout analysis.',
              controller: _roomController,
              defaultText: SystemPrompts.describeRoom,
            ),
            const SizedBox(height: 24),
            _buildPromptSection(
              title: 'What You See (F7)',
              desc: 'Prompt for general scene description.',
              controller: _seeController,
              defaultText: SystemPrompts.tellMeWhatYouSee,
            ),
            const SizedBox(height: 24),
            _buildPromptSection(
              title: 'What Is This (F4)',
              desc: 'Prompt for object identification.',
              controller: _whatController,
              defaultText: SystemPrompts.whatIsThis,
            ),
            const SizedBox(height: 24),
            _buildPromptSection(
              title: 'Read Text (F6)',
              desc: 'Prompt for OCR/Reading text.',
              controller: _readController,
              defaultText: SystemPrompts.readText,
            ),
            // Bottom padding for scroll
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptSection({
    required String title,
    required String desc,
    required TextEditingController controller,
    required String defaultText,
    int maxLines = 2,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(desc, style: TextStyle(color: _secText, fontSize: 13)),
                  ],
                ),
              ),
              SemanticMaterialButton(
                label: 'Reset $title to default',
                onPressed: () {
                  controller.text = defaultText;
                  _checkChanges();
                  // Announce reset
                  HapticFeedback.mediumImpact();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _hc ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Text(
                    'Default',
                    style: TextStyle(
                      color: _text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(color: _text),
            decoration: InputDecoration(
              filled: true,
              fillColor: _hc ? Colors.black : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}