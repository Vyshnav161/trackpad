using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Agent.Core.Dispatch;
using Agent.Core.Pairing;
using Agent.Core.Protocol;
using Agent.Core.Security;

namespace Agent.Core.Session;

/// <summary>
/// Agent side of one Connection: handshake (mirrors lib/transport/handshake.dart),
/// then decrypt, decode and dispatch Input_Events until the link closes or goes
/// silent for 10 seconds (Requirements 9.1, 10.3, 10.4, 11.4, 11.5).
/// </summary>
public sealed class ConnectionSession
{
    public const byte ControlMarker = 0xC0;
    public const byte MsgClientHello = 0x01;
    public const byte MsgServerHello = 0x02;
    public const byte MsgPairingSubmit = 0x03;
    public const byte MsgPairingResult = 0x04;
    public const int ClientHelloLength = 28;
    public const int ServerHelloLength = 20;
    public const int PairingSecretLength = 32;
    public static readonly TimeSpan IdleTimeout = TimeSpan.FromSeconds(10);

    private readonly IFramedTransport _transport;
    private readonly PairingAuthManager _auth;
    private readonly IPairedSecretStore _secrets;
    private readonly EventDispatcher _dispatcher;
    private readonly HostOS _hostOs;
    private readonly Action<string> _log;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private readonly Func<int, byte[]> _randomBytes;

    /// <param name="delay">Timer used for the idle timeout; defaults to Task.Delay. Inject in tests.</param>
    public ConnectionSession(
        IFramedTransport transport,
        PairingAuthManager auth,
        IPairedSecretStore secrets,
        EventDispatcher dispatcher,
        HostOS hostOs,
        Action<string>? log = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null,
        Func<int, byte[]>? randomBytes = null,
        Guid? connectionId = null)
    {
        _transport = transport;
        _auth = auth;
        _secrets = secrets;
        _dispatcher = dispatcher;
        _hostOs = hostOs;
        _log = log ?? (_ => { });
        _delay = delay ?? Task.Delay;
        _randomBytes = randomBytes ?? RandomNumberGenerator.GetBytes;
        ConnectionId = connectionId ?? Guid.NewGuid();
    }

    public Guid ConnectionId { get; }

    /// <summary>
    /// Runs the connection to completion. Never throws (except cancellation of
    /// <paramref name="ct"/> is swallowed too); always releases held input and closes the link.
    /// </summary>
    public async Task RunAsync(CancellationToken ct = default)
    {
        try
        {
            var channel = await HandshakeAsync(ct);
            if (channel != null) await ReceiveLoopAsync(channel, ct);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            _log($"Connection {ConnectionId} failed: {ex.Message}");
        }
        finally
        {
            _dispatcher.CloseConnection(ConnectionId);
            _auth.EndConnection(ConnectionId);
            _transport.Close();
        }
    }

    // -- handshake ------------------------------------------------------------

    private async Task<SecureChannel?> HandshakeAsync(CancellationToken ct)
    {
        var helloBytes = await ReceiveAsync(ct);
        if (helloBytes is not { Length: ClientHelloLength } h
            || h[0] != ControlMarker || h[1] != MsgClientHello || h[3 + SecureChannel.NonceLength] > 1)
        {
            _log("Handshake failed: invalid ClientHello");
            return null;
        }
        var clientNonce = h[3..(3 + SecureChannel.NonceLength)];
        var hasSecret = h[3 + SecureChannel.NonceLength] == 1;
        var fingerprint = h[(4 + SecureChannel.NonceLength)..];

        var pairedSecret = hasSecret ? _secrets.TryGetSecret(fingerprint) : null;
        var paired = pairedSecret != null && _auth.IsPairedHost(fingerprint);
        if (!paired) _auth.BeginConnection(ConnectionId, new byte[SecretFingerprint.Length]);

        var serverNonce = _randomBytes(SecureChannel.NonceLength);
        var serverHello = new byte[ServerHelloLength];
        serverHello[0] = ControlMarker;
        serverHello[1] = MsgServerHello;
        serverNonce.CopyTo(serverHello, 2);
        serverHello[2 + SecureChannel.NonceLength] = (byte)_hostOs; // Requirement 9.1
        serverHello[3 + SecureChannel.NonceLength] = (byte)(paired ? 0 : 1);
        await _transport.SendFrameAsync(serverHello, ct);

        return paired
            ? await ProveKeyPossessionAsync(pairedSecret!, clientNonce, serverNonce, ct)
            : await PairAsync(clientNonce, serverNonce, ct);
    }

    private async Task<SecureChannel?> ProveKeyPossessionAsync(
        byte[] secret, byte[] clientNonce, byte[] serverNonce, CancellationToken ct)
    {
        var channel = SecureChannel.Create(secret, clientNonce, serverNonce, ChannelRole.Server);
        var frame = await ReceiveAsync(ct);
        var plain = frame == null ? null : channel.Decrypt(frame);
        if (plain == null || ProtocolCodec.Decode(plain) is not DecodeOk { Event: Heartbeat })
        {
            _log("Handshake failed: key possession proof rejected");
            if (frame != null) await SendResultAsync(PairingStatus.Rejected, 0, 0, ct);
            return null;
        }
        _auth.MarkAuthenticated(ConnectionId);
        await SendResultAsync(PairingStatus.Accepted, 0, 0, ct);
        return channel;
    }

    private async Task<SecureChannel?> PairAsync(byte[] clientNonce, byte[] serverNonce, CancellationToken ct)
    {
        while (true)
        {
            var frame = await ReceiveAsync(ct);
            if (frame == null) return null;

            // A fresh channel per attempt (counter restarts at 0), keyed by the displayed code.
            byte[]? newSecret = null;
            var code = _auth.CurrentCode;
            if (code != null)
            {
                var pairingKey = SHA256.HashData(Encoding.ASCII.GetBytes("trackpad/v1/pairing:" + code));
                var plain = SecureChannel.Create(pairingKey, clientNonce, serverNonce, ChannelRole.Server).Decrypt(frame);
                if (plain is { Length: 2 + PairingSecretLength } && plain[0] == ControlMarker && plain[1] == MsgPairingSubmit)
                    newSecret = plain[2..];
            }

            var result = _auth.ReportAttempt(ConnectionId, newSecret != null, newSecret);
            if (result.Status == PairingStatus.Accepted) _secrets.SaveSecret(newSecret!);
            await SendResultAsync(result.Status, result.FailedAttempts, result.LockoutSeconds, ct);

            switch (result.Status)
            {
                case PairingStatus.Accepted:
                    return SecureChannel.Create(newSecret!, clientNonce, serverNonce, ChannelRole.Server);
                case PairingStatus.Rejected:
                    return null;
            }
        }
    }

    private Task SendResultAsync(PairingStatus status, int failed, int lockoutSeconds, CancellationToken ct)
    {
        var msg = new byte[6];
        msg[0] = ControlMarker;
        msg[1] = MsgPairingResult;
        msg[2] = (byte)status;
        msg[3] = (byte)Math.Min(failed, 255);
        BinaryPrimitives.WriteUInt16BigEndian(msg.AsSpan(4), (ushort)Math.Min(lockoutSeconds, ushort.MaxValue));
        return _transport.SendFrameAsync(msg, ct);
    }

    // -- steady state -----------------------------------------------------------

    private async Task ReceiveLoopAsync(SecureChannel channel, CancellationToken ct)
    {
        while (true)
        {
            var frame = await ReceiveAsync(ct);
            if (frame == null) return;

            var plain = channel.Decrypt(frame);
            if (plain == null)
            {
                _log("Discarded message: failed decryption or replayed counter");
                continue;
            }
            switch (ProtocolCodec.Decode(plain))
            {
                case DecodeOk ok:
                    _dispatcher.Dispatch(ConnectionId, ok.Event);
                    break;
                case DecodeErr err:
                    _log(ProtocolCodec.PrettyPrintError(err.Error));
                    break;
            }
        }
    }

    /// <summary>
    /// Next frame; null when the peer closed or nothing arrived within
    /// <see cref="IdleTimeout"/> (Requirement 11.4).
    /// </summary>
    private async Task<byte[]?> ReceiveAsync(CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var receive = _transport.ReceiveFrameAsync(cts.Token);
        var timer = _delay(IdleTimeout, cts.Token);
        var winner = await Task.WhenAny(receive, timer);
        if (winner == receive)
        {
            cts.Cancel(); // stop the timer
            return await receive;
        }
        ct.ThrowIfCancellationRequested();
        _log($"Connection {ConnectionId} closed: no data for {IdleTimeout.TotalSeconds:0} seconds");
        cts.Cancel();
        _ = receive.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);
        return null;
    }
}
