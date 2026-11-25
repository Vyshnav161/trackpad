using System.Runtime.InteropServices;

namespace Agent.Core.Bluetooth;

/// <summary>
/// STUB. Used on platforms where no RFCOMM server backend is implemented. It reports
/// itself unsupported so <see cref="BluetoothServer"/> logs it and does nothing,
/// leaving the Wi-Fi path untouched.
///
/// Not implemented (needs platform SDKs not available to this net7.0 library build):
///  - Windows: Windows.Devices.Bluetooth.Rfcomm.RfcommServiceProvider (WinRT). Requires
///    the net7.0-windows10.0.19041.0 TFM in Agent.Windows.csproj; implement there as
///    an IBluetoothRfcommListener (CreateAsync(RfcommServiceId.FromUuid(uuid)), set SDP
///    attribute 0x100 to the service name, BindServiceAsync, ConnectionReceived ->
///    StreamSocket.InputStream/OutputStream.AsStream()).
///  - macOS: IOBluetooth (IOBluetoothAddServiceDict + RegisterForFilteredRFCOMMChannelOpenNotifications),
///    which needs an Objective-C delegate class created at runtime; implement in Agent.Mac.
/// </summary>
public sealed class UnsupportedBluetoothListener : IBluetoothRfcommListener
{
    public UnsupportedBluetoothListener(string? reason = null)
    {
        UnsupportedReason = reason ?? $"Bluetooth RFCOMM server is not implemented for {RuntimeInformation.OSDescription}.";
    }

    public bool IsSupported => false;
    public string? UnsupportedReason { get; }

    public Task StartAsync(BluetoothAdvertisement advertisement, CancellationToken cancellationToken) =>
        throw new NotSupportedException(UnsupportedReason);

    public Task<Stream> AcceptAsync(CancellationToken cancellationToken) =>
        throw new NotSupportedException(UnsupportedReason);

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
