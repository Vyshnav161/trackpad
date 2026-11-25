/// Input event types shared by the Android_App and (by wire parity) the
/// Desktop_Agent. Plain Dart: no Flutter dependencies.
library;

enum MouseButton { left, right }

enum ButtonState { down, up }

enum Modifier { shift, control, alt, platform }

/// Special (non-character) keys. Wire ids are the enum indices, so do not
/// reorder existing values.
enum SpecialKey {
  backspace,
  enter,
  tab,
  escape,
  delete,
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
}

sealed class InputEvent {
  const InputEvent();
}

final class PointerMove extends InputEvent {
  final double dx;
  final double dy;
  const PointerMove(this.dx, this.dy);

  @override
  bool operator ==(Object other) =>
      other is PointerMove && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash('PointerMove', dx, dy);
}

final class ButtonAction extends InputEvent {
  final MouseButton button;
  final ButtonState action;
  const ButtonAction(this.button, this.action);

  @override
  bool operator ==(Object other) =>
      other is ButtonAction && other.button == button && other.action == action;

  @override
  int get hashCode => Object.hash('ButtonAction', button, action);
}

final class ClickAction extends InputEvent {
  final MouseButton button;

  /// 1 (single) or 2 (double).
  final int clickCount;
  const ClickAction(this.button, this.clickCount);

  @override
  bool operator ==(Object other) =>
      other is ClickAction &&
      other.button == button &&
      other.clickCount == clickCount;

  @override
  int get hashCode => Object.hash('ClickAction', button, clickCount);
}

final class ScrollEvent extends InputEvent {
  final double dx;
  final double dy;
  const ScrollEvent(this.dx, this.dy);

  @override
  bool operator ==(Object other) =>
      other is ScrollEvent && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash('ScrollEvent', dx, dy);
}

final class ZoomEvent extends InputEvent {
  final double magnitude;
  const ZoomEvent(this.magnitude);

  @override
  bool operator ==(Object other) =>
      other is ZoomEvent && other.magnitude == magnitude;

  @override
  int get hashCode => Object.hash('ZoomEvent', magnitude);
}

final class AppSwitchEvent extends InputEvent {
  const AppSwitchEvent();

  @override
  bool operator ==(Object other) => other is AppSwitchEvent;

  @override
  int get hashCode => 'AppSwitchEvent'.hashCode;
}

/// Either a Unicode character or a special key.
sealed class KeyId {
  const KeyId();
}

final class CharKey extends KeyId {
  /// Unicode scalar value (0..0x10FFFF, excluding surrogates).
  final int codepoint;
  const CharKey(this.codepoint);

  @override
  bool operator ==(Object other) =>
      other is CharKey && other.codepoint == codepoint;

  @override
  int get hashCode => Object.hash('CharKey', codepoint);
}

final class SpecialKeyId extends KeyId {
  final SpecialKey key;
  const SpecialKeyId(this.key);

  @override
  bool operator ==(Object other) => other is SpecialKeyId && other.key == key;

  @override
  int get hashCode => Object.hash('SpecialKeyId', key);
}

final class KeyAction extends InputEvent {
  final KeyId key;
  final Set<Modifier> modifiers;
  final ButtonState action;
  const KeyAction(this.key, this.modifiers, this.action);

  @override
  bool operator ==(Object other) =>
      other is KeyAction &&
      other.key == key &&
      other.action == action &&
      other.modifiers.length == modifiers.length &&
      other.modifiers.containsAll(modifiers);

  @override
  int get hashCode =>
      Object.hash('KeyAction', key, action, Object.hashAllUnordered(modifiers));
}

final class Heartbeat extends InputEvent {
  const Heartbeat();

  @override
  bool operator ==(Object other) => other is Heartbeat;

  @override
  int get hashCode => 'Heartbeat'.hashCode;
}

sealed class CodecError {
  const CodecError();
}

final class Malformed extends CodecError {
  final String reason;
  const Malformed(this.reason);

  @override
  bool operator ==(Object other) =>
      other is Malformed && other.reason == reason;

  @override
  int get hashCode => Object.hash('Malformed', reason);

  @override
  String toString() => 'Malformed($reason)';
}

final class VersionMismatch extends CodecError {
  final int found;
  final int supported;
  const VersionMismatch(this.found, this.supported);

  @override
  bool operator ==(Object other) =>
      other is VersionMismatch &&
      other.found == found &&
      other.supported == supported;

  @override
  int get hashCode => Object.hash('VersionMismatch', found, supported);

  @override
  String toString() => 'VersionMismatch(found: $found, supported: $supported)';
}

/// Result of [ProtocolCodec.decode].
sealed class DecodeResult {
  const DecodeResult();
}

final class DecodeOk extends DecodeResult {
  final InputEvent event;
  const DecodeOk(this.event);
}

final class DecodeErr extends DecodeResult {
  final CodecError error;
  const DecodeErr(this.error);
}
