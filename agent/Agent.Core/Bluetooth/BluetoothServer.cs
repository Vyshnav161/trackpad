using Agent.Core.Session;

namespace Agent.Core.Bluetooth;

/// <summary>
/// Bluetooth Transport server + discovery advertiser (Requirements 1.1, 1.2, 3.1, 10.7).
/// Starts the platform listener (which publishes the SDP record), wraps every accepted
/// stream in a <see cref="StreamFramedTransport"/> and hands it to <paramref name="onConnection"/>
/// (typically builds and runs a <see cref="ConnectionSession"/>). Never throws: if Bluetooth
/// is unavailable it logs and <see cref="StartAsync"/> returns false, so Wi-Fi keeps working.
/// </summary>
public sealed class BluetoothServer : IAsyncDisposable
{
    private readonly IBluetoothRfcommListener _listener;
    private readonly BluetoothAdvertisement _advertisement;
    private readonly Func<IFramedTransport, CancellationToken, Task> _onConnection;
    private readonly Action<string> _log;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public BluetoothServer(
        IBluetoothRfcommListener listener,
        BluetoothAdvertisement advertisement,
        Func<IFramedTransport, CancellationToken, Task> onConnection,
        Action<string>? log = null)
    {
        _listener = listener;
        _advertisement = advertisement;
        _onConnection = onConnection;
        _log = log ?? (_ => { });
    }

    public bool IsRunning { get; private set; }

    /// <returns>true if the RFCOMM service is advertised and accepting connections.</returns>
    public async Task<bool> StartAsync(CancellationToken cancellationToken = default)
    {
        if (IsRunning) return true;
        if (!_listener.IsSupported)
        {
            _log($"Bluetooth disabled: {_listener.UnsupportedReason}");
            return false;
        }
        try
        {
            await _listener.StartAsync(_advertisement, cancellationToken);
        }
        catch (Exception ex)
        {
            _log($"Bluetooth disabled: could not start RFCOMM service: {ex.Message}");
            return false;
        }
        _cts = new CancellationTokenSource();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
        IsRunning = true;
        _log($"Bluetooth advertising '{_advertisement.ServiceName}' ({_advertisement.ServiceUuid})");
        return true;
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            Stream stream;
            try
            {
                stream = await _listener.AcceptAsync(ct);
            }
            catch (OperationCanceledException) { return; }
            catch (Exception ex)
            {
                _log($"Bluetooth accept failed: {ex.Message}");
                try { await Task.Delay(TimeSpan.FromSeconds(1), ct); }
                catch (OperationCanceledException) { return; }
                continue;
            }
            _ = Task.Run(async () =>
            {
                var transport = new StreamFramedTransport(stream);
                try { await _onConnection(transport, ct); }
                catch (Exception ex) { _log($"Bluetooth connection error: {ex.Message}"); }
                finally { transport.Close(); }
            }, CancellationToken.None);
        }
    }

    public async Task StopAsync()
    {
        IsRunning = false;
        var cts = _cts;
        if (cts == null) return;
        cts.Cancel();
        try { if (_acceptLoop != null) await _acceptLoop; } catch { }
        try { await _listener.DisposeAsync(); } catch { }
        cts.Dispose();
        _cts = null;
    }

    public ValueTask DisposeAsync() => new(StopAsync());
}
