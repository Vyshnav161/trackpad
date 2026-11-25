namespace Agent.Core.Ui;

/// <summary>Result of an OS input-injection permission check (Requirement 9.5).</summary>
/// <param name="Granted">True when the agent can inject input.</param>
/// <param name="Instructions">Human-readable grant instructions; null when granted and no caveat applies.</param>
public readonly record struct PermissionStatus(bool Granted, string? Instructions);

/// <summary>Checks whether the OS allows the agent to inject input.</summary>
public interface IPermissionChecker
{
    /// <summary>Checks the permission, without prompting the user.</summary>
    PermissionStatus Check();
}
