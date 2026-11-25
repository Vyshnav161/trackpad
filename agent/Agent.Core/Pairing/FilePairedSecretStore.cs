using Agent.Core.Session;

namespace Agent.Core.Pairing;

/// <summary>
/// One persistent store serving both <see cref="IPairedSecretStore"/> (used by
/// ConnectionSession to derive keys) and <see cref="IPairedHostStore"/> (used by
/// PairingAuthManager to recognise paired phones). Secrets are keyed by
/// fingerprint and written to a file readable only by the current user.
/// File format: one "FINGERPRINTHEX:SECRETHEX" line per host.
/// </summary>
public sealed class FilePairedSecretStore : IPairedSecretStore, IPairedHostStore
{
    private readonly string _path;
    private readonly Dictionary<string, byte[]> _items = new();
    private readonly object _lock = new();

    public FilePairedSecretStore(string path)
    {
        _path = path;
        if (!File.Exists(path)) return;
        foreach (var line in File.ReadAllLines(path))
        {
            var parts = line.Trim().Split(':');
            if (parts.Length != 2) continue;
            try { _items[parts[0].ToUpperInvariant()] = Convert.FromHexString(parts[1]); }
            catch (FormatException) { }
        }
    }

    public byte[]? TryGetSecret(ReadOnlySpan<byte> fingerprint)
    {
        lock (_lock)
            return _items.TryGetValue(Convert.ToHexString(fingerprint), out var s) ? (byte[])s.Clone() : null;
    }

    public void SaveSecret(byte[] sharedSecret)
    {
        var key = Convert.ToHexString(SecretFingerprint.Compute(sharedSecret));
        lock (_lock)
        {
            _items[key] = (byte[])sharedSecret.Clone();
            Save();
        }
    }

    public bool Contains(ReadOnlySpan<byte> fingerprint)
    {
        lock (_lock) return _items.ContainsKey(Convert.ToHexString(fingerprint));
    }

    /// <summary>
    /// No-op: the fingerprint alone carries no secret. <see cref="SaveSecret"/>
    /// (called by ConnectionSession on acceptance) is what records the host.
    /// </summary>
    public void Add(ReadOnlySpan<byte> fingerprint) { }

    public void Remove(ReadOnlySpan<byte> fingerprint)
    {
        lock (_lock)
        {
            if (_items.Remove(Convert.ToHexString(fingerprint))) Save();
        }
    }

    private void Save()
    {
        var dir = Path.GetDirectoryName(Path.GetFullPath(_path));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = _path + ".tmp";
        var options = new FileStreamOptions { Mode = FileMode.Create, Access = FileAccess.Write };
        if (!OperatingSystem.IsWindows())
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        using (var w = new StreamWriter(tmp, options))
        {
            foreach (var (fp, secret) in _items) w.WriteLine($"{fp}:{Convert.ToHexString(secret)}");
        }
        File.Move(tmp, _path, overwrite: true);
    }
}
