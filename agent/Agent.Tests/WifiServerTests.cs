using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using Agent.Core.Protocol;
using Agent.Core.Wifi;
namespace Agent.Tests;

public class WifiServerTests
{
    [Fact]
    public async Task TlsServer_EchoesFramesAndPersistsCertificate()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".pfx");
        try
        {
            using var cert = CertificateStore.LoadOrCreate(path, "test");
            using var again = CertificateStore.LoadOrCreate(path, "test");
            Assert.Equal(cert.Thumbprint, again.Thumbprint);

            using var server = new WifiServer(cert, async (t, ct) =>
            {
                var f = await t.ReceiveFrameAsync(ct);
                await t.SendFrameAsync(f!, ct);
                t.Close();
            });
            server.Start(0);
            using var tcp = new TcpClient();
            await tcp.ConnectAsync(IPAddress.Loopback, server.Port);
            using var ssl = new SslStream(tcp.GetStream(), false, (_, _, _, _) => true);
            await ssl.AuthenticateAsClientAsync("localhost");
            await ssl.WriteAsync(Framing.EncodeFrame(new byte[] { 1, 2, 3 }));
            var buf = new byte[7];
            var read = 0;
            while (read < 7) read += await ssl.ReadAsync(buf.AsMemory(read));
            Assert.Equal(new byte[] { 0, 0, 0, 3, 1, 2, 3 }, buf);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void MdnsPacket_ResponseContainsServiceAndQuestionsParse()
    {
        var pkt = MdnsPacket.BuildResponse("Desk", "desk", 52800,
            new[] { new KeyValuePair<string, string>("os", "windows") },
            new[] { IPAddress.Parse("192.168.1.5") }, 120);
        Assert.Equal(0x84, pkt[2]);
        Assert.Contains("_trackpad", System.Text.Encoding.UTF8.GetString(pkt));
        Assert.Empty(MdnsPacket.ParseQuestions(pkt));

        var q = new List<byte> { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        foreach (var l in new[] { "_trackpad", "_tcp", "local" })
        { q.Add((byte)l.Length); q.AddRange(System.Text.Encoding.ASCII.GetBytes(l)); }
        q.AddRange(new byte[] { 0, 0, 12, 0, 1 });
        var qs = MdnsPacket.ParseQuestions(q.ToArray());
        Assert.True(MdnsAdvertiser.ShouldAnswer(qs, "Desk", "desk"));
    }
}
