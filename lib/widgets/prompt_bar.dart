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

    return Semantics(
      container: true,
      label: 'Message input area',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Message input field',
                    textField: true,
                    child: TextField(
                      controller: _ctrl,
                      enabled: !disabled,
                      decoration: const InputDecoration(
                        hintText: 'Type your message here...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: _sendWithPhoto,
                    ),
                  ),
                ),
                Semantics(
                  label: widget.listening
                      ? 'Stop voice input'
                      : 'Start voice input',
                  button: true,
                  enabled: !disabled && widget.speechEnabled,
                  child: IconButton(
                    icon: Icon(widget.listening ? Icons.mic : Icons.mic_none),
                    tooltip: widget.speechEnabled
                        ? (widget.listening
                              ? 'Stop dictation'
                              : 'Start dictation')
                        : 'Dictation unavailable',
                    onPressed: disabled || !widget.speechEnabled
                        ? null
                        : widget.onToggleListening,
                    color: widget.listening ? Colors.red : null,
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'Send text message only',
                  button: true,
                  enabled: !disabled,
                  child: ElevatedButton(
                    onPressed: disabled
                        ? null
                        : () => _sendTextOnly(_ctrl.text),
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'Send message with photo',
                  button: true,
                  enabled: !disabled,
                  child: ElevatedButton(
                    onPressed: disabled
                        ? null
                        : () => _sendWithPhoto(_ctrl.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
