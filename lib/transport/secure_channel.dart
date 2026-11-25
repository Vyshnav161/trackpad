/// Secure channel: authenticated encryption of framed Input_Events.
///
/// Satisfies Requirements 4.7 and 10.7. The same layout is used over the
/// Wi-Fi and Bluetooth transports. The C# agent (task 10.6) MUST match this
/// specification exactly.
///
/// ## Inputs
/// * `sharedSecret`: the pairing shared secret (bytes, >= 16 bytes).
/// * `clientNonce`, `serverNonce`: 16 random bytes each. The Android_App
///   (client) generates `clientNonce`, the Desktop_Agent (server) generates
///   `serverNonce`. They are exchanged in the clear during connection setup
///   (before any encrypted message) so every Connection gets fresh keys.
///
/// ## Key derivation (per Connection, per direction)
/// HKDF (RFC 5869) with HMAC-SHA-256, output length 32 bytes:
///   * IKM  = sharedSecret
///   * salt = clientNonce || serverNonce            (32 bytes)
///   * info = ASCII "trackpad/v1/c2s"  for the client->server key
///            ASCII "trackpad/v1/s2c"  for the server->client key
/// (No trailing NUL, no length prefix.) Two independent keys are derived so
/// each direction has its own nonce counter without collision.
///
/// ## Cipher
/// AES-256-GCM, 12-byte nonce, 16-byte tag.
///
/// ## Nonce
/// 12 bytes = 0x00 0x00 0x00 0x00 || counter (u64, big-endian).
/// The counter is per direction, starts at 0 and increments by 1 for every
/// message sent. A counter MUST NOT repeat under one key.
///
/// ## Message layout (the payload that goes inside the length-prefix frame)
///   [counter: u64 big-endian, 8 bytes]
///   [ciphertext: N bytes]        N = length of the encoded InputEvent
///   [GCM tag: 16 bytes]
/// Total = 8 + N + 16 bytes.
///   * Plaintext  = the Protocol_Codec bytes `[version u8][type u8][payload]`.
///   * AAD        = the 8 counter bytes (as transmitted).
///   * The length-prefix framing is applied outside, over this whole message.
///
/// ## Receiver rules
/// * Reject (return null, never throw) messages shorter than 24 bytes,
///   with a failing tag, or whose counter is <= the last accepted counter
///   (replay/reorder protection; both transports are ordered streams).
/// * Only update the last accepted counter after the tag verifies.
/// * A failed message MUST NOT advance state; the caller decides whether to
///   close the Connection.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Which side of the Connection this channel instance is.
enum ChannelRole { client, server }

class SecureChannel {
  static const int nonceLength = 16;
  static const int keyLength = 32;
  static const int tagLength = 16;
  static const int counterLength = 8;
  static const int minMessageLength = counterLength + tagLength;
  static const String infoClientToServer = 'trackpad/v1/c2s';
  static const String infoServerToClient = 'trackpad/v1/s2c';

  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  final AesGcm _cipher = AesGcm.with256bits();

  int _sendCounter = 0;
  int _lastReceived = -1;

  SecureChannel._(this._sendKey, this._receiveKey);

  /// Derives the per-Connection keys and returns a channel for [role].
  static Future<SecureChannel> create({
    required List<int> sharedSecret,
    required List<int> clientNonce,
    required List<int> serverNonce,
    required ChannelRole role,
  }) async {
    if (sharedSecret.length < 16) {
      throw ArgumentError('sharedSecret must be at least 16 bytes');
    }
    if (clientNonce.length != nonceLength ||
        serverNonce.length != nonceLength) {
      throw ArgumentError('nonces must be $nonceLength bytes');
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);
    final salt = [...clientNonce, ...serverNonce];
    final secret = SecretKey(List<int>.of(sharedSecret));
    final c2s = await hkdf.deriveKey(
      secretKey: secret,
      nonce: salt,
      info: infoClientToServer.codeUnits,
    );
    final s2c = await hkdf.deriveKey(
      secretKey: secret,
      nonce: salt,
      info: infoServerToClient.codeUnits,
    );
    return role == ChannelRole.client
        ? SecureChannel._(c2s, s2c)
        : SecureChannel._(s2c, c2s);
  }

  static Uint8List _counterBytes(int counter) {
    final b = ByteData(counterLength)..setUint64(0, counter, Endian.big);
    return b.buffer.asUint8List();
  }

  static Uint8List _nonceFor(Uint8List counterBytes) {
    final n = Uint8List(12);
    n.setRange(4, 12, counterBytes);
    return n;
  }

  /// Encrypts one encoded Input_Event; returns the message to be framed.
  Future<Uint8List> encrypt(List<int> encodedEvent) async {
    final counterBytes = _counterBytes(_sendCounter);
    _sendCounter++;
    final box = await _cipher.encrypt(
      encodedEvent,
      secretKey: _sendKey,
      nonce: _nonceFor(counterBytes),
      aad: counterBytes,
    );
    return Uint8List.fromList([
      ...counterBytes,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Decrypts a message produced by the peer's [encrypt]. Returns the encoded
  /// Input_Event bytes, or null if the message is malformed, fails
  /// authentication, or replays an earlier counter. Never throws.
  Future<Uint8List?> decrypt(List<int> message) async {
    if (message.length < minMessageLength) return null;
    try {
      final bytes = Uint8List.fromList(message);
      final counterBytes = Uint8List.sublistView(bytes, 0, counterLength);
      final counter = ByteData.sublistView(
        counterBytes,
      ).getUint64(0, Endian.big);
      if (counter < 0 || counter <= _lastReceived) return null;
      final cipherText = Uint8List.sublistView(
        bytes,
        counterLength,
        bytes.length - tagLength,
      );
      final tag = Uint8List.sublistView(bytes, bytes.length - tagLength);
      final plain = await _cipher.decrypt(
        SecretBox(cipherText, nonce: _nonceFor(counterBytes), mac: Mac(tag)),
        secretKey: _receiveKey,
        aad: counterBytes,
      );
      _lastReceived = counter;
      return Uint8List.fromList(plain);
    } catch (_) {
      return null;
    }
  }
}
