using System.Security.Cryptography;

namespace Agent.Core.Pairing;

/// <summary>Time source, injectable for tests.</summary>
public interface IClock
{
    DateTimeOffset UtcNow { get; }
}

public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}

/// <summary>Source of random integers, injectable for tests.</summary>
public interface IRandomSource
{
    /// <summary>Returns a uniform integer in [0, exclusiveMax).</summary>
    int NextInt(int exclusiveMax);
}

/// <summary>CSPRNG-backed random source.</summary>
public sealed class CryptoRandomSource : IRandomSource
{
    public int NextInt(int exclusiveMax) => RandomNumberGenerator.GetInt32(exclusiveMax);
}

/// <summary>Persistent set of paired hosts keyed by secret fingerprint.</summary>
public interface IPairedHostStore
{
    bool Contains(ReadOnlySpan<byte> fingerprint);
    void Add(ReadOnlySpan<byte> fingerprint);
    void Remove(ReadOnlySpan<byte> fingerprint);
}

public static class SecretFingerprint
{
    public const int Length = 8;

    /// <summary>First 8 bytes of SHA-256(sharedSecret), matching the Dart handshake.</summary>
    public static byte[] Compute(ReadOnlySpan<byte> sharedSecret)
        => SHA256.HashData(sharedSecret)[..Length];
}
