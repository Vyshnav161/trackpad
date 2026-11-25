using System.Runtime.InteropServices;
using Agent.Core.Dispatch;
using Agent.Core.Protocol;

namespace Agent.Mac;

/// <summary>
/// macOS injector using CGEventPost (requires Accessibility permission).
/// </summary>
public sealed class MacInputInjector : IInputInjector
{
    private const string CoreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics";
    private const string CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";

    private const uint KCGHIDEventTap = 0;
    private const uint KCGEventLeftMouseDown = 1;
    private const uint KCGEventLeftMouseUp = 2;
    private const uint KCGEventRightMouseDown = 3;
    private const uint KCGEventRightMouseUp = 4;
    private const uint KCGEventMouseMoved = 5;
    private const uint KCGEventLeftMouseDragged = 6;
    private const uint KCGEventRightMouseDragged = 7;
    private const uint KCGMouseButtonLeft = 0;
    private const uint KCGMouseButtonRight = 1;
    private const uint KCGScrollEventUnitPixel = 0;
    private const uint KCGMouseEventClickState = 1;

    [StructLayout(LayoutKind.Sequential)]
    private struct CGPoint { public double X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct CGSize { public double Width, Height; }

    [StructLayout(LayoutKind.Sequential)]
    private struct CGRect { public CGPoint Origin; public CGSize Size; }

    [DllImport(CoreGraphics)] private static extern IntPtr CGEventCreate(IntPtr source);
    [DllImport(CoreGraphics)] private static extern CGPoint CGEventGetLocation(IntPtr ev);
    [DllImport(CoreGraphics)] private static extern IntPtr CGEventCreateMouseEvent(IntPtr source, uint type, CGPoint pos, uint button);
    [DllImport(CoreGraphics)] private static extern IntPtr CGEventCreateKeyboardEvent(IntPtr source, ushort virtualKey, [MarshalAs(UnmanagedType.I1)] bool keyDown);
    [DllImport(CoreGraphics)] private static extern void CGEventKeyboardSetUnicodeString(IntPtr ev, nuint length, ushort[] chars);
    [DllImport(CoreGraphics)] private static extern IntPtr CGEventCreateScrollWheelEvent2(IntPtr source, uint units, uint wheelCount, int w1, int w2, int w3);
    [DllImport(CoreGraphics)] private static extern void CGEventSetIntegerValueField(IntPtr ev, uint field, long value);
    [DllImport(CoreGraphics)] private static extern void CGEventSetFlags(IntPtr ev, ulong flags);
    [DllImport(CoreGraphics)] private static extern void CGEventPost(uint tap, IntPtr ev);
    [DllImport(CoreGraphics)] private static extern uint CGMainDisplayID();
    [DllImport(CoreGraphics)] private static extern CGRect CGDisplayBounds(uint display);
    [DllImport(CoreFoundation)] private static extern void CFRelease(IntPtr obj);

    private readonly object _lock = new();
    private ulong _flags;
    private bool _leftHeld;
    private bool _rightHeld;

    public HostOS HostOS => HostOS.MacOS;

    public DisplayBounds Bounds
    {
        get
        {
            var r = CGDisplayBounds(CGMainDisplayID());
            // Inclusive pixel bounds: last addressable pixel is size - 1.
            return new DisplayBounds(
                r.Origin.X, r.Origin.Y,
                r.Origin.X + Math.Max(r.Size.Width - 1, 0),
                r.Origin.Y + Math.Max(r.Size.Height - 1, 0));
        }
    }

    public (double X, double Y) Position
    {
        get
        {
            var ev = CGEventCreate(IntPtr.Zero);
            if (ev == IntPtr.Zero) return (0, 0);
            try
            {
                var p = CGEventGetLocation(ev);
                return (p.X, p.Y);
            }
            finally { CFRelease(ev); }
        }
    }

    private void Post(IntPtr ev, bool applyFlags = true)
    {
        if (ev == IntPtr.Zero) return;
        try
        {
            if (applyFlags) CGEventSetFlags(ev, _flags);
            CGEventPost(KCGHIDEventTap, ev);
        }
        finally { CFRelease(ev); }
    }

    private void PostMouse(uint type, double x, double y, uint button, int clickState = 0)
    {
        var ev = CGEventCreateMouseEvent(IntPtr.Zero, type, new CGPoint { X = x, Y = y }, button);
        if (ev == IntPtr.Zero) return;
        if (clickState > 0) CGEventSetIntegerValueField(ev, KCGMouseEventClickState, clickState);
        Post(ev);
    }

    public void MoveTo(double x, double y)
    {
        lock (_lock)
        {
            var b = Bounds;
            x = b.ClampX(x);
            y = b.ClampY(y);
            if (_leftHeld) PostMouse(KCGEventLeftMouseDragged, x, y, KCGMouseButtonLeft);
            else if (_rightHeld) PostMouse(KCGEventRightMouseDragged, x, y, KCGMouseButtonRight);
            else PostMouse(KCGEventMouseMoved, x, y, KCGMouseButtonLeft);
        }
    }

    public void ButtonDown(MouseButton button)
    {
        lock (_lock) { ButtonCore(button, down: true, clickState: 1); }
    }

    public void ButtonUp(MouseButton button)
    {
        lock (_lock) { ButtonCore(button, down: false, clickState: 1); }
    }

    private void ButtonCore(MouseButton button, bool down, int clickState)
    {
        var (x, y) = Position;
        if (button == MouseButton.Left)
        {
            _leftHeld = down;
            PostMouse(down ? KCGEventLeftMouseDown : KCGEventLeftMouseUp, x, y, KCGMouseButtonLeft, clickState);
        }
        else
        {
            _rightHeld = down;
            PostMouse(down ? KCGEventRightMouseDown : KCGEventRightMouseUp, x, y, KCGMouseButtonRight, clickState);
        }
    }

    public void Click(MouseButton button, int clickCount)
    {
        lock (_lock)
        {
            var count = Math.Max(1, clickCount);
            // Each down/up pair carries an increasing click state so apps see a double-click.
            for (var i = 1; i <= count; i++)
            {
                ButtonCore(button, down: true, clickState: i);
                ButtonCore(button, down: false, clickState: i);
            }
        }
    }

    public void ModifierDown(Modifier modifier)
    {
        lock (_lock)
        {
            _flags |= MacKeyMap.ModifierFlag(modifier);
            PostModifier(modifier, true);
            if (modifier == Modifier.Platform) Thread.Sleep(30);
        }
    }

    public void ModifierUp(Modifier modifier)
    {
        lock (_lock)
        {
            _flags &= ~MacKeyMap.ModifierFlag(modifier);
            if (modifier == Modifier.Platform) Thread.Sleep(30);
            PostModifier(modifier, false);
        }
    }

    private void PostModifier(Modifier modifier, bool down)
    {
        Post(CGEventCreateKeyboardEvent(IntPtr.Zero, MacKeyMap.ModifierKeyCode(modifier), down));
    }

    public void KeyDown(KeyId key) { lock (_lock) { PostKey(key, true); } }

    public void KeyUp(KeyId key) { lock (_lock) { PostKey(key, false); } }

    private void PostKey(KeyId key, bool down)
    {
        switch (key)
        {
            case SpecialKeyId s:
                // The Command+Tab switcher is driven by the WindowServer, which drops
                // the Tab press when it arrives in the same instant as Command.
                if (s.Key == SpecialKey.Tab && (_flags & MacKeyMap.FlagCommand) != 0)
                    Thread.Sleep(down ? 30 : 60);
                Post(CGEventCreateKeyboardEvent(IntPtr.Zero, MacKeyMap.SpecialKeyCode(s.Key), down));
                break;
            case CharKey c:
                if (MacKeyMap.UseKeyCodeForChar(c.Codepoint, _flags, out var code))
                {
                    Post(CGEventCreateKeyboardEvent(IntPtr.Zero, code, down));
                    break;
                }
                var units = MacKeyMap.ToUtf16(c.Codepoint);
                if (units.Length == 0) break;
                var ev = CGEventCreateKeyboardEvent(IntPtr.Zero, 0, down);
                if (ev == IntPtr.Zero) break;
                CGEventKeyboardSetUnicodeString(ev, (nuint)units.Length, units);
                Post(ev);
                break;
        }
    }

    public void Scroll(double dx, double dy)
    {
        lock (_lock)
        {
            var ix = (int)Math.Round(dx);
            var iy = (int)Math.Round(dy);
            if (ix == 0 && iy == 0) return;
            // Wheel 1 is vertical, wheel 2 horizontal. CoreGraphics treats positive as
            // up / left, the opposite of the IInputInjector contract (positive dy = down,
            // positive dx = right), so both axes are negated.
            Post(CGEventCreateScrollWheelEvent2(IntPtr.Zero, KCGScrollEventUnitPixel, 2, -iy, -ix, 0));
        }
    }

}
