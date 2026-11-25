using System.Text.Json;
using Agent.Core.Protocol;

namespace Agent.Tests;

/// <summary>
/// Golden vectors generated from the Dart codec (lib/protocol). The same vectors
/// live in test/golden/codec_vectors.json.
/// </summary>
public class ProtocolCodecTests
{
    private static byte[] Hex(string s) => Convert.FromHexString(s);

    public static IEnumerable<object[]> Golden() => new[]
    {
        new object[] { new PointerMove(1.5, -2.25), "01013fc00000c0100000" },
        new object[] { new ButtonAction(MouseButton.Left, ButtonState.Down), "01020000" },
        new object[] { new ButtonAction(MouseButton.Right, ButtonState.Up), "01020101" },
        new object[] { new ClickAction(MouseButton.Left, 1), "01030001" },
        new object[] { new ClickAction(MouseButton.Right, 2), "01030102" },
        new object[] { new ScrollEvent(0.0, 3.0), "01040000000040400000" },
        new object[] { new ZoomEvent(-0.5), "0105bf000000" },
        new object[] { new AppSwitchEvent(), "0106" },
        new object[] { new KeyAction(new CharKey(0x41), Array.Empty<Modifier>(), ButtonState.Down), "010700000000000041" },
        new object[] { new KeyAction(new CharKey(0x1F600), new[] { Modifier.Shift, Modifier.Platform }, ButtonState.Up), "01070109000001f600" },
        new object[] { new KeyAction(new SpecialKeyId(SpecialKey.Enter), new[] { Modifier.Control, Modifier.Alt }, ButtonState.Down), "010700060101" },
        new object[] { new KeyAction(new SpecialKeyId(SpecialKey.F12), new[] { Modifier.Shift, Modifier.Control, Modifier.Alt, Modifier.Platform }, ButtonState.Up), "0107010f0114" },
        new object[] { new Heartbeat(), "0108" },
    };

    [Theory]
    [MemberData(nameof(Golden))]
    public void Encode_MatchesDartBytes(InputEvent e, string hex) =>
        Assert.Equal(Hex(hex), ProtocolCodec.Encode(e));

    [Theory]
    [MemberData(nameof(Golden))]
    public void Decode_ReturnsEvent(InputEvent e, string hex)
    {
        var r = Assert.IsType<DecodeOk>(ProtocolCodec.Decode(Hex(hex)));
        Assert.Equal(e, r.Event);
    }

    [Fact]
    public void SharedJsonVectors_MatchEncodeDecodeFrameAndPretty()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "golden", "codec_vectors.json")));
        var root = doc.RootElement;
        Assert.Equal(Framing.MaxFrameSize, root.GetProperty("maxFrameSize").GetInt32());

        foreach (var v in root.GetProperty("events").EnumerateArray())
        {
            var bytes = Hex(v.GetProperty("hex").GetString()!);
            var r = Assert.IsType<DecodeOk>(ProtocolCodec.Decode(bytes));
            Assert.Equal(bytes, ProtocolCodec.Encode(r.Event));
            Assert.Equal(v.GetProperty("pretty").GetString(), ProtocolCodec.PrettyPrint(r.Event));
            Assert.Equal(Hex(v.GetProperty("frameHex").GetString()!), Framing.EncodeFrame(bytes));
        }

        foreach (var v in root.GetProperty("errors").EnumerateArray())
        {
            var r = Assert.IsType<DecodeErr>(ProtocolCodec.Decode(Hex(v.GetProperty("hex").GetString()!)));
            var kind = v.GetProperty("kind").GetString();
            Assert.Equal(kind == "malformed" ? typeof(Malformed) : typeof(VersionMismatch), r.Error.GetType());
            Assert.Equal(v.GetProperty("message").GetString(), ProtocolCodec.PrettyPrintError(r.Error));
        }
    }

    [Fact]
    public void Encode_RejectsInvariantViolations()
    {
        Assert.Throws<ArgumentException>(() => ProtocolCodec.Encode(new PointerMove(double.NaN, 0)));
        Assert.Throws<ArgumentException>(() => ProtocolCodec.Encode(new ClickAction(MouseButton.Left, 3)));
        Assert.Throws<ArgumentException>(() => ProtocolCodec.Encode(new KeyAction(new CharKey(0xD800), Array.Empty<Modifier>(), ButtonState.Down)));
    }

    [Fact]
    public void FrameDecoder_ReassemblesSplitAndCoalescedChunks()
    {
        var a = Framing.EncodeFrame(Hex("0108"));
        var b = Framing.EncodeFrame(Hex("01020000"));
        var all = a.Concat(b).ToArray();
        var d = new FrameDecoder();
        var frames = new List<byte[]>();
        foreach (var x in all) frames.AddRange(d.Add(new[] { x }));
        Assert.Equal(2, frames.Count);
        Assert.Equal(Hex("0108"), frames[0]);
        Assert.Equal(Hex("01020000"), frames[1]);
        Assert.Equal(2, new FrameDecoder().Add(all).Count);
    }

    [Fact]
    public void FrameDecoder_OversizedLengthSetsCorrupted()
    {
        var d = new FrameDecoder();
        Assert.Empty(d.Add(Hex("00010001")));
        Assert.True(d.Corrupted);
        Assert.Empty(d.Add(Hex("0000000201080000")));
    }
}
