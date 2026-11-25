using System.Buffers.Binary;
using System.Globalization;

namespace Agent.Core.Protocol;

/// <summary>
/// Binary wire format: <c>[version u8][type u8][payload]</c>, big-endian.
/// Mirrors lib/protocol/protocol_codec.dart exactly (see that file for the
/// per-type payload layout).
/// </summary>
public static class ProtocolCodec
{
    public const int Version = 1;

    private static bool IsSupportedVersion(int v) => v == Version;

    private const byte TPointerMove = 0x01;
    private const byte TButton = 0x02;
    private const byte TClick = 0x03;
    private const byte TScroll = 0x04;
    private const byte TZoom = 0x05;
    private const byte TAppSwitch = 0x06;
    private const byte TKey = 0x07;
    private const byte THeartbeat = 0x08;

    /// <summary>
    /// Serializes <paramref name="e"/>. Throws <see cref="ArgumentException"/> only for
    /// events that violate the type's invariants (non-finite floats, bad click
    /// count or codepoint).
    /// </summary>
    public static byte[] Encode(InputEvent e)
    {
        var b = new List<byte> { Version };
        switch (e)
        {
            case PointerMove m:
                b.Add(TPointerMove);
                F32(b, m.Dx);
                F32(b, m.Dy);
                break;
            case ButtonAction a:
                b.Add(TButton);
                b.Add((byte)a.Button);
                b.Add((byte)a.Action);
                break;
            case ClickAction c:
                if (c.ClickCount != 1 && c.ClickCount != 2)
                    throw new ArgumentException("clickCount must be 1 or 2", nameof(e));
                b.Add(TClick);
                b.Add((byte)c.Button);
                b.Add((byte)c.ClickCount);
                break;
            case ScrollEvent s:
                b.Add(TScroll);
                F32(b, s.Dx);
                F32(b, s.Dy);
                break;
            case ZoomEvent z:
                b.Add(TZoom);
                F32(b, z.Magnitude);
                break;
            case AppSwitchEvent:
                b.Add(TAppSwitch);
                break;
            case KeyAction k:
                b.Add(TKey);
                b.Add((byte)k.Action);
                var mask = 0;
                foreach (var m in k.Modifiers) mask |= 1 << (int)m;
                b.Add((byte)mask);
                switch (k.Key)
                {
                    case CharKey ck:
                        if (!ValidCodepoint(ck.Codepoint))
                            throw new ArgumentException("invalid codepoint", nameof(e));
                        b.Add(0);
                        var cp = new byte[4];
                        BinaryPrimitives.WriteUInt32BigEndian(cp, (uint)ck.Codepoint);
                        b.AddRange(cp);
                        break;
                    case SpecialKeyId sk:
                        b.Add(1);
                        b.Add((byte)sk.Key);
                        break;
                    default:
                        throw new ArgumentException("unknown key id", nameof(e));
                }
                break;
            case Heartbeat:
                b.Add(THeartbeat);
                break;
            default:
                throw new ArgumentException("unknown event", nameof(e));
        }
        return b.ToArray();
    }

    /// <summary>Parses <paramref name="bytes"/>. Never throws.</summary>
    public static DecodeResult Decode(ReadOnlySpan<byte> bytes)
    {
        try
        {
            return DecodeCore(bytes);
        }
        catch (Exception ex)
        {
            return new DecodeErr(new Malformed($"unexpected decode failure: {ex.Message}"));
        }
    }

    private static DecodeErr Bad(string why) => new(new Malformed(why));

    private static DecodeErr? ExpectLen(int len, int n, string name) =>
        len == n ? null : Bad($"{name} payload must be {n} bytes, got {len}");

    private static DecodeResult DecodeCore(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 2)
            return Bad($"message too short: {bytes.Length} bytes");
        int v = bytes[0];
        if (!IsSupportedVersion(v))
            return new DecodeErr(new VersionMismatch(v, Version));
        var type = bytes[1];
        var len = bytes.Length - 2;

        switch (type)
        {
            case TPointerMove:
            {
                if (ExpectLen(len, 8, "PointerMove") is { } err) return err;
                double dx = BinaryPrimitives.ReadSingleBigEndian(bytes[2..]);
                double dy = BinaryPrimitives.ReadSingleBigEndian(bytes[6..]);
                if (!double.IsFinite(dx) || !double.IsFinite(dy)) return Bad("non-finite float");
                return new DecodeOk(new PointerMove(dx, dy));
            }
            case TButton:
            {
                if (ExpectLen(len, 2, "ButtonAction") is { } err) return err;
                if (bytes[2] > (int)MouseButton.Right) return Bad($"unknown button {bytes[2]}");
                if (bytes[3] > (int)ButtonState.Up) return Bad($"unknown button state {bytes[3]}");
                return new DecodeOk(new ButtonAction((MouseButton)bytes[2], (ButtonState)bytes[3]));
            }
            case TClick:
            {
                if (ExpectLen(len, 2, "ClickAction") is { } err) return err;
                if (bytes[2] > (int)MouseButton.Right) return Bad($"unknown button {bytes[2]}");
                int count = bytes[3];
                if (count != 1 && count != 2) return Bad($"invalid click count {count}");
                return new DecodeOk(new ClickAction((MouseButton)bytes[2], count));
            }
            case TScroll:
            {
                if (ExpectLen(len, 8, "ScrollEvent") is { } err) return err;
                double dx = BinaryPrimitives.ReadSingleBigEndian(bytes[2..]);
                double dy = BinaryPrimitives.ReadSingleBigEndian(bytes[6..]);
                if (!double.IsFinite(dx) || !double.IsFinite(dy)) return Bad("non-finite float");
                return new DecodeOk(new ScrollEvent(dx, dy));
            }
            case TZoom:
            {
                if (ExpectLen(len, 4, "ZoomEvent") is { } err) return err;
                double m = BinaryPrimitives.ReadSingleBigEndian(bytes[2..]);
                if (!double.IsFinite(m)) return Bad("non-finite float");
                return new DecodeOk(new ZoomEvent(m));
            }
            case TAppSwitch:
            {
                if (ExpectLen(len, 0, "AppSwitchEvent") is { } err) return err;
                return new DecodeOk(new AppSwitchEvent());
            }
            case TKey:
                return DecodeKey(bytes, len);
            case THeartbeat:
            {
                if (ExpectLen(len, 0, "Heartbeat") is { } err) return err;
                return new DecodeOk(new Heartbeat());
            }
            default:
                return Bad($"unknown event type 0x{type:x}");
        }
    }

    private static DecodeResult DecodeKey(ReadOnlySpan<byte> bytes, int len)
    {
        if (len < 4) return Bad($"KeyAction payload too short: {len} bytes");
        if (bytes[2] > (int)ButtonState.Up) return Bad($"unknown key state {bytes[2]}");
        var st = (ButtonState)bytes[2];
        int mask = bytes[3];
        if ((mask & ~0x0F) != 0) return Bad($"unknown modifier bits {mask}");
        var mods = new List<Modifier>();
        foreach (var m in Enum.GetValues<Modifier>())
            if ((mask & (1 << (int)m)) != 0) mods.Add(m);
        int kind = bytes[4];
        switch (kind)
        {
            case 0:
            {
                if (len != 7) return Bad("char KeyAction payload must be 7 bytes");
                var cp = BinaryPrimitives.ReadUInt32BigEndian(bytes[5..]);
                if (cp > 0x10FFFF || !ValidCodepoint((int)cp)) return Bad($"invalid codepoint {cp}");
                return new DecodeOk(new KeyAction(new CharKey((int)cp), mods, st));
            }
            case 1:
            {
                if (len != 4) return Bad("special KeyAction payload must be 4 bytes");
                if (bytes[5] > (int)SpecialKey.F12) return Bad($"unknown special key {bytes[5]}");
                return new DecodeOk(new KeyAction(new SpecialKeyId((SpecialKey)bytes[5]), mods, st));
            }
            default:
                return Bad($"unknown key kind {kind}");
        }
    }

    /// <summary>Human-readable text for logging (same format as the Dart codec).</summary>
    public static string PrettyPrint(InputEvent e)
    {
        switch (e)
        {
            case PointerMove m:
                return $"PointerMove(dx: {Num(m.Dx)}, dy: {Num(m.Dy)})";
            case ButtonAction a:
                return $"ButtonAction(button: {Name(a.Button)}, action: {Name(a.Action)})";
            case ClickAction c:
                return $"ClickAction(button: {Name(c.Button)}, clickCount: {c.ClickCount})";
            case ScrollEvent s:
                return $"ScrollEvent(dx: {Num(s.Dx)}, dy: {Num(s.Dy)})";
            case ZoomEvent z:
                return $"ZoomEvent(magnitude: {Num(z.Magnitude)})";
            case AppSwitchEvent:
                return "AppSwitchEvent()";
            case KeyAction k:
            {
                var key = k.Key switch
                {
                    CharKey ck => $"char U+{ck.Codepoint.ToString("X").PadLeft(4, '0')}",
                    SpecialKeyId sk => $"special {Name(sk.Key)}",
                    _ => "unknown",
                };
                var names = k.Modifiers.Select(m => Name(m)).ToList();
                names.Sort(StringComparer.Ordinal);
                return $"KeyAction(key: {key}, modifiers: [{string.Join("+", names)}], action: {Name(k.Action)})";
            }
            case Heartbeat:
                return "Heartbeat()";
            default:
                return e.GetType().Name;
        }
    }

    /// <summary>Human-readable text for a decode failure.</summary>
    public static string PrettyPrintError(CodecError error) => error switch
    {
        Malformed m => $"Malformed message: {m.Reason}",
        VersionMismatch v => $"Version mismatch: found {v.Found}, supported {v.Supported}",
        _ => "Unknown codec error",
    };

    private static bool ValidCodepoint(int cp) =>
        cp >= 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF);

    private static void F32(List<byte> b, double v)
    {
        if (!double.IsFinite(v)) throw new ArgumentException("value must be finite");
        var d = new byte[4];
        BinaryPrimitives.WriteSingleBigEndian(d, (float)v);
        b.AddRange(d);
    }

    /// <summary>Lower-camel-case enum name, matching Dart's <c>Enum.name</c>.</summary>
    private static string Name<T>(T value) where T : struct, Enum
    {
        var s = value.ToString();
        return char.ToLowerInvariant(s[0]) + s[1..];
    }

    /// <summary>Formats a double the way Dart's <c>double.toString()</c> does for typical values.</summary>
    private static string Num(double d)
    {
        var s = d.ToString("R", CultureInfo.InvariantCulture);
        var ei = s.IndexOf('E');
        if (ei < 0)
            return s.Contains('.') ? s : s + ".0";
        var mant = s[..ei];
        var exp = int.Parse(s[(ei + 1)..], CultureInfo.InvariantCulture);
        if (exp >= 0 && exp < 21)
        {
            // Dart prints integers below 1e21 in full.
            var neg = mant.StartsWith('-');
            var digits = mant.TrimStart('-').Replace(".", "");
            var intLen = mant.TrimStart('-').IndexOf('.') is var p and >= 0 ? p : mant.TrimStart('-').Length;
            digits = digits.PadRight(intLen + exp, '0');
            return (neg ? "-" : "") + digits + ".0";
        }
        return $"{mant}e{(exp < 0 ? "-" : "+")}{Math.Abs(exp)}";
    }
}
