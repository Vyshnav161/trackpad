/// Length-prefix framing shared by the Wi-Fi (TCP) and Bluetooth (RFCOMM)
/// transports: `[length u32 big-endian][message bytes]`.
library;

import 'dart:typed_data';

/// Maximum accepted frame body size. Input events are tiny; this only guards
/// against corrupt length prefixes.
const int maxFrameSize = 64 * 1024;

/// Wraps [message] with a 4-byte big-endian length prefix.
Uint8List encodeFrame(List<int> message) {
  if (message.length > maxFrameSize) {
    throw ArgumentError.value(message.length, 'message.length', 'too large');
  }
  final out = Uint8List(4 + message.length);
  ByteData.sublistView(out).setUint32(0, message.length, Endian.big);
  out.setRange(4, out.length, message);
  return out;
}

/// Incrementally reassembles frames from arbitrary stream chunks.
/// Never throws: an oversized length prefix sets [corrupted] and discards
/// buffered data; the transport should then close the connection.
class FrameDecoder {
  final BytesBuilder _buf = BytesBuilder(copy: false);
  bool _corrupted = false;

  bool get corrupted => _corrupted;

  /// Adds [chunk] and returns every complete frame body now available.
  List<Uint8List> add(List<int> chunk) {
    if (_corrupted) return const [];
    _buf.add(chunk);
    final data = _buf.takeBytes();
    final frames = <Uint8List>[];
    var offset = 0;
    while (data.length - offset >= 4) {
      final n = ByteData.sublistView(
        data,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      if (n > maxFrameSize) {
        _corrupted = true;
        return frames;
      }
      if (data.length - offset - 4 < n) break;
      frames.add(Uint8List.sublistView(data, offset + 4, offset + 4 + n));
      offset += 4 + n;
    }
    if (offset < data.length) {
      _buf.add(Uint8List.sublistView(data, offset));
    }
    return frames;
  }
}
