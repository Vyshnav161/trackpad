/// Maps typed characters and special keys to [KeyAction]s, tracking the
/// on-screen modifier toggles. Plain Dart: no Flutter dependencies.
library;

import '../protocol/input_event.dart';

class KeyboardRecognizer {
  final Set<Modifier> _active = <Modifier>{};

  /// Currently toggled modifiers (read-only snapshot).
  Set<Modifier> get activeModifiers => Set.unmodifiable(_active);

  bool isActive(Modifier m) => _active.contains(m);

  /// Flips the toggle state of [m]. Returns the new state (true = on).
  bool toggleModifier(Modifier m) {
    if (!_active.remove(m)) {
      _active.add(m);
      return true;
    }
    return false;
  }

  /// Clears all toggled modifiers.
  void clearModifiers() => _active.clear();

  /// Key down + key up for a typed [codepoint], carrying the active
  /// modifiers. Returns an empty list for invalid scalar values.
  /// Active modifiers are consumed (cleared) by this call.
  List<KeyAction> typeCodepoint(int codepoint) {
    if (!_isScalarValue(codepoint)) return const [];
    return _press(CharKey(codepoint));
  }

  /// Key actions for every character in [text] (by Unicode scalar). Active
  /// modifiers apply to the first character only; invalid (lone surrogate)
  /// units are skipped.
  List<KeyAction> typeText(String text) {
    final out = <KeyAction>[];
    for (final r in text.runes) {
      out.addAll(typeCodepoint(r));
    }
    return out;
  }

  /// Key down + key up for a special key (Backspace, Enter, F1-F12, ...).
  /// Active modifiers are consumed by this call.
  List<KeyAction> pressSpecial(SpecialKey key) => _press(SpecialKeyId(key));

  List<KeyAction> _press(KeyId key) {
    final mods = Set<Modifier>.unmodifiable(Set<Modifier>.of(_active));
    _active.clear();
    return [
      KeyAction(key, mods, ButtonState.down),
      KeyAction(key, mods, ButtonState.up),
    ];
  }

  static bool _isScalarValue(int c) =>
      c >= 0 && c <= 0x10FFFF && !(c >= 0xD800 && c <= 0xDFFF);
}
