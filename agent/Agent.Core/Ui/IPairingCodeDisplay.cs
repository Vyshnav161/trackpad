namespace Agent.Core.Ui;

/// <summary>Presents the Pairing_Code to the user (Requirement 4.1).</summary>
public interface IPairingCodeDisplay
{
    /// <summary>Shows the given code, or clears the display when null.</summary>
    void ShowCode(string? code);

    /// <summary>Informs the user that pairing is locked out for the given seconds.</summary>
    void ShowLockout(int remainingSeconds);

    /// <summary>Shows a permission problem with grant instructions.</summary>
    void ShowPermissionProblem(PermissionStatus status);
}
