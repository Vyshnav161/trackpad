using Agent.Core.Protocol;

namespace Agent.Mac;

/// <summary>
/// Pure mapping from protocol keys/modifiers to macOS virtual key codes
/// (Carbon HIToolbox kVK_* values) and CGEventFlags. No native calls.
/// </summary>
public static class MacKeyMap
{
    // CGEventFlags masks.
    public const ulong FlagShift = 0x00020000;
    public const ulong FlagControl = 0x00040000;
    public const ulong FlagAlternate = 0x00080000;
    public const ulong FlagCommand = 0x00100000;

    // Modifier virtual key codes.
    public const ushort VkCommand = 55;
    public const ushort VkShift = 56;
    public const ushort VkOption = 58;
    public const ushort VkControl = 59;

    public const ushort VkTab = 48;

    public static ushort ModifierKeyCode(Modifier m) => m switch
    {
        Modifier.Shift => VkShift,
        Modifier.Control => VkControl,
        Modifier.Alt => VkOption,
        Modifier.Platform => VkCommand,
        _ => throw new ArgumentOutOfRangeException(nameof(m)),
    };

    public static ulong ModifierFlag(Modifier m) => m switch
    {
        Modifier.Shift => FlagShift,
        Modifier.Control => FlagControl,
        Modifier.Alt => FlagAlternate,
        Modifier.Platform => FlagCommand,
        _ => throw new ArgumentOutOfRangeException(nameof(m)),
    };

    public static ushort SpecialKeyCode(SpecialKey key) => key switch
    {
        SpecialKey.Backspace => 51,
        SpecialKey.Enter => 36,
        SpecialKey.Tab => 48,
        SpecialKey.Escape => 53,
        SpecialKey.Delete => 117, // forward delete
        SpecialKey.ArrowLeft => 123,
        SpecialKey.ArrowRight => 124,
        SpecialKey.ArrowDown => 125,
        SpecialKey.ArrowUp => 126,
        SpecialKey.F1 => 122,
        SpecialKey.F2 => 120,
        SpecialKey.F3 => 99,
        SpecialKey.F4 => 118,
        SpecialKey.F5 => 96,
        SpecialKey.F6 => 97,
        SpecialKey.F7 => 98,
        SpecialKey.F8 => 100,
        SpecialKey.F9 => 101,
        SpecialKey.F10 => 109,
        SpecialKey.F11 => 103,
        SpecialKey.F12 => 111,
        _ => throw new ArgumentOutOfRangeException(nameof(key)),
    };

    private static readonly Dictionary<char, ushort> Ansi = new()
    {
        ['a'] = 0, ['s'] = 1, ['d'] = 2, ['f'] = 3, ['h'] = 4, ['g'] = 5,
        ['z'] = 6, ['x'] = 7, ['c'] = 8, ['v'] = 9, ['b'] = 11, ['q'] = 12,
        ['w'] = 13, ['e'] = 14, ['r'] = 15, ['y'] = 16, ['t'] = 17,
        ['1'] = 18, ['2'] = 19, ['3'] = 20, ['4'] = 21, ['6'] = 22, ['5'] = 23,
        ['='] = 24, ['9'] = 25, ['7'] = 26, ['-'] = 27, ['8'] = 28, ['0'] = 29,
        [']'] = 30, ['o'] = 31, ['u'] = 32, ['['] = 33, ['i'] = 34, ['p'] = 35,
        ['l'] = 37, ['j'] = 38, ['\''] = 39, ['k'] = 40, [';'] = 41,
        ['\\'] = 42, [','] = 43, ['/'] = 44, ['n'] = 45, ['m'] = 46,
        ['.'] = 47, [' '] = 49, ['`'] = 50,
    };

    /// <summary>
    /// ANSI-layout virtual key for an ASCII codepoint (letters case-folded).
    /// Needed so shortcuts such as Command+C resolve to the right key.
    /// </summary>
    public static bool TryGetAnsiKeyCode(int codepoint, out ushort keyCode)
    {
        keyCode = 0;
        if (codepoint < 0 || codepoint > 0x7F) return false;
        return Ansi.TryGetValue(char.ToLowerInvariant((char)codepoint), out keyCode);
    }

    /// <summary>
    /// True when the character should be injected via its virtual key code
    /// (shortcut semantics) instead of a Unicode string: Command or Control held
    /// and the character has an ANSI key.
    /// </summary>
    public static bool UseKeyCodeForChar(int codepoint, ulong flags, out ushort keyCode)
    {
        keyCode = 0;
        if ((flags & (FlagCommand | FlagControl)) == 0) return false;
        return TryGetAnsiKeyCode(codepoint, out keyCode);
    }

    /// <summary>UTF-16 code units for a Unicode scalar value; empty if invalid.</summary>
    public static ushort[] ToUtf16(int codepoint)
    {
        if (codepoint < 0 || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
            return Array.Empty<ushort>();
        var s = char.ConvertFromUtf32(codepoint);
        var r = new ushort[s.Length];
        for (var i = 0; i < s.Length; i++) r[i] = s[i];
        return r;
    }
}
