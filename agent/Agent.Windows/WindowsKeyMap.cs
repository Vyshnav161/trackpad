using Agent.Core.Protocol;

namespace Agent.Windows;

/// <summary>Pure (no native calls) mapping helpers for <see cref="WindowsInputInjector"/>.</summary>
public static class WindowsKeyMap
{
    public const ushort VK_BACK = 0x08, VK_TAB = 0x09, VK_RETURN = 0x0D, VK_SHIFT = 0x10,
        VK_CONTROL = 0x11, VK_MENU = 0x12, VK_ESCAPE = 0x1B, VK_LEFT = 0x25, VK_UP = 0x26,
        VK_RIGHT = 0x27, VK_DOWN = 0x28, VK_DELETE = 0x2E, VK_LWIN = 0x5B, VK_F1 = 0x70;

    public const int WheelDelta = 120;

    /// <summary>Virtual-key code for a special key; <paramref name="extended"/> is true for keys needing KEYEVENTF_EXTENDEDKEY.</summary>
    public static ushort GetVirtualKey(SpecialKey key, out bool extended)
    {
        extended = key is SpecialKey.Delete or SpecialKey.ArrowUp or SpecialKey.ArrowDown
            or SpecialKey.ArrowLeft or SpecialKey.ArrowRight;
        return key switch
        {
            SpecialKey.Backspace => VK_BACK,
            SpecialKey.Enter => VK_RETURN,
            SpecialKey.Tab => VK_TAB,
            SpecialKey.Escape => VK_ESCAPE,
            SpecialKey.Delete => VK_DELETE,
            SpecialKey.ArrowUp => VK_UP,
            SpecialKey.ArrowDown => VK_DOWN,
            SpecialKey.ArrowLeft => VK_LEFT,
            SpecialKey.ArrowRight => VK_RIGHT,
            >= SpecialKey.F1 and <= SpecialKey.F12 => (ushort)(VK_F1 + (key - SpecialKey.F1)),
            _ => throw new ArgumentOutOfRangeException(nameof(key)),
        };
    }

    /// <summary>Platform modifier is the left Windows key.</summary>
    public static ushort GetModifierVirtualKey(Modifier modifier) => modifier switch
    {
        Modifier.Shift => VK_SHIFT,
        Modifier.Control => VK_CONTROL,
        Modifier.Alt => VK_MENU,
        Modifier.Platform => VK_LWIN,
        _ => throw new ArgumentOutOfRangeException(nameof(modifier)),
    };

    /// <summary>
    /// VK for ASCII letters (VK_A..VK_Z, same as uppercase ASCII) and digits (VK_0..VK_9, same as ASCII),
    /// used so shortcuts like Ctrl+C work. Returns null for anything else.
    /// </summary>
    public static ushort? GetCharVirtualKey(int codepoint)
    {
        if (codepoint >= 'a' && codepoint <= 'z') return (ushort)(codepoint - 'a' + 'A');
        if (codepoint >= 'A' && codepoint <= 'Z') return (ushort)codepoint;
        if (codepoint >= '0' && codepoint <= '9') return (ushort)codepoint;
        return null;
    }

    /// <summary>UTF-16 code units for a scalar value (surrogate pair above U+FFFF).</summary>
    public static ushort[] ToUtf16(int codepoint)
    {
        if (codepoint < 0 || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
            throw new ArgumentOutOfRangeException(nameof(codepoint));
        if (codepoint <= 0xFFFF) return new[] { (ushort)codepoint };
        var v = codepoint - 0x10000;
        return new[] { (ushort)(0xD800 + (v >> 10)), (ushort)(0xDC00 + (v & 0x3FF)) };
    }

    /// <summary>Maps a pixel coordinate to SendInput's 0..65535 absolute range across [min, max].</summary>
    public static int ToAbsolute(double value, double min, double max)
    {
        var span = max - min;
        if (span <= 0) return 0;
        var n = (Math.Min(Math.Max(value, min), max) - min) / span * 65535.0;
        return (int)Math.Round(n);
    }

    /// <summary>Converts a scroll/zoom amount to a wheel delta (1 unit per pixel, sub-notch allowed), never 0 for non-zero input.</summary>
    public static int ToWheelDelta(double amount)
    {
        if (double.IsNaN(amount) || amount == 0) return 0;
        var r = (int)Math.Round(Math.Max(Math.Min(amount, 32000), -32000));
        return r != 0 ? r : (amount > 0 ? 1 : -1);
    }

    /// <summary>Wheel delta for a pinch magnitude (one notch per unit of magnitude).</summary>
    public static int ZoomToWheelDelta(double magnitude) => ToWheelDelta(magnitude * WheelDelta);
}
