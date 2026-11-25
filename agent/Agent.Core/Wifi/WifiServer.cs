using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using Agent.Core.Session;
namespace Agent.Core.Wifi;

/// <summary>
/// Accepts TLS connections on the Wi-Fi port and hands each one, as an
/// <see cref="IFramedTransport"/>, to a handler (which runs a ConnectionSession).
/// Requirements 1.1, 9.1.
/// </summary>
public sealed class WifiServer : IDisposable
{
    public const int DefaultPort = 52800;
    private readonly X509Certificate2 _cert;
    private readonly Func<IFramedTransport, CancellationToken, Task> _handler;
    private readonly Action<string> _log;
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;

    public WifiServer(X509Certificate2 certificate,
        Func<IFramedTransport, CancellationToken, Task> connectionHandler, Action<string>? log = null)
    {
        _cert = certificate;
        _handler = connectionHandler;
        _log = log ?? (_ => { });
    }

    /// <summary>The bound port (useful when started with port 0).</summary>
    public int Port => ((IPEndPoint?)_listener?.LocalEndpoint)?.Port ?? 0;

    public void Start(int port = DefaultPort)
    {
        if (_listener != null) return;
        var l = new TcpListener(IPAddress.Any, port);
        l.Start();
        _listener = l;
        _cts = new CancellationTokenSource();
        _ = Task.Run(() => AcceptLoopAsync(l, _cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        try { _listener?.Stop(); } catch { }
        _listener = null;
    }

    public void Dispose() => Stop();

    private async Task AcceptLoopAsync(TcpListener l, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await l.AcceptTcpClientAsync(ct); }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (SocketException ex) { _log($"Wi-Fi accept failed: {ex.Message}"); if (ct.IsCancellationRequested) return; continue; }
            _ = Task.Run(() => HandleAsync(client, ct), ct);
        }
    }

    private async Task HandleAsync(TcpClient client, CancellationToken ct)
    {
        try
        {
            client.NoDelay = true;
            var ssl = new SslStream(client.GetStream(), false);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
            {
                ServerCertificate = _cert,
                ClientCertificateRequired = false,
                EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
            }, timeout.Token);
            await _handler(new StreamFramedTransport(ssl), ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _log($"Wi-Fi connection failed: {ex.Message}");
        }
        finally { client.Dispose(); }
    }
}
