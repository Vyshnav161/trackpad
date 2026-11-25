using Agent.Core.Protocol;
using Agent.Core.Session;

namespace Agent.Core.Bluetooth;

/// <summary>
/// <see cref="IFramedTransport"/> over any duplex <see cref="Stream"/> (an RFCOMM
/// socket stream). Uses the same 4-byte big-endian length prefix as the Wi-Fi
/// path (<see cref="Framing"/>), so both transports carry identical messages
/// (Requirement 10.7).
/// </summary>
public sealed class StreamFramedTransport : IFramedTransport
{
    private readonly Stream _stream;
    private readonly FrameDecoder _decoder = new();
    private readonly Queue<byte[]> _pending = new();
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly byte[] _readBuffer = new byte[4096];
    private int _closed;

    public StreamFramedTransport(Stream stream) => _stream = stream;

    public async Task<byte[]?> ReceiveFrameAsync(CancellationToken cancellationToken)
    {
        while (true)
        {
            if (_pending.Count > 0) return _pending.Dequeue();
            if (Volatile.Read(ref _closed) != 0) return null;
            int n;
            try
            {
                n = await _stream.ReadAsync(_readBuffer.AsMemory(), cancellationToken);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception)
            {
                Close();
                return null;
            }
            if (n <= 0)
            {
                Close();
                return null;
            }
            foreach (var f in _decoder.Add(_readBuffer.AsSpan(0, n))) _pending.Enqueue(f);
            if (_decoder.Corrupted && _pending.Count == 0)
            {
                Close();
                return null;
            }
        }
    }

    public async Task SendFrameAsync(byte[] frame, CancellationToken cancellationToken)
    {
        var encoded = Framing.EncodeFrame(frame);
        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            await _stream.WriteAsync(encoded, cancellationToken);
            await _stream.FlushAsync(cancellationToken);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public void Close()
    {
        if (Interlocked.Exchange(ref _closed, 1) != 0) return;
        try { _stream.Dispose(); } catch { /* idempotent, never throws */ }
    }
}
