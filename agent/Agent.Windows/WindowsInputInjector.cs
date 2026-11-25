using System.Runtime.InteropServices;
using Agent.Core.Dispatch;
using Agent.Core.Protocol;

namespace Agent.Windows;

/// <summary>Windows <see cref="IInputInjector"/> using user32 SendInput.</summary>
public sealed class WindowsInputInjector : IInputInjector
{
    private const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    private const uint MOUSEEVENTF_MOVE = 0x0001, MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004,
        MOUSEEVENTF_RIGHTDOWN = 0x0008, MOUSEEVENTF_RIGHTUP = 0x0010, MOUSEEVENTF_WHEEL = 0x0800,
        MOUSEEVENTF_HWHEEL = 0x1000, MOUSEEVENTF_VIRTUALDESK = 0x4000, MOUSEEVENTF_ABSOLUTE = 0x8000;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001, KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004;
    private const int SM_XVIRTUALSCREEN = 76, SM_YVIRTUALSCREEN = 77, SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk, wScan;
        public uint dwFlags, time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out POINT lpPoint);

    private readonly HashSet<Modifier> _heldModifiers = new();

    public HostOS HostOS => HostOS.Windows;

    public DisplayBounds Bounds
    {
        get
        {
            var x = GetSystemMetrics(SM_XVIRTUALSCREEN);
            var y = GetSystemMetrics(SM_YVIRTUALSCREEN);
            var w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
            var h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
            return new DisplayBounds(x, y, x + Math.Max(w, 1) - 1, y + Math.Max(h, 1) - 1);
        }
    }

    public (double X, double Y) Position => GetCursorPos(out var p) ? (p.X, p.Y) : (0, 0);

    public void MoveTo(double x, double y)
    {
        var b = Bounds;
        Send(Mouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
            WindowsKeyMap.ToAbsolute(x, b.MinX, b.MaxX), WindowsKeyMap.ToAbsolute(y, b.MinY, b.MaxY), 0));
    }

    public void ButtonDown(MouseButton button) =>
        Send(Mouse(button == MouseButton.Left ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_RIGHTDOWN, 0, 0, 0));

    public void ButtonUp(MouseButton button) =>
        Send(Mouse(button == MouseButton.Left ? MOUSEEVENTF_LEFTUP : MOUSEEVENTF_RIGHTUP, 0, 0, 0));

    public void Click(MouseButton button, int clickCount)
    {
        for (var i = 0; i < Math.Max(clickCount, 1); i++)
        {
            ButtonDown(button);
            ButtonUp(button);
        }
    }

    public void ModifierDown(Modifier modifier)
    {
        _heldModifiers.Add(modifier);
        Send(Key(WindowsKeyMap.GetModifierVirtualKey(modifier), 0, 0));
    }

    public void ModifierUp(Modifier modifier)
    {
        _heldModifiers.Remove(modifier);
        Send(Key(WindowsKeyMap.GetModifierVirtualKey(modifier), 0, KEYEVENTF_KEYUP));
    }

    public void KeyDown(KeyId key) => SendKey(key, false);

    public void KeyUp(KeyId key) => SendKey(key, true);

    /// <summary>Positive dy scrolls down, positive dx scrolls right.</summary>
    public void Scroll(double dx, double dy)
    {
        var v = WindowsKeyMap.ToWheelDelta(dy);
        var h = WindowsKeyMap.ToWheelDelta(dx);
        // Wheel: positive = away from user (up), so invert dy.
        if (v != 0) Send(Mouse(MOUSEEVENTF_WHEEL, 0, 0, -v));
        if (h != 0) Send(Mouse(MOUSEEVENTF_HWHEEL, 0, 0, h));
    }

    private void SendKey(KeyId key, bool up)
    {
        var upFlag = up ? KEYEVENTF_KEYUP : 0u;
        switch (key)
        {
            case SpecialKeyId s:
            {
                var vk = WindowsKeyMap.GetVirtualKey(s.Key, out var ext);
                Send(Key(vk, 0, upFlag | (ext ? KEYEVENTF_EXTENDEDKEY : 0u)));
                break;
            }
            case CharKey c:
            {
                var shortcutMods = _heldModifiers.Contains(Modifier.Control)
                    || _heldModifiers.Contains(Modifier.Alt) || _heldModifiers.Contains(Modifier.Platform);
                var vk = shortcutMods ? WindowsKeyMap.GetCharVirtualKey(c.Codepoint) : null;
                if (vk is { } v)
                {
                    Send(Key(v, 0, upFlag));
                    break;
                }
                var units = WindowsKeyMap.ToUtf16(c.Codepoint);
                var inputs = new INPUT[units.Length];
                for (var i = 0; i < units.Length; i++)
                    inputs[i] = Key(0, units[i], KEYEVENTF_UNICODE | upFlag);
                Send(inputs);
                break;
            }
            default:
                throw new ArgumentException("Unknown key", nameof(key));
        }
    }

    private static INPUT Mouse(uint flags, int dx, int dy, int data) => new()
    {
        type = INPUT_MOUSE,
        u = new InputUnion { mi = new MOUSEINPUT { dx = dx, dy = dy, mouseData = unchecked((uint)data), dwFlags = flags } },
    };

    private static INPUT Key(ushort vk, ushort scan, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, wScan = scan, dwFlags = flags } },
    };

    private static void Send(params INPUT[] inputs)
    {
        if (inputs.Length == 0) return;
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }
}
