using Agent.Core.Bluetooth;
using Agent.Core.Dispatch;
using Agent.Core.Pairing;
using Agent.Core.Session;
using Agent.Core.Ui;
using Agent.Core.Wifi;

namespace Agent.Core;

/// <summary>
/// Shared startup for the platform console projects: wires the Wi-Fi and Bluetooth
/// servers, mDNS advertiser, PairingAuthManager, EventDispatcher and ConnectionSession
/// together, runs the pairing code display loop and shuts down on Ctrl+C
/// (Requirements 4.6, 9.4, 11.5).
/// </summary>
public static class AgentHost
{
    public static string DefaultDataDirectory() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TrackpadAgent");

    /// <param name="bluetoothListener">Platform RFCOMM backend; null falls back to <see cref="UnsupportedBluetoothListener"/>.</param>
    /// <param name="dataDirectory">Where the certificate and paired hosts are persisted.</param>
    /// <param name="cancelOnCtrlC">Hook Console.CancelKeyPress to stop the agent.</param>
    /// <returns>Process exit code.</returns>
    public static async Task<int> RunAsync(
        IInputInjector injector,
        IPermissionChecker? permissionChecker = null,
        IBluetoothRfcommListener? bluetoothListener = null,
        IPairingCodeDisplay? display = null,
        string? dataDirectory = null,
        bool cancelOnCtrlC = true,
        CancellationToken cancellationToken = default)
    {
        var dataDir = dataDirectory ?? DefaultDataDirectory();
        var hostName = Environment.MachineName;
        var hostOs = injector.HostOS;
        Action<string> log = m => Console.WriteLine(m);

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        ConsoleCancelEventHandler? onCancel = null;
        if (cancelOnCtrlC)
        {
            onCancel = (_, e) => { e.Cancel = true; cts.Cancel(); };
            Console.CancelKeyPress += onCancel;
        }

        WifiServer? wifi = null;
        MdnsAdvertiser? mdns = null;
        BluetoothServer? bluetooth = null;
        try
        {
            var store = new FilePairedSecretStore(Path.Combine(dataDir, "paired-hosts.txt"));
            var auth = new PairingAuthManager(store);
            var dispatcher = new EventDispatcher(injector, auth);

            Task Handle(IFramedTransport transport, CancellationToken ct) =>
                new ConnectionSession(transport, auth, store, dispatcher, hostOs, log).RunAsync(ct);

            var cert = CertificateStore.LoadOrCreate(Path.Combine(dataDir, "tls.pfx"), hostName);
            wifi = new WifiServer(cert, Handle, log);
            wifi.Start();
            log($"Wi-Fi server listening on port {wifi.Port}");

            try
            {
                mdns = new MdnsAdvertiser(log);
                mdns.Start(hostName, hostOs, cert.GetCertHashString()[..16], wifi.Port);
            }
            catch (Exception ex)
            {
                log($"mDNS advertising disabled: {ex.Message}");
            }

            bluetooth = new BluetoothServer(
                bluetoothListener ?? new UnsupportedBluetoothListener(),
                BluetoothAdvertisement.ForHost(hostName, hostOs == HostOS.Windows ? "Windows" : "macOS"),
                Handle, log);
            await bluetooth.StartAsync(cts.Token);

            log("Trackpad agent running. Press Ctrl+C to stop.");
            await ConsolePairingCodeDisplay.RunAsync(
                auth, display ?? new ConsolePairingCodeDisplay(), permissionChecker,
                TimeSpan.FromMilliseconds(500), cts.Token);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Agent failed to start: {ex.Message}");
            return 1;
        }
        finally
        {
            if (onCancel != null) Console.CancelKeyPress -= onCancel;
            cts.Cancel();
            log("Shutting down...");
            try { wifi?.Stop(); } catch { }
            try { mdns?.Stop(); } catch { }
            if (bluetooth != null) { try { await bluetooth.StopAsync(); } catch { } }
        }
    }
}
