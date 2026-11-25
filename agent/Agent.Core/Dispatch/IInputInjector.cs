using Agent.Core.Protocol;

namespace Agent.Core.Dispatch;

public enum HostOS { MacOS, Windows }

/// <summary>Inclusive pixel bounds of the injectable display area.</summary>
public readonly record struct DisplayBounds(double MinX, double MinY, double MaxX, double MaxY)
{
    public double ClampX(double x) => Math.Min(Math.Max(x, MinX), MaxX);
    public double ClampY(double y) => Math.Min(Math.Max(y, MinY), MaxY);
}

/// <summary>
/// Platform adapter (Windows SendInput / macOS CGEventPost). Keeps the
/// <see cref="EventDispatcher"/> platform-agnostic.
/// </summary>
public interface IInputInjector
{
    HostOS HostOS { get; }
    DisplayBounds Bounds { get; }
    /// <summary>Current absolute pointer position.</summary>
    (double X, double Y) Position { get; }

    void MoveTo(double x, double y);
    void ButtonDown(MouseButton button);
    void ButtonUp(MouseButton button);
    /// <summary>Full click (down+up) repeated <paramref name="clickCount"/> as a multi-click.</summary>
    void Click(MouseButton button, int clickCount);
    /// <summary>Press a modifier. <see cref="Modifier.Platform"/> is Command on macOS, Windows key on Windows.</summary>
    void ModifierDown(Modifier modifier);
    void ModifierUp(Modifier modifier);
    void KeyDown(KeyId key);
    void KeyUp(KeyId key);
    /// <summary>
    /// Scrolls the view. Convention (same as Dart ScrollEvent, which is sign-inverted
    /// by the classifier when natural scrolling is on): positive <paramref name="dy"/>
    /// scrolls the view down (content moves up), positive <paramref name="dx"/> scrolls right.
    /// Implementations translate to the OS wheel sign.
    /// </summary>
    void Scroll(double dx, double dy);
}
