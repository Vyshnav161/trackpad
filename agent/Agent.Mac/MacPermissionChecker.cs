using System.Runtime.InteropServices;
using Agent.Core.Ui;

namespace Agent.Mac;

/// <summary>Detects the macOS Accessibility permission needed by CGEventPost (Requirement 9.5).</summary>
public sealed class MacPermissionChecker : IPermissionChecker
{
    public const string GrantInstructions =
        "Accessibility permission is required. Open System Settings > Privacy & Security > Accessibility, " +
        "enable this agent (or the terminal running it), then restart the agent.";

    [DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")]
    private static extern bool AXIsProcessTrusted();

    public PermissionStatus Check()
    {
        if (!OperatingSystem.IsMacOS()) return new PermissionStatus(true, null);
        try
        {
            return AXIsProcessTrusted()
                ? new PermissionStatus(true, null)
                : new PermissionStatus(false, GrantInstructions);
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException)
        {
            return new PermissionStatus(false, GrantInstructions);
        }
    }
}
