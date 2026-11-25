/// Keyboard panel: opens the Android on-screen keyboard through a hidden
/// text field, offers modifier toggles and an F1-F12 row.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keyboard/keyboard_recognizer.dart';
import '../protocol/input_event.dart';

class KeyboardPanel extends StatefulWidget {
  final KeyboardRecognizer recognizer;

  /// OS-specific label for the platform modifier (e.g. "Command", "Windows").
  final String platformKeyLabel;

  /// Receives key actions to be sent to the host.
  final void Function(List<KeyAction> actions) onKeyActions;

  const KeyboardPanel({
    super.key,
    required this.recognizer,
    required this.platformKeyLabel,
    required this.onKeyActions,
  });

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  /// Sentinel kept in the field so a backspace on an "empty" field is visible
  /// as a text change.
  static const String _sentinel = '\u200B';

  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _resetField();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _resetField() {
    _controller.value = const TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
  }

  void _emit(List<KeyAction> actions) {
    if (actions.isNotEmpty) widget.onKeyActions(actions);
    if (mounted) setState(() {}); // modifiers may have been consumed
  }

  void _onChanged(String value) {
    if (!value.startsWith(_sentinel)) {
      // Sentinel deleted: backspace.
      final typed = value;
      _resetField();
      if (typed.isEmpty) {
        _emit(widget.recognizer.pressSpecial(SpecialKey.backspace));
      } else {
        _emit(widget.recognizer.typeText(typed.replaceAll(_sentinel, '')));
      }
      return;
    }
    final typed = value.substring(_sentinel.length);
    _resetField();
    if (typed.isEmpty) return;
    final out = <KeyAction>[];
    for (final r in typed.runes) {
      if (r == 0x0A) {
        out.addAll(widget.recognizer.pressSpecial(SpecialKey.enter));
      } else {
        out.addAll(widget.recognizer.typeCodepoint(r));
      }
    }
    _emit(out);
  }

  void _onSubmitted(String _) {
    _emit(widget.recognizer.pressSpecial(SpecialKey.enter));
    _focus.requestFocus(); // keep the keyboard open
  }

  void _openKeyboard() {
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  static const _fKeys = <SpecialKey>[
    SpecialKey.f1,
    SpecialKey.f2,
    SpecialKey.f3,
    SpecialKey.f4,
    SpecialKey.f5,
    SpecialKey.f6,
    SpecialKey.f7,
    SpecialKey.f8,
    SpecialKey.f9,
    SpecialKey.f10,
    SpecialKey.f11,
    SpecialKey.f12,
  ];

  Widget _modifierToggle(Modifier m, String label) {
    return FilterChip(
      label: Text(label),
      selected: widget.recognizer.isActive(m),
      onSelected: (_) {
        widget.recognizer.toggleModifier(m);
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hidden input capture field.
        SizedBox(
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              enableInteractiveSelection: false,
              maxLines: null,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                key: const Key('keyboard_open'),
                icon: const Icon(Icons.keyboard),
                tooltip: 'Show keyboard',
                onPressed: _openKeyboard,
              ),
              _modifierToggle(Modifier.shift, 'Shift'),
              _modifierToggle(Modifier.control, 'Control'),
              _modifierToggle(Modifier.alt, 'Alt'),
              _modifierToggle(Modifier.platform, widget.platformKeyLabel),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (var i = 0; i < _fKeys.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OutlinedButton(
                    onPressed: () =>
                        _emit(widget.recognizer.pressSpecial(_fKeys[i])),
                    child: Text('F${i + 1}'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
