using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Agent.Core.Security;

/// <summary>Which side of the Connection this channel instance is.</summary>
public enum ChannelRole { Client, Server }

/// <summary>
/// Authenticated encryption of framed Input_Events. Port of
/// lib/transport/secure_channel.dart (Requirement 4.7).
/// Message: [counter u64 BE][ciphertext][tag 16]; AAD = counter bytes;
/// nonce = 00 00 00 00 || counter.
/// </summary>
public sealed class SecureChannel
{
    public const int NonceLength = 16;
    public const int KeyLength = 32;
    public const int TagLength = 16;
    public const int CounterLength = 8;
    public const int MinMessageLength = CounterLength + TagLength;
    public const string InfoClientToServer = "trackpad/v1/c2s";
    public const string InfoServerToClient = "trackpad/v1/s2c";

    private readonly byte[] _sendKey;
    private readonly byte[] _receiveKey;
    private ulong _sendCounter;
    private bool _hasReceived;
    private ulong _lastReceived;

    private SecureChannel(byte[] sendKey, byte[] receiveKey)
    {
        _sendKey = sendKey;
        _receiveKey = receiveKey;
    }

    public static SecureChannel Create(
        byte[] sharedSecret, byte[] clientNonce, byte[] serverNonce, ChannelRole role)
    {
        if (sharedSecret.Length < 16)
            throw new ArgumentException("sharedSecret must be at least 16 bytes");
        if (clientNonce.Length != NonceLength || serverNonce.Length != NonceLength)
            throw new ArgumentException($"nonces must be {NonceLength} bytes");

        var salt = new byte[NonceLength * 2];
        clientNonce.CopyTo(salt, 0);
        serverNonce.CopyTo(salt, NonceLength);
        var c2s = HKDF.DeriveKey(HashAlgorithmName.SHA256, sharedSecret, KeyLength, salt,
            Encoding.ASCII.GetBytes(InfoClientToServer));
        var s2c = HKDF.DeriveKey(HashAlgorithmName.SHA256, sharedSecret, KeyLength, salt,
            Encoding.ASCII.GetBytes(InfoServerToClient));
        return role == ChannelRole.Client
            ? new SecureChannel(c2s, s2c)
            : new SecureChannel(s2c, c2s);
    }

    private static byte[] NonceFor(ReadOnlySpan<byte> counterBytes)
    {
        var n = new byte[12];
        counterBytes.CopyTo(n.AsSpan(4));
        return n;
    }

    /// <summary>Encrypts one encoded Input_Event; returns the message to be framed.</summary>
    public byte[] Encrypt(ReadOnlySpan<byte> encodedEvent)
    {
        var message = new byte[CounterLength + encodedEvent.Length + TagLength];
        BinaryPrimitives.WriteUInt64BigEndian(message, _sendCounter);
        _sendCounter++;
        var counterBytes = message.AsSpan(0, CounterLength);
        if (AesGcm.IsSupported)
        {
            using var aes = new AesGcm(_sendKey);
            aes.Encrypt(NonceFor(counterBytes), encodedEvent,
                message.AsSpan(CounterLength, encodedEvent.Length),
                message.AsSpan(CounterLength + encodedEvent.Length, TagLength),
                counterBytes);
        }
        else
        {
            // net7.0 on macOS has no AesGcm; BouncyCastle keeps the dev build working.
            var gcm = Fallback(true, _sendKey, NonceFor(counterBytes), counterBytes);
            var output = new byte[gcm.GetOutputSize(encodedEvent.Length)];
            var n = gcm.ProcessBytes(encodedEvent.ToArray(), 0, encodedEvent.Length, output, 0);
            gcm.DoFinal(output, n);
            output.CopyTo(message.AsSpan(CounterLength));
        }
        return message;
    }

    private static Org.BouncyCastle.Crypto.Modes.GcmBlockCipher Fallback(
        bool encrypt, byte[] key, byte[] nonce, ReadOnlySpan<byte> aad)
    {
        var gcm = new Org.BouncyCastle.Crypto.Modes.GcmBlockCipher(
            new Org.BouncyCastle.Crypto.Engines.AesEngine());
        gcm.Init(encrypt, new Org.BouncyCastle.Crypto.Parameters.AeadParameters(
            new Org.BouncyCastle.Crypto.Parameters.KeyParameter(key), TagLength * 8, nonce, aad.ToArray()));
        return gcm;
    }

    /// <summary>
    /// Decrypts a peer message. Returns null if malformed, failing authentication,
    /// or replaying a counter. Never throws; failures do not advance state.
    /// </summary>
    public byte[]? Decrypt(ReadOnlySpan<byte> message)
    {
        if (message.Length < MinMessageLength) return null;
        try
        {
            var counterBytes = message.Slice(0, CounterLength);
            var counter = BinaryPrimitives.ReadUInt64BigEndian(counterBytes);
            if (_hasReceived && counter <= _lastReceived) return null;
            var cipherLen = message.Length - CounterLength - TagLength;
            byte[] plain;
            if (AesGcm.IsSupported)
            {
                plain = new byte[cipherLen];
                using var aes = new AesGcm(_receiveKey);
                aes.Decrypt(NonceFor(counterBytes), message.Slice(CounterLength, cipherLen),
                    message.Slice(message.Length - TagLength), plain, counterBytes);
            }
            else
            {
                var gcm = Fallback(false, _receiveKey, NonceFor(counterBytes), counterBytes);
                var input = message.Slice(CounterLength).ToArray();
                var output = new byte[gcm.GetOutputSize(input.Length)];
                var n = gcm.ProcessBytes(input, 0, input.Length, output, 0);
                gcm.DoFinal(output, n);
                plain = output;
            }
            _hasReceived = true;
            _lastReceived = counter;
            return plain;
        }
        catch
        {
            return null;
        }
    }
}
