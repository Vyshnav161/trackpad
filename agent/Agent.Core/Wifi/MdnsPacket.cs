using System.Buffers.Binary;
using System.Net;
using System.Text;
namespace Agent.Core.Wifi;

/// <summary>Minimal DNS wire-format helpers for the mDNS responder.</summary>
public static class MdnsPacket
{
    public const ushort TypeA = 1, TypePtr = 12, TypeTxt = 16, TypeSrv = 33, TypeAny = 255;
    public const string ServiceType = "_trackpad._tcp.local";

    public readonly record struct Question(string Name, ushort Type);

    /// <summary>Returns the questions of a DNS query packet, or an empty list for responses/garbage.</summary>
    public static List<Question> ParseQuestions(ReadOnlySpan<byte> p)
    {
        var result = new List<Question>();
        try
        {
            if (p.Length < 12) return result;
            if ((p[2] & 0x80) != 0) return result; // QR=1: a response
            int qd = BinaryPrimitives.ReadUInt16BigEndian(p[4..]);
            var pos = 12;
            for (var i = 0; i < qd; i++)
            {
                var name = ReadName(p, ref pos);
                if (pos + 4 > p.Length) return result;
                var type = BinaryPrimitives.ReadUInt16BigEndian(p[pos..]);
                pos += 4;
                result.Add(new Question(name, type));
            }
        }
        catch (ArgumentException) { }
        return result;
    }

    private static string ReadName(ReadOnlySpan<byte> p, ref int pos)
    {
        var labels = new List<string>();
        var cur = pos;
        var jumped = false;
        for (var hops = 0; hops < 32; hops++)
        {
            if (cur >= p.Length) throw new ArgumentException("truncated");
            int len = p[cur];
            if (len == 0)
            {
                if (!jumped) pos = cur + 1;
                return string.Join('.', labels);
            }
            if ((len & 0xC0) == 0xC0)
            {
                if (cur + 1 >= p.Length) throw new ArgumentException("truncated");
                var ptr = ((len & 0x3F) << 8) | p[cur + 1];
                if (!jumped) pos = cur + 2;
                jumped = true;
                cur = ptr;
                continue;
            }
            if (cur + 1 + len > p.Length) throw new ArgumentException("truncated");
            labels.Add(Encoding.UTF8.GetString(p.Slice(cur + 1, len)));
            cur += 1 + len;
        }
        throw new ArgumentException("name loop");
    }

    private static void WriteName(List<byte> o, string name)
    {
        foreach (var label in name.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            var b = Encoding.UTF8.GetBytes(label);
            if (b.Length > 63) b = b[..63];
            o.Add((byte)b.Length);
            o.AddRange(b);
        }
        o.Add(0);
    }

    private static void U16(List<byte> o, int v) { o.Add((byte)(v >> 8)); o.Add((byte)v); }
    private static void U32(List<byte> o, uint v) { U16(o, (int)(v >> 16)); U16(o, (int)(v & 0xFFFF)); }

    private static void Record(List<byte> o, string name, ushort type, uint ttl, byte[] data, bool cacheFlush)
    {
        WriteName(o, name);
        U16(o, type);
        U16(o, cacheFlush ? 0x8001 : 1);
        U32(o, ttl);
        U16(o, data.Length);
        o.AddRange(data);
    }

    /// <summary>
    /// Builds an unsolicited/answer response with PTR, SRV, TXT and A records.
    /// <paramref name="ttl"/> 0 produces a "goodbye" packet.
    /// </summary>
    public static byte[] BuildResponse(string instance, string hostLabel, int port,
        IReadOnlyList<KeyValuePair<string, string>> txt, IReadOnlyList<IPAddress> v4, uint ttl)
    {
        var instanceFqdn = $"{instance}.{ServiceType}";
        var hostFqdn = $"{hostLabel}.local";
        var o = new List<byte>();
        U16(o, 0); U16(o, 0x8400); U16(o, 0); // id, QR+AA, no questions
        U16(o, 3 + v4.Count); U16(o, 0); U16(o, 0);

        var ptr = new List<byte>(); WriteName(ptr, instanceFqdn);
        Record(o, ServiceType, TypePtr, ttl, ptr.ToArray(), false);

        var srv = new List<byte>(); U16(srv, 0); U16(srv, 0); U16(srv, port); WriteName(srv, hostFqdn);
        Record(o, instanceFqdn, TypeSrv, ttl, srv.ToArray(), true);

        var t = new List<byte>();
        foreach (var kv in txt)
        {
            var s = Encoding.UTF8.GetBytes($"{kv.Key}={kv.Value}");
            if (s.Length > 255) s = s[..255];
            t.Add((byte)s.Length); t.AddRange(s);
        }
        if (t.Count == 0) t.Add(0);
        Record(o, instanceFqdn, TypeTxt, ttl, t.ToArray(), true);

        foreach (var a in v4) Record(o, hostFqdn, TypeA, ttl, a.GetAddressBytes(), true);
        return o.ToArray();
    }
}
