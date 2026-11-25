namespace Agent.Core.Session;

/// <summary>
/// A connected, message-oriented duplex link (one frame = one message body,
/// length prefix already handled). Wi-Fi and Bluetooth servers implement this.
/// </summary>
public interface IFramedTransport
{
    /// <summary>Next frame body, or null when the peer closed the link.</summary>
    Task<byte[]?> ReceiveFrameAsync(CancellationToken cancellationToken);

    Task SendFrameAsync(byte[] frame, CancellationToken cancellationToken);

    /// <summary>Closes the link. Must be idempotent and must not throw.</summary>
    void Close();
}

/// <summary>Finds and stores the shared secrets of Paired_Hosts by fingerprint.</summary>
public interface IPairedSecretStore
{
    byte[]? TryGetSecret(ReadOnlySpan<byte> fingerprint);
    void SaveSecret(byte[] sharedSecret);
}

public sealed class InMemoryPairedSecretStore : IPairedSecretStore
{
    private readonly Dictionary<string, byte[]> _items = new();

    public byte[]? TryGetSecret(ReadOnlySpan<byte> fingerprint)
    {
        lock (_items) return _items.TryGetValue(Convert.ToHexString(fingerprint), out var s) ? s : null;
    }

    public void SaveSecret(byte[] sharedSecret)
    {
        var key = Convert.ToHexString(Pairing.SecretFingerprint.Compute(sharedSecret));
        lock (_items) _items[key] = (byte[])sharedSecret.Clone();
    }
}
