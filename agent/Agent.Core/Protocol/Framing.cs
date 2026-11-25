using System.Buffers.Binary;

namespace Agent.Core.Protocol;

/// <summary>
/// Length-prefix framing shared by the Wi-Fi and Bluetooth transports:
/// <c>[length u32 big-endian][message bytes]</c>. Mirrors lib/protocol/framing.dart.
/// </summary>
public static class Framing
{
    /// <summary>Maximum accepted frame body size; guards against corrupt prefixes.</summary>
    public const int MaxFrameSize = 64 * 1024;

    /// <summary>Wraps <paramref name="message"/> with a 4-byte big-endian length prefix.</summary>
    public static byte[] EncodeFrame(ReadOnlySpan<byte> message)
    {
        if (message.Length > MaxFrameSize)
            throw new ArgumentException("message too large", nameof(message));
        var out_ = new byte[4 + message.Length];
        BinaryPrimitives.WriteUInt32BigEndian(out_, (uint)message.Length);
        message.CopyTo(out_.AsSpan(4));
        return out_;
    }
}

/// <summary>
/// Incrementally reassembles frames from arbitrary stream chunks. Never throws:
/// an oversized length prefix sets <see cref="Corrupted"/> and discards buffered
/// data; the transport should then close the connection.
/// </summary>
public sealed class FrameDecoder
{
    private readonly List<byte> _buf = new();

    public bool Corrupted { get; private set; }

    /// <summary>Adds <paramref name="chunk"/> and returns every complete frame body now available.</summary>
    public List<byte[]> Add(ReadOnlySpan<byte> chunk)
    {
        var frames = new List<byte[]>();
        if (Corrupted) return frames;
        _buf.AddRange(chunk.ToArray());
        var data = _buf.ToArray();
        _buf.Clear();
        var offset = 0;
        while (data.Length - offset >= 4)
        {
            var n = BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(offset, 4));
            if (n > Framing.MaxFrameSize)
            {
                Corrupted = true;
                return frames;
            }
            if (data.Length - offset - 4 < n) break;
            frames.Add(data.AsSpan(offset + 4, (int)n).ToArray());
            offset += 4 + (int)n;
        }
        if (offset < data.Length) _buf.AddRange(data.AsSpan(offset).ToArray());
        return frames;
    }
}
