using System.Security.Cryptography;
using System.Text;
using System.Threading.Channels;
using Agent.Core.Dispatch;
using Agent.Core.Pairing;
using Agent.Core.Protocol;
using Agent.Core.Security;
using Agent.Core.Session;

namespace Agent.Tests;

public class ConnectionSessionTests
{
    private sealed class FakeTransport : IFramedTransport
    {
        public readonly Channel<byte[]?> Inbox = Channel.CreateUnbounded<byte[]?>();
        public readonly Channel<byte[]> Outbox = Channel.CreateUnbounded<byte[]>();
        public bool Closed;

        public async Task<byte[]?> ReceiveFrameAsync(CancellationToken ct) => await Inbox.Reader.ReadAsync(ct);
        public Task SendFrameAsync(byte[] frame, CancellationToken ct) { Outbox.Writer.TryWrite(frame); return Task.CompletedTask; }
        public void Close() => Closed = true;

        public async Task<byte[]> NextSent() => await Outbox.Reader.ReadAsync(new CancellationTokenSource(5000).Token);
    }

    private sealed class Injector : IInputInjector
    {
        public List<string> Calls = new();
        public HostOS HostOS => HostOS.Windows;
        public DisplayBounds Bounds => new(0, 0, 1000, 1000);
        public (double X, double Y) Position => (500, 500);
        public void MoveTo(double x, double y) => Calls.Add($"move {x},{y}");
        public void ButtonDown(MouseButton b) => Calls.Add($"down {b}");
        public void ButtonUp(MouseButton b) => Calls.Add($"up {b}");
        public void Click(MouseButton b, int n) => Calls.Add($"click {b}");
        public void ModifierDown(Modifier m) { }
        public void ModifierUp(Modifier m) { }
        public void KeyDown(KeyId k) { }
        public void KeyUp(KeyId k) { }
        public void Scroll(double dx, double dy) { }
    }

    private sealed class Rig
    {
        public readonly FakeTransport T = new();
        public readonly Injector Inj = new();
        public readonly InMemoryPairedHostStore Store = new();
        public readonly InMemoryPairedSecretStore Secrets = new();
        public readonly PairingAuthManager Auth;
        public readonly List<string> Log = new();
        public readonly TaskCompletionSource IdleFired = new();
        public readonly ConnectionSession Session;
        public readonly byte[] ServerNonceFixed = Enumerable.Range(0, 16).Select(i => (byte)(0x20 + i)).ToArray();
        public Task Run;

        public Rig()
        {
            Auth = new PairingAuthManager(Store);
            var dispatcher = new EventDispatcher(Inj, Auth);
            // The fake timer never fires on its own; tests complete it explicitly.
            Session = new ConnectionSession(T, Auth, Secrets, dispatcher, HostOS.Windows, Log.Add,
                async (_, ct) => { using (ct.Register(() => { })) await IdleFired.Task.WaitAsync(ct); },
                n => n == 16 ? ServerNonceFixed : RandomNumberGenerator.GetBytes(n));
            Run = Session.RunAsync();
        }
    }

    private static readonly byte[] Cn = Enumerable.Range(0, 16).Select(i => (byte)(0x10 + i)).ToArray();

    private static byte[] ClientHello(bool hasSecret, byte[] fingerprint)
    {
        var m = new List<byte> { 0xC0, 0x01, 1 };
        m.AddRange(Cn);
        m.Add((byte)(hasSecret ? 1 : 0));
        m.AddRange(fingerprint);
        return m.ToArray();
    }

    private static SecureChannel ClientChannel(byte[] secret, byte[] serverNonce)
        => SecureChannel.Create(secret, Cn, serverNonce, ChannelRole.Client);

    [Fact]
    public async Task NewHost_ReportsOs_PairsWithCode_ThenDispatchesEvents()
    {
        var r = new Rig();
        r.T.Inbox.Writer.TryWrite(ClientHello(false, new byte[8]));
        var hello = await r.T.NextSent();
        Assert.Equal(20, hello.Length);
        Assert.Equal(new byte[] { 0xC0, 0x02 }, hello[..2]);
        Assert.Equal(1, hello[16 + 2]); // Windows
        Assert.Equal(1, hello[16 + 3]); // pairing required
        var sn = hello[2..18];

        var code = r.Auth.CurrentCode!;
        var wrong = code == "000000" ? "111111" : "000000";
        byte[] Submit(string c, byte[] secret) => ClientChannel(
            SHA256.HashData(Encoding.ASCII.GetBytes("trackpad/v1/pairing:" + c)), sn)
            .Encrypt(new byte[] { 0xC0, 0x03 }.Concat(secret).ToArray());

        var secret = Enumerable.Range(100, 32).Select(i => (byte)i).ToArray();
        r.T.Inbox.Writer.TryWrite(Submit(wrong, secret));
        var bad = await r.T.NextSent();
        Assert.Equal(new byte[] { 0xC0, 0x04, 1, 1, 0, 0 }, bad);

        r.T.Inbox.Writer.TryWrite(Submit(code, secret));
        Assert.Equal(new byte[] { 0xC0, 0x04, 0, 0, 0, 0 }, await r.T.NextSent());

        var channel = ClientChannel(secret, sn);
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new ButtonAction(MouseButton.Left, ButtonState.Down))));
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(new byte[] { 1, 0xEE, 0xEE })); // malformed type
        r.T.Inbox.Writer.TryWrite(new byte[] { 1, 2, 3 }); // garbage, not decryptable
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new ClickAction(MouseButton.Right, 1))));
        r.T.Inbox.Writer.TryWrite(null);
        await r.Run.WaitAsync(TimeSpan.FromSeconds(5));

        // Connection stayed alive past the malformed messages; held button released on close.
        Assert.Equal(new[] { "down Left", "click Right", "up Left" }, r.Inj.Calls);
        Assert.Contains(r.Log, l => l.StartsWith("Malformed") || l.StartsWith("Version"));
        Assert.True(r.T.Closed);
        Assert.NotNull(r.Secrets.TryGetSecret(SecretFingerprint.Compute(secret)));
    }

    [Fact]
    public async Task PairedHost_ProvesPossessionWithHeartbeat()
    {
        var r = new Rig();
        var secret = Enumerable.Range(1, 32).Select(i => (byte)i).ToArray();
        r.Secrets.SaveSecret(secret);
        r.Store.Add(SecretFingerprint.Compute(secret));

        r.T.Inbox.Writer.TryWrite(ClientHello(true, SecretFingerprint.Compute(secret)));
        var hello = await r.T.NextSent();
        Assert.Equal(0, hello[19]); // no pairing required
        var channel = ClientChannel(secret, hello[2..18]);
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new Heartbeat())));
        Assert.Equal(new byte[] { 0xC0, 0x04, 0, 0, 0, 0 }, await r.T.NextSent());
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new ClickAction(MouseButton.Left, 1))));
        r.T.Inbox.Writer.TryWrite(null);
        await r.Run.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(new[] { "click Left" }, r.Inj.Calls);
    }

    [Fact]
    public async Task PairedHost_WithBadProof_IsRejectedAndClosed()
    {
        var r = new Rig();
        var secret = Enumerable.Range(1, 32).Select(i => (byte)i).ToArray();
        r.Secrets.SaveSecret(secret);
        r.Store.Add(SecretFingerprint.Compute(secret));
        r.T.Inbox.Writer.TryWrite(ClientHello(true, SecretFingerprint.Compute(secret)));
        var hello = await r.T.NextSent();
        var wrongChannel = ClientChannel(new byte[32], hello[2..18]);
        r.T.Inbox.Writer.TryWrite(wrongChannel.Encrypt(ProtocolCodec.Encode(new Heartbeat())));
        Assert.Equal(new byte[] { 0xC0, 0x04, 3, 0, 0, 0 }, await r.T.NextSent());
        await r.Run.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.True(r.T.Closed);
    }

    [Fact]
    public async Task IdleTimeout_ClosesConnectionAndReleasesHeldInput()
    {
        var r = new Rig();
        var secret = Enumerable.Range(1, 32).Select(i => (byte)i).ToArray();
        r.Secrets.SaveSecret(secret);
        r.Store.Add(SecretFingerprint.Compute(secret));
        r.T.Inbox.Writer.TryWrite(ClientHello(true, SecretFingerprint.Compute(secret)));
        var hello = await r.T.NextSent();
        var channel = ClientChannel(secret, hello[2..18]);
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new Heartbeat())));
        await r.T.NextSent();
        r.T.Inbox.Writer.TryWrite(channel.Encrypt(ProtocolCodec.Encode(new ButtonAction(MouseButton.Left, ButtonState.Down))));
        await Task.Delay(200);
        Assert.False(r.Run.IsCompleted);

        r.IdleFired.SetResult(); // 10 seconds of silence
        await r.Run.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(new[] { "down Left", "up Left" }, r.Inj.Calls);
        Assert.True(r.T.Closed);
        Assert.Contains(r.Log, l => l.Contains("no data for 10 seconds"));
    }
}
