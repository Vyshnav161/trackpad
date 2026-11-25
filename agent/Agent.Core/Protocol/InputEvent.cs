namespace Agent.Core.Protocol;

// Mirrors lib/protocol/input_event.dart. Enum member order is the wire id.

public enum MouseButton { Left, Right }

public enum ButtonState { Down, Up }

public enum Modifier { Shift, Control, Alt, Platform }

/// <summary>Wire ids are the enum values; do not reorder.</summary>
public enum SpecialKey
{
    Backspace, Enter, Tab, Escape, Delete,
    ArrowUp, ArrowDown, ArrowLeft, ArrowRight,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

public abstract record InputEvent;

public sealed record PointerMove(double Dx, double Dy) : InputEvent;

public sealed record ButtonAction(MouseButton Button, ButtonState Action) : InputEvent;

/// <summary>ClickCount is 1 (single) or 2 (double).</summary>
public sealed record ClickAction(MouseButton Button, int ClickCount) : InputEvent;

public sealed record ScrollEvent(double Dx, double Dy) : InputEvent;

public sealed record ZoomEvent(double Magnitude) : InputEvent;

public sealed record AppSwitchEvent : InputEvent;

public abstract record KeyId;

/// <summary>Unicode scalar value (0..0x10FFFF, excluding surrogates).</summary>
public sealed record CharKey(int Codepoint) : KeyId;

public sealed record SpecialKeyId(SpecialKey Key) : KeyId;

public sealed record KeyAction : InputEvent
{
    public KeyAction(KeyId key, IEnumerable<Modifier> modifiers, ButtonState action)
    {
        Key = key;
        Modifiers = new HashSet<Modifier>(modifiers);
        Action = action;
    }

    public KeyId Key { get; }
    public IReadOnlySet<Modifier> Modifiers { get; }
    public ButtonState Action { get; }

    public bool Equals(KeyAction? other) =>
        other is not null
        && Key == other.Key
        && Action == other.Action
        && Modifiers.Count == other.Modifiers.Count
        && Modifiers.All(other.Modifiers.Contains);

    public override int GetHashCode()
    {
        var mask = 0;
        foreach (var m in Modifiers) mask |= 1 << (int)m;
        return HashCode.Combine(Key, Action, mask);
    }
}

public sealed record Heartbeat : InputEvent;

public abstract record CodecError;

public sealed record Malformed(string Reason) : CodecError;

public sealed record VersionMismatch(int Found, int Supported) : CodecError;

/// <summary>Result of <see cref="ProtocolCodec.Decode"/>.</summary>
public abstract record DecodeResult;

public sealed record DecodeOk(InputEvent Event) : DecodeResult;

public sealed record DecodeErr(CodecError Error) : DecodeResult;
