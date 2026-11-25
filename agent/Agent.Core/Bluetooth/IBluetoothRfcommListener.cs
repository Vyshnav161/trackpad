namespace Agent.Core.Bluetooth;

/// <summary>What the Desktop_Agent publishes in its SDP record (Requirements 1.1, 1.2).</summary>
/// <param name="ServiceUuid">RFCOMM service UUID; must equal Dart <c>agentRfcommServiceUuid</c>.</param>
/// <param name="ServiceName">SDP service name (human readable, includes Host name).</param>
/// <param name="HostName">Host name shown in the Android host list.</param>
/// <param name="HostOs">"macOS" or "Windows".</param>
public sealed record BluetoothAdvertisement(Guid ServiceUuid, string ServiceName, string HostName, string HostOs)
{
    /// <summary>Same value as <c>agentRfcommServiceUuid</c> in lib/transport/bluetooth_discovery.dart.</summary>
    public static readonly Guid AgentServiceUuid = new("6f1b5a3e-7c2d-4e8a-9b41-3d5e2a7c9f10");

    public static BluetoothAdvertisement ForHost(string hostName, string hostOs) =>
        new(AgentServiceUuid, $"Trackpad Agent ({hostName}, {hostOs})", hostName, hostOs);
}

/// <summary>
/// Platform-specific RFCOMM server. Implementations register an SDP record for the
/// advertisement and yield one duplex byte stream per incoming connection.
/// All members must fail soft: report problems via <see cref="IsSupported"/> /
/// exceptions from <see cref="StartAsync"/>, never crash the process.
/// </summary>
public interface IBluetoothRfcommListener : IAsyncDisposable
{
    /// <summary>False when this OS/adapter cannot host an RFCOMM service.</summary>
    bool IsSupported { get; }

    /// <summary>Why <see cref="IsSupported"/> is false, otherwise null.</summary>
    string? UnsupportedReason { get; }

    /// <summary>Registers the SDP record and starts listening.</summary>
    Task StartAsync(BluetoothAdvertisement advertisement, CancellationToken cancellationToken);

    /// <summary>Waits for the next connection; the stream carries raw (length-prefixed) bytes.</summary>
    Task<Stream> AcceptAsync(CancellationToken cancellationToken);
}
