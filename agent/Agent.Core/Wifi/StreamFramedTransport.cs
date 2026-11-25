using Agent.Core.Protocol;
using Agent.Core.Session;
namespace Agent.Core.Wifi;

/// <summary>IFramedTransport over a byte stream (TLS) using length-prefix framing.</summary>
public sealed class StreamFramedTransport : IFramedTransport
{
    private readonly Stream _stream;
    private readonly FrameDecoder _decoder = new();
    private readonly Queue<byte[]> _pending = new();
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private readonly byte[] _buf = new byte[8192];
    private int _closed;

    public StreamFramedTransport(Stream stream) => _stream = stream;

    public async Task<byte[]?> ReceiveFrameAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (_pending.Count == 0)
            {
                var n = await _stream.ReadAsync(_buf, cancellationToken);
                if (n == 0) return null;
                foreach (var f in _decoder.Add(_buf.AsSpan(0, n))) _pending.Enqueue(f);
                if (_decoder.Corrupted) { Close(); return null; }
            }
            return _pending.Dequeue();
        }
        catch (Exception ex) when (ex is IOException or ObjectDisposedException or System.Security.Authentication.AuthenticationException)
        {
            return null;
        }
    }

    public async Task SendFrameAsync(byte[] frame, CancellationToken cancellationToken)
    {
        var data = Framing.EncodeFrame(frame);
        await _sendLock.WaitAsync(cancellationToken);
        try
        {
            await _stream.WriteAsync(data, cancellationToken);
            await _stream.FlushAsync(cancellationToken);
        }
        finally { _sendLock.Release(); }
    }

    public void Close()
    {
        if (Interlocked.Exchange(ref _closed, 1) == 1) return;
        try { _stream.Dispose(); } catch { }
    }
}
