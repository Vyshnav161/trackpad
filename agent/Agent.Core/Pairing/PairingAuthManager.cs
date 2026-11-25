using System.Security.Cryptography;

namespace Agent.Core.Pairing;

/// <summary>Mirrors the Dart PairingStatus (accepted, incorrectCode, lockedOut, rejected).</summary>
public enum PairingStatus : byte { Accepted = 0, IncorrectCode = 1, LockedOut = 2, Rejected = 3 }

/// <param name="Status">Typed outcome; failures are never thrown.</param>
/// <param name="FailedAttempts">Consecutive incorrect codes so far.</param>
/// <param name="LockoutSeconds">Remaining lockout, 0 unless LockedOut.</param>
public readonly record struct PairingResult(PairingStatus Status, int FailedAttempts, int LockoutSeconds);

/// <summary>
/// Generates Pairing_Codes, counts consecutive failures, enforces the lockout
/// and tracks authenticated state per Connection (Requirements 4.1-4.5).
/// </summary>
public sealed class PairingAuthManager
{
    public const int CodeLength = 6;
    public const int MaxFailedAttempts = 3;
    public static readonly TimeSpan LockoutDuration = TimeSpan.FromSeconds(60);

    private readonly IPairedHostStore _store;
    private readonly IClock _clock;
    private readonly IRandomSource _random;
    private readonly object _lock = new();
    private readonly HashSet<Guid> _authenticated = new();

    private string? _code;
    private int _failedAttempts;
    private DateTimeOffset? _lockedUntil;

    public PairingAuthManager(IPairedHostStore store, IClock? clock = null, IRandomSource? random = null)
    {
        _store = store;
        _clock = clock ?? new SystemClock();
        _random = random ?? new CryptoRandomSource();
    }

    /// <summary>The currently displayed code, or null if none is active.</summary>
    public string? CurrentCode { get { lock (_lock) return _code; } }

    public bool IsLockedOut { get { lock (_lock) return RemainingLockout() > 0; } }

    /// <summary>Remaining lockout in whole seconds (rounded up); 0 when not locked out.</summary>
    public int RemainingLockoutSeconds { get { lock (_lock) return RemainingLockout(); } }

    /// <summary>
    /// Generates and returns a fresh 6-digit code, resetting the failure count.
    /// Returns null while locked out.
    /// </summary>
    public string? GenerateCode()
    {
        lock (_lock)
        {
            if (RemainingLockout() > 0) return null;
            return NewCode();
        }
    }

    /// <summary>
    /// True when the fingerprint belongs to a Paired_Host, so the challenge is
    /// skipped (Requirement 4.5). Pairing_Code is not issued in that case.
    /// </summary>
    public bool IsPairedHost(ReadOnlySpan<byte> fingerprint) => _store.Contains(fingerprint);

    /// <summary>
    /// Connection start. Paired hosts become authenticated immediately and
    /// return true; otherwise the Connection is unauthenticated and a code
    /// is ensured to exist (unless locked out).
    /// </summary>
    public bool BeginConnection(Guid connectionId, ReadOnlySpan<byte> fingerprint)
    {
        if (_store.Contains(fingerprint))
        {
            lock (_lock) _authenticated.Add(connectionId);
            return true;
        }
        lock (_lock)
        {
            _authenticated.Remove(connectionId);
            if (_code == null && RemainingLockout() == 0) NewCode();
        }
        return false;
    }

    /// <summary>
    /// Verifies an entered code (constant-time compare). On success the
    /// Connection is authenticated, the code is consumed and, if
    /// <paramref name="newSharedSecret"/> is given, the host is stored.
    /// </summary>
    public PairingResult SubmitCode(Guid connectionId, string enteredCode, ReadOnlySpan<byte> newSharedSecret = default)
    {
        lock (_lock)
        {
            var remaining = RemainingLockout();
            if (remaining > 0) return new(PairingStatus.LockedOut, _failedAttempts, remaining);
            if (_code == null) return new(PairingStatus.Rejected, _failedAttempts, 0);

            var match = CryptographicOperations.FixedTimeEquals(
                System.Text.Encoding.ASCII.GetBytes(_code),
                System.Text.Encoding.ASCII.GetBytes(enteredCode ?? string.Empty));
            return match ? Accept(connectionId, newSharedSecret) : RecordFailure(connectionId);
        }
    }

    /// <summary>
    /// For transports that verify the code cryptographically (AES-GCM tag with
    /// the code-derived key): report whether the attempt decrypted correctly.
    /// </summary>
    public PairingResult ReportAttempt(Guid connectionId, bool correct, ReadOnlySpan<byte> newSharedSecret = default)
    {
        lock (_lock)
        {
            var remaining = RemainingLockout();
            if (remaining > 0) return new(PairingStatus.LockedOut, _failedAttempts, remaining);
            if (_code == null) return new(PairingStatus.Rejected, _failedAttempts, 0);
            return correct ? Accept(connectionId, newSharedSecret) : RecordFailure(connectionId);
        }
    }

    public bool IsAuthenticated(Guid connectionId)
    {
        lock (_lock) return _authenticated.Contains(connectionId);
    }

    /// <summary>Marks a Connection authenticated after key-possession proof of a paired host.</summary>
    public void MarkAuthenticated(Guid connectionId)
    {
        lock (_lock) _authenticated.Add(connectionId);
    }

    public void EndConnection(Guid connectionId)
    {
        lock (_lock) _authenticated.Remove(connectionId);
    }

    private PairingResult Accept(Guid connectionId, ReadOnlySpan<byte> newSharedSecret)
    {
        if (!newSharedSecret.IsEmpty)
            _store.Add(SecretFingerprint.Compute(newSharedSecret));
        _authenticated.Add(connectionId);
        _code = null;
        _failedAttempts = 0;
        return new(PairingStatus.Accepted, 0, 0);
    }

    private PairingResult RecordFailure(Guid connectionId)
    {
        _authenticated.Remove(connectionId);
        _failedAttempts++;
        if (_failedAttempts >= MaxFailedAttempts)
        {
            _code = null; // invalidate
            _lockedUntil = _clock.UtcNow + LockoutDuration;
            return new(PairingStatus.LockedOut, _failedAttempts, (int)LockoutDuration.TotalSeconds);
        }
        return new(PairingStatus.IncorrectCode, _failedAttempts, 0);
    }

    /// <summary>Remaining lockout in whole seconds (rounded up); clears expired lockout.</summary>
    private int RemainingLockout()
    {
        if (_lockedUntil is not { } until) return 0;
        var left = until - _clock.UtcNow;
        if (left <= TimeSpan.Zero)
        {
            _lockedUntil = null;
            _failedAttempts = 0;
            return 0;
        }
        return (int)Math.Ceiling(left.TotalSeconds);
    }

    private string NewCode()
    {
        _code = _random.NextInt(1_000_000).ToString("D6");
        _failedAttempts = 0;
        return _code;
    }
}
