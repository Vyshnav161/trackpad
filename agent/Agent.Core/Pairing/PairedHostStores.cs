namespace Agent.Core.Pairing;

public sealed class InMemoryPairedHostStore : IPairedHostStore
{
    private readonly HashSet<string> _items = new();
    private readonly object _lock = new();

    public bool Contains(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock) return _items.Contains(key);
    }

    public void Add(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock) _items.Add(key);
    }

    public void Remove(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock) _items.Remove(key);
    }
}

/// <summary>Stores one hex fingerprint per line in a text file.</summary>
public sealed class FilePairedHostStore : IPairedHostStore
{
    private readonly string _path;
    private readonly HashSet<string> _items = new();
    private readonly object _lock = new();

    public FilePairedHostStore(string path)
    {
        _path = path;
        if (File.Exists(path))
        {
            foreach (var line in File.ReadAllLines(path))
            {
                var t = line.Trim();
                if (t.Length > 0) _items.Add(t.ToUpperInvariant());
            }
        }
    }

    public bool Contains(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock) return _items.Contains(key);
    }

    public void Add(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock)
        {
            if (_items.Add(key)) Save();
        }
    }

    public void Remove(ReadOnlySpan<byte> fingerprint)
    {
        var key = Convert.ToHexString(fingerprint);
        lock (_lock)
        {
            if (_items.Remove(key)) Save();
        }
    }

    private void Save()
    {
        var dir = Path.GetDirectoryName(Path.GetFullPath(_path));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = _path + ".tmp";
        File.WriteAllLines(tmp, _items);
        File.Move(tmp, _path, overwrite: true);
    }
}
