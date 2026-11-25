using Agent.Core.Pairing;

namespace Agent.Core.Ui;

/// <summary>
/// Console implementation of <see cref="IPairingCodeDisplay"/>. Prints the code
/// prominently and re-prints when it changes. Not a tray/menu-bar window.
/// </summary>
public sealed class ConsolePairingCodeDisplay : IPairingCodeDisplay
{
    private readonly TextWriter _out;
    private string? _lastCode;
    private bool _lockoutShown;

    public ConsolePairingCodeDisplay(TextWriter? output = null) => _out = output ?? Console.Out;

    public void ShowCode(string? code)
    {
        if (code == _lastCode) return;
        _lastCode = code;
        _lockoutShown = false;
        if (code is null)
        {
            _out.WriteLine("Pairing code: (none active)");
            return;
        }
        var bar = new string('=', 30);
        _out.WriteLine(bar);
        _out.WriteLine($"   PAIRING CODE:  {code}");
        _out.WriteLine(bar);
    }

    public void ShowLockout(int remainingSeconds)
    {
        if (_lockoutShown) return;
        _lockoutShown = true;
        _lastCode = null;
        _out.WriteLine($"Pairing locked after too many incorrect codes. Try again in {remainingSeconds}s.");
    }

    public void ShowPermissionProblem(PermissionStatus status)
    {
        _out.WriteLine("PERMISSION REQUIRED: " + (status.Instructions ?? "Input injection is not permitted."));
    }

    /// <summary>
    /// Polls the manager until cancelled, showing the current code and generating
    /// a new one when none is active (initially, or after a lockout expires).
    /// </summary>
    public static async Task RunAsync(PairingAuthManager manager, IPairingCodeDisplay display,
        IPermissionChecker? checker, TimeSpan pollInterval, CancellationToken ct)
    {
        if (checker is not null)
        {
            var status = checker.Check();
            if (!status.Granted || status.Instructions is not null) display.ShowPermissionProblem(status);
        }
        while (!ct.IsCancellationRequested)
        {
            var remaining = manager.RemainingLockoutSeconds;
            if (remaining > 0)
            {
                display.ShowLockout(remaining);
            }
            else
            {
                var code = manager.CurrentCode ?? manager.GenerateCode();
                display.ShowCode(code);
            }
            try { await Task.Delay(pollInterval, ct); }
            catch (OperationCanceledException) { break; }
        }
    }
}
