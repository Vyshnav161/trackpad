/// Binary wire format: `[version u8][type u8][payload]`, big-endian.
///
/// Type tags and payloads:
/// - 0x01 PointerMove:  f32 dx, f32 dy
/// - 0x02 ButtonAction: u8 button (0 left, 1 right), u8 state (0 down, 1 up)
/// - 0x03 ClickAction:  u8 button, u8 clickCount (1 or 2)
/// - 0x04 ScrollEvent:  f32 dx, f32 dy
/// - 0x05 ZoomEvent:    f32 magnitude
/// - 0x06 AppSwitch:    (empty)
/// - 0x07 KeyAction:    u8 state, u8 modifier bitmask (shift=1, control=2,
///                      alt=4, platform=8), u8 kind (0 char, 1 special),
///                      then u32 codepoint (char) or u8 special-key id
/// - 0x08 Heartbeat:    (empty)
library;

import 'dart:typed_data';

import 'input_event.dart';

class ProtocolCodec {
  const ProtocolCodec._();

  static const int version = 1;
  static const Set<int> supportedVersions = {version};

  static const int _tPointerMove = 0x01;
  static const int _tButton = 0x02;
  static const int _tClick = 0x03;
  static const int _tScroll = 0x04;
  static const int _tZoom = 0x05;
  static const int _tAppSwitch = 0x06;
  static const int _tKey = 0x07;
  static const int _tHeartbeat = 0x08;

  /// Serializes [event]. Throws [ArgumentError] only for events that violate
  /// the type's invariants (non-finite floats, bad click count or codepoint).
  static Uint8List encode(InputEvent event) {
    final b = BytesBuilder();
    b.addByte(version);
    switch (event) {
      case PointerMove(:final dx, :final dy):
        b.addByte(_tPointerMove);
        _f32(b, dx);
        _f32(b, dy);
      case ButtonAction(:final button, :final action):
        b.addByte(_tButton);
        b.addByte(button.index);
        b.addByte(action.index);
      case ClickAction(:final button, :final clickCount):
        if (clickCount != 1 && clickCount != 2) {
          throw ArgumentError.value(clickCount, 'clickCount', 'must be 1 or 2');
        }
        b.addByte(_tClick);
        b.addByte(button.index);
        b.addByte(clickCount);
      case ScrollEvent(:final dx, :final dy):
        b.addByte(_tScroll);
        _f32(b, dx);
        _f32(b, dy);
      case ZoomEvent(:final magnitude):
        b.addByte(_tZoom);
        _f32(b, magnitude);
      case AppSwitchEvent():
        b.addByte(_tAppSwitch);
      case KeyAction(:final key, :final modifiers, :final action):
        b.addByte(_tKey);
        b.addByte(action.index);
        var mask = 0;
        for (final m in modifiers) {
          mask |= 1 << m.index;
        }
        b.addByte(mask);
        switch (key) {
          case CharKey(:final codepoint):
            if (!_validCodepoint(codepoint)) {
              throw ArgumentError.value(codepoint, 'codepoint', 'invalid');
            }
            b.addByte(0);
            final d = ByteData(4)..setUint32(0, codepoint, Endian.big);
            b.add(d.buffer.asUint8List());
          case SpecialKeyId(:final key):
            b.addByte(1);
            b.addByte(key.index);
        }
      case Heartbeat():
        b.addByte(_tHeartbeat);
    }
    return b.toBytes();
  }

  /// Parses [bytes]. Never throws.
  static DecodeResult decode(List<int> bytes) {
    try {
      return _decode(bytes);
    } catch (e) {
      return DecodeErr(Malformed('unexpected decode failure: $e'));
    }
  }

  static DecodeResult _decode(List<int> raw) {
    if (raw.length < 2) {
      return DecodeErr(Malformed('message too short: ${raw.length} bytes'));
    }
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final v = bytes[0];
    if (!supportedVersions.contains(v)) {
      return DecodeErr(VersionMismatch(v, version));
    }
    final type = bytes[1];
    final data = ByteData.sublistView(bytes);
    final len = bytes.length - 2; // payload length

    DecodeResult bad(String why) => DecodeErr(Malformed(why));

    DecodeResult? expectLen(int n, String name) =>
        len == n ? null : bad('$name payload must be $n bytes, got $len');

    switch (type) {
      case _tPointerMove:
        final e = expectLen(8, 'PointerMove');
        if (e != null) return e;
        final dx = data.getFloat32(2, Endian.big);
        final dy = data.getFloat32(6, Endian.big);
        if (!dx.isFinite || !dy.isFinite) return bad('non-finite float');
        return DecodeOk(PointerMove(dx, dy));
      case _tButton:
        final e = expectLen(2, 'ButtonAction');
        if (e != null) return e;
        final btn = _enum(MouseButton.values, bytes[2]);
        final st = _enum(ButtonState.values, bytes[3]);
        if (btn == null) return bad('unknown button ${bytes[2]}');
        if (st == null) return bad('unknown button state ${bytes[3]}');
        return DecodeOk(ButtonAction(btn, st));
      case _tClick:
        final e = expectLen(2, 'ClickAction');
        if (e != null) return e;
        final btn = _enum(MouseButton.values, bytes[2]);
        if (btn == null) return bad('unknown button ${bytes[2]}');
        final count = bytes[3];
        if (count != 1 && count != 2) return bad('invalid click count $count');
        return DecodeOk(ClickAction(btn, count));
      case _tScroll:
        final e = expectLen(8, 'ScrollEvent');
        if (e != null) return e;
        final dx = data.getFloat32(2, Endian.big);
        final dy = data.getFloat32(6, Endian.big);
        if (!dx.isFinite || !dy.isFinite) return bad('non-finite float');
        return DecodeOk(ScrollEvent(dx, dy));
      case _tZoom:
        final e = expectLen(4, 'ZoomEvent');
        if (e != null) return e;
        final m = data.getFloat32(2, Endian.big);
        if (!m.isFinite) return bad('non-finite float');
        return DecodeOk(ZoomEvent(m));
      case _tAppSwitch:
        final e = expectLen(0, 'AppSwitchEvent');
        if (e != null) return e;
        return const DecodeOk(AppSwitchEvent());
      case _tKey:
        return _decodeKey(bytes, data, len);
      case _tHeartbeat:
        final e = expectLen(0, 'Heartbeat');
        if (e != null) return e;
        return const DecodeOk(Heartbeat());
      default:
        return bad('unknown event type 0x${type.toRadixString(16)}');
    }
  }

  static DecodeResult _decodeKey(Uint8List bytes, ByteData data, int len) {
    DecodeResult bad(String why) => DecodeErr(Malformed(why));
    if (len < 4) return bad('KeyAction payload too short: $len bytes');
    final st = _enum(ButtonState.values, bytes[2]);
    if (st == null) return bad('unknown key state ${bytes[2]}');
    final mask = bytes[3];
    if (mask & ~0x0F != 0) return bad('unknown modifier bits $mask');
    final mods = <Modifier>{
      for (final m in Modifier.values)
        if (mask & (1 << m.index) != 0) m,
    };
    final kind = bytes[4];
    switch (kind) {
      case 0:
        if (len != 7) return bad('char KeyAction payload must be 7 bytes');
        final cp = data.getUint32(5, Endian.big);
        if (!_validCodepoint(cp)) return bad('invalid codepoint $cp');
        return DecodeOk(KeyAction(CharKey(cp), mods, st));
      case 1:
        if (len != 4) return bad('special KeyAction payload must be 4 bytes');
        final sk = _enum(SpecialKey.values, bytes[5]);
        if (sk == null) return bad('unknown special key ${bytes[5]}');
        return DecodeOk(KeyAction(SpecialKeyId(sk), mods, st));
      default:
        return bad('unknown key kind $kind');
    }
  }

  /// Human-readable text for logging.
  static String prettyPrint(InputEvent event) {
    switch (event) {
      case PointerMove(:final dx, :final dy):
        return 'PointerMove(dx: $dx, dy: $dy)';
      case ButtonAction(:final button, :final action):
        return 'ButtonAction(button: ${button.name}, action: ${action.name})';
      case ClickAction(:final button, :final clickCount):
        return 'ClickAction(button: ${button.name}, clickCount: $clickCount)';
      case ScrollEvent(:final dx, :final dy):
        return 'ScrollEvent(dx: $dx, dy: $dy)';
      case ZoomEvent(:final magnitude):
        return 'ZoomEvent(magnitude: $magnitude)';
      case AppSwitchEvent():
        return 'AppSwitchEvent()';
      case KeyAction(:final key, :final modifiers, :final action):
        final k = switch (key) {
          CharKey(:final codepoint) =>
            'char U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')}',
          SpecialKeyId(:final key) => 'special ${key.name}',
        };
        final mods = (modifiers.map((m) => m.name).toList()..sort()).join('+');
        return 'KeyAction(key: $k, modifiers: [$mods], action: ${action.name})';
      case Heartbeat():
        return 'Heartbeat()';
    }
  }

  /// Human-readable text for a decode failure.
  static String prettyPrintError(CodecError error) => switch (error) {
    Malformed(:final reason) => 'Malformed message: $reason',
    VersionMismatch(:final found, :final supported) =>
      'Version mismatch: found $found, supported $supported',
  };

  static bool _validCodepoint(int cp) =>
      cp >= 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF);

  static T? _enum<T>(List<T> values, int i) =>
      i >= 0 && i < values.length ? values[i] : null;

  static void _f32(BytesBuilder b, double v) {
    if (!v.isFinite) throw ArgumentError.value(v, 'value', 'must be finite');
    final d = ByteData(4)..setFloat32(0, v, Endian.big);
    b.add(d.buffer.asUint8List());
  }
}
