using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using Agent.Core.Dispatch;
namespace Agent.Core.Wifi;

/// <summary>
/// Minimal cross-platform mDNS responder advertising <c>_trackpad._tcp</c> with TXT
/// keys <c>os</c> (macOS/windows) and <c>id</c>. Answers PTR/SRV/TXT/A/ANY queries
/// and announces on start (Requirements 1.1, 1.2, 2.1).
/// </summary>
public sealed class MdnsAdvertiser : IDiscoveryAdvertiser
{
    private static readonly IPAddress Group = IPAddress.Parse("224.0.0.251");
    private static readonly IPEndPoint GroupEndPoint = new(Group, 5353);
    private readonly Action<string> _log;
    private readonly object _gate = new();
    private UdpClient? _udp;
    private CancellationTokenSource? _cts;
    private string _instance = "", _hostLabel = "";
    private int _port;
    private List<KeyValuePair<string, string>> _txt = new();

    public MdnsAdvertiser(Action<string>? log = null) => _log = log ?? (_ => { });

    public void Start(string hostName, HostOS os, string hostId, int port)
    {
        lock (_gate)
        {
            if (_udp != null) return;
            _instance = SanitizeLabel(hostName, "Desktop");
            _hostLabel = SanitizeLabel(hostName, "desktop").Replace(' ', '-');
            _port = port;
            _txt = new()
            {
                new("os", os == HostOS.Windows ? "windows" : "macOS"),
                new("id", hostId),
            };
            var udp = new UdpClient(AddressFamily.InterNetwork);
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            if (!OperatingSystem.IsWindows())
            {
                // SO_REUSEPORT: 0x200 on macOS, 15 on Linux (lets us coexist with mDNSResponder).
                try { udp.Client.SetSocketOption(SocketOptionLevel.Socket, (SocketOptionName)(OperatingSystem.IsMacOS() ? 0x200 : 15), true); }
                catch { }
            }
            udp.Client.Bind(new IPEndPoint(IPAddress.Any, 5353));
            foreach (var addr in LocalAddresses())
            {
                try { udp.JoinMulticastGroup(Group, addr); }
                catch (Exception ex) { _log($"mDNS: join failed on {addr}: {ex.Message}"); }
            }
            udp.MulticastLoopback = false;
            _udp = udp;
            _cts = new CancellationTokenSource();
            _ = Task.Run(() => ListenAsync(udp, _cts.Token));
            _ = Task.Run(() => AnnounceAsync(udp, _cts.Token));
        }
    }

    public void Stop()
    {
        UdpClient? udp;
        lock (_gate)
        {
            udp = _udp;
            if (udp == null) return;
            _udp = null;
            _cts?.Cancel();
        }
        try { Send(udp, 0); } catch { }
        try { udp.Dispose(); } catch { }
    }

    public void Dispose() => Stop();

    private async Task AnnounceAsync(UdpClient udp, CancellationToken ct)
    {
        try
        {
            for (var i = 0; i < 3 && !ct.IsCancellationRequested; i++)
            {
                Send(udp, 120);
                await Task.Delay(TimeSpan.FromSeconds(1 << i), ct);
            }
        }
        catch (Exception) { }
    }

    private async Task ListenAsync(UdpClient udp, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var r = await udp.ReceiveAsync(ct);
                if (ShouldAnswer(MdnsPacket.ParseQuestions(r.Buffer), _instance, _hostLabel))
                    Send(udp, 120);
            }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (Exception ex) { _log($"mDNS: {ex.Message}"); await Task.Delay(200, CancellationToken.None); }
        }
    }

    /// <summary>True if any question asks for our PTR/SRV/TXT/A data.</summary>
    public static bool ShouldAnswer(IEnumerable<MdnsPacket.Question> questions, string instance, string hostLabel)
    {
        var inst = $"{instance}.{MdnsPacket.ServiceType}";
        var host = $"{hostLabel}.local";
        foreach (var q in questions)
        {
            var isType = q.Type is MdnsPacket.TypePtr or MdnsPacket.TypeSrv or MdnsPacket.TypeTxt
                or MdnsPacket.TypeA or MdnsPacket.TypeAny;
            if (!isType) continue;
            if (Eq(q.Name, MdnsPacket.ServiceType) || Eq(q.Name, inst) || Eq(q.Name, host)) return true;
        }
        return false;
    }

    private static bool Eq(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    private void Send(UdpClient udp, uint ttl)
    {
        var packet = MdnsPacket.BuildResponse(_instance, _hostLabel, _port, _txt, LocalAddresses(), ttl);
        udp.Send(packet, packet.Length, GroupEndPoint);
    }

    private static List<IPAddress> LocalAddresses()
    {
        var list = new List<IPAddress>();
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up || !nic.SupportsMulticast
                || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var ua in nic.GetIPProperties().UnicastAddresses)
                if (ua.Address.AddressFamily == AddressFamily.InterNetwork
                    && !ua.Address.ToString().StartsWith("169.254."))
                    list.Add(ua.Address);
        }
        return list;
    }

    private static string SanitizeLabel(string name, string fallback)
    {
        var s = new string(name.Where(c => !char.IsControl(c)).ToArray()).Replace('.', '-').Trim();
        if (s.Length == 0) s = fallback;
        while (Encoding.UTF8.GetByteCount(s) > 63) s = s[..^1];
        return s;
    }
}
