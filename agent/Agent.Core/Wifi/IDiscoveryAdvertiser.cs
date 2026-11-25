using Agent.Core.Dispatch;
namespace Agent.Core.Wifi;

/// <summary>Makes this Desktop_Agent discoverable on a transport (Requirements 1.1, 1.2, 2.1).</summary>
public interface IDiscoveryAdvertiser : IDisposable
{
    /// <summary>Starts advertising; announces immediately. Idempotent.</summary>
    void Start(string hostName, HostOS os, string hostId, int port);
    /// <summary>Stops advertising (sends goodbye records where the protocol supports it). Idempotent.</summary>
    void Stop();
}
