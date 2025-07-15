// widgets/prompt_bar.dart
import 'package:flutter/material.dart';

/// Prompt bar widget for text input and actions
class PromptBar extends StatefulWidget {
  final Future<void> Function(String) onPromptWithPhoto;
  final Future<void> Function(String) onPromptTextOnly;
  final bool disabled;
  final bool speechEnabled;
  final bool listening;
  final VoidCallback onToggleListening;

  const PromptBar({
    Key? key,
    required this.onPromptWithPhoto,
    required this.onPromptTextOnly,
    this.disabled = false,
    required this.speechEnabled,
    required this.listening,
    required this.onToggleListening,
  }) : super(key: key);

  @override
  State<PromptBar> createState() => PromptBarState();
}

class PromptBarState extends State<PromptBar> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  Future<void> _sendWithPhoto(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;
    _ctrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      await widget.onPromptWithPhoto(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendTextOnly(String prompt) async {
    if (widget.disabled || _sending) return;
    final txt = prompt.trim();
    if (txt.isEmpty) return;
    _ctrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      await widget.onPromptTextOnly(txt);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void clear() => _ctrl.clear();

  void updateText(String text) {
    setState(() {
      _ctrl.text = text;
      _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _ctrl.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled || _sending;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text input field
          Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: disabled ? Colors.grey.shade300 : Colors.blue.shade300,
                width: 2,
              ),
            ),
            child: TextField(
              controller: _ctrl,
              enabled: !disabled,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Type your message here...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  _sendWithPhoto(text);
                }
              },
            ),
          ),

          const SizedBox(height: 12),

          // Send buttons row
          Row(
            children: [
              // Send text only button
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: disabled
                        ? null
                        : () => _sendTextOnly(_ctrl.text),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.send, size: 24),
                    label: const Text(
                      'Send Text Only',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Send with photo button
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: disabled
                        ? null
                        : () => _sendWithPhoto(_ctrl.text),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.camera_alt, size: 24),
                    label: const Text(
                      'Send with Photo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
