using System.Runtime.InteropServices;
using Agent.Core.Ui;

namespace Agent.Windows;

/// <summary>
/// Windows SendInput needs no grant, but UIPI blocks injection into windows of
/// higher integrity (elevated) processes. Reports when the foreground window
/// belongs to an elevated process while the agent is not elevated (Requirement 9.5).
/// </summary>
public sealed class WindowsPermissionChecker : IPermissionChecker
{
    public const string ElevatedInstructions =
        "The active window belongs to an elevated (administrator) program, and Windows blocks input " +
        "from non-elevated programs into it. Run the agent as administrator to control that window.";

    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint TokenQuery = 0x0008;
    private const int TokenElevation = 20;

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("kernel32.dll")] private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(IntPtr token, int infoClass, out int info, int len, out int retLen);

    public PermissionStatus Check()
    {
        if (!OperatingSystem.IsWindows()) return new PermissionStatus(true, null);
        try
        {
            if (IsProcessElevated(GetCurrentProcess())) return new PermissionStatus(true, null);
            var hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero || GetWindowThreadProcessId(hwnd, out var pid) == 0)
                return new PermissionStatus(true, null);
            var h = OpenProcess(ProcessQueryLimitedInformation, false, pid);
            if (h == IntPtr.Zero)
                // Cannot open it at all; likely a higher-integrity process.
                return new PermissionStatus(true, ElevatedInstructions);
            try { return IsProcessElevated(h) ? new PermissionStatus(true, ElevatedInstructions) : new PermissionStatus(true, null); }
            finally { CloseHandle(h); }
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException)
        {
            return new PermissionStatus(true, null);
        }
    }

    private static bool IsProcessElevated(IntPtr process)
    {
        if (!OpenProcessToken(process, TokenQuery, out var token)) return false;
        try
        {
            return GetTokenInformation(token, TokenElevation, out var elevated, sizeof(int), out _) && elevated != 0;
        }
        finally { CloseHandle(token); }
    }
}
