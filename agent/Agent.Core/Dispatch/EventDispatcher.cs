using Agent.Core.Pairing;
using Agent.Core.Protocol;

namespace Agent.Core.Dispatch;

/// <summary>
/// Applies decoded <see cref="InputEvent"/>s from authenticated Connections to an
/// <see cref="IInputInjector"/>: Sensitivity scaling, display clamping, app-switch
/// mapping, and held-state tracking for release on close.
/// </summary>
public sealed class EventDispatcher
{
    private sealed class HeldState
    {
        public readonly HashSet<MouseButton> Buttons = new();
        public readonly HashSet<Modifier> Modifiers = new();
        public readonly HashSet<KeyId> Keys = new();
    }

    private readonly IInputInjector _injector;
    private readonly Func<Guid, bool> _isAuthenticated;
    private readonly Dictionary<Guid, HeldState> _held = new();
    private readonly object _lock = new();
    private double _sensitivity;

    public EventDispatcher(IInputInjector injector, Func<Guid, bool> isAuthenticated, double sensitivity = 1.0)
    {
        _injector = injector;
        _isAuthenticated = isAuthenticated;
        Sensitivity = sensitivity;
    }

    public EventDispatcher(IInputInjector injector, PairingAuthManager auth, double sensitivity = 1.0)
        : this(injector, auth.IsAuthenticated, sensitivity) { }

    /// <summary>Multiplier applied to pointer deltas; the most recent value is always used.</summary>
    public double Sensitivity
    {
        get { lock (_lock) return _sensitivity; }
        set
        {
            if (!double.IsFinite(value) || value <= 0)
                throw new ArgumentOutOfRangeException(nameof(value), "Sensitivity must be finite and > 0.");
            lock (_lock) _sensitivity = value;
        }
    }

    /// <summary>Held buttons/modifiers/keys currently tracked for a connection.</summary>
    public (int Buttons, int Modifiers, int Keys) HeldCount(Guid connectionId)
    {
        lock (_lock)
            return _held.TryGetValue(connectionId, out var h)
                ? (h.Buttons.Count, h.Modifiers.Count, h.Keys.Count)
                : (0, 0, 0);
    }

    /// <summary>Dispatch an event. Returns false if discarded (unauthenticated).</summary>
    public bool Dispatch(Guid connectionId, InputEvent evt)
    {
        lock (_lock)
        {
            if (!_isAuthenticated(connectionId)) return false;
            switch (evt)
            {
                case PointerMove m:
                    var (x, y) = _injector.Position;
                    var b = _injector.Bounds;
                    _injector.MoveTo(
                        b.ClampX(x + m.Dx * _sensitivity),
                        b.ClampY(y + m.Dy * _sensitivity));
                    break;
                case ButtonAction a:
                    var h = Held(connectionId);
                    if (a.Action == ButtonState.Down) { _injector.ButtonDown(a.Button); h.Buttons.Add(a.Button); }
                    else { _injector.ButtonUp(a.Button); h.Buttons.Remove(a.Button); }
                    break;
                case ClickAction c:
                    _injector.Click(c.Button, c.ClickCount);
                    break;
                case ScrollEvent s:
                    _injector.Scroll(s.Dx, s.Dy);
                    break;
                case AppSwitchEvent:
                    AppSwitch(Held(connectionId));
                    break;
                case KeyAction k:
                    Key(Held(connectionId), k);
                    break;
                // Heartbeat and unknown events have no injection effect.
            }
            return true;
        }
    }

    /// <summary>Release everything the connection holds. Call on close / heartbeat timeout.</summary>
    public void CloseConnection(Guid connectionId)
    {
        lock (_lock)
        {
            if (!_held.Remove(connectionId, out var h)) return;
            foreach (var key in h.Keys) _injector.KeyUp(key);
            foreach (var m in h.Modifiers) _injector.ModifierUp(m);
            foreach (var btn in h.Buttons) _injector.ButtonUp(btn);
        }
    }

    private HeldState Held(Guid id)
    {
        if (!_held.TryGetValue(id, out var h)) _held[id] = h = new HeldState();
        return h;
    }

    private void AppSwitch(HeldState h)
    {
        var mod = _injector.HostOS == HostOS.MacOS ? Modifier.Platform : Modifier.Alt;
        var tab = new SpecialKeyId(SpecialKey.Tab);
        var pressed = h.Modifiers.Add(mod);
        if (pressed) _injector.ModifierDown(mod);
        _injector.KeyDown(tab);
        _injector.KeyUp(tab);
        if (pressed) { _injector.ModifierUp(mod); h.Modifiers.Remove(mod); }
    }

    private void Key(HeldState h, KeyAction k)
    {
        if (k.Action == ButtonState.Down)
        {
            foreach (var m in k.Modifiers)
                if (h.Modifiers.Add(m)) _injector.ModifierDown(m);
            _injector.KeyDown(k.Key);
            h.Keys.Add(k.Key);
        }
        else
        {
            _injector.KeyUp(k.Key);
            h.Keys.Remove(k.Key);
            foreach (var m in k.Modifiers)
                if (h.Modifiers.Remove(m)) _injector.ModifierUp(m);
        }
    }
}
