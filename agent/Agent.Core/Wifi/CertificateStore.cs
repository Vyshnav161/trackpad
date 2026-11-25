using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Org.BouncyCastle.Asn1.X509;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Operators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Math;
using Org.BouncyCastle.Pkcs;
using Org.BouncyCastle.Security;
using Org.BouncyCastle.X509;
namespace Agent.Core.Wifi;

/// <summary>Creates the agent's self-signed TLS certificate on first run and persists it as a PFX.</summary>
/// <remarks>
/// Generated with BouncyCastle: <c>CertificateRequest.CreateSelfSigned</c> needs keychain
/// access on macOS and fails when it is unavailable, whereas loading a PFX does not.
/// </remarks>
public static class CertificateStore
{
    private const X509KeyStorageFlags Flags = X509KeyStorageFlags.Exportable;

    public static string DefaultPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TrackpadAgent", "tls.pfx");

    /// <summary>Loads the certificate at <paramref name="path"/>, creating it if missing or unreadable.</summary>
    public static X509Certificate2 LoadOrCreate(string path, string subjectName)
    {
        if (File.Exists(path))
        {
            try
            {
                var c = new X509Certificate2(path, (string?)null, Flags);
                if (c.HasPrivateKey && c.NotAfter > DateTime.UtcNow.AddDays(7)) return c;
                c.Dispose();
            }
            catch (CryptographicException) { }
        }
        var pfx = CreatePfx(subjectName);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllBytes(path, pfx);
        try
        {
            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
        catch { }
        return new X509Certificate2(pfx, (string?)null, Flags);
    }

    private static byte[] CreatePfx(string subjectName)
    {
        var random = new SecureRandom();
        var kpg = new RsaKeyPairGenerator();
        kpg.Init(new KeyGenerationParameters(random, 2048));
        var pair = kpg.GenerateKeyPair();
        var subject = new X509Name("CN=" + subjectName.Replace(",", " "));
        var gen = new X509V3CertificateGenerator();
        gen.SetSerialNumber(BigInteger.ProbablePrime(120, random));
        gen.SetIssuerDN(subject);
        gen.SetSubjectDN(subject);
        gen.SetNotBefore(DateTime.UtcNow.AddDays(-1));
        gen.SetNotAfter(DateTime.UtcNow.AddYears(10));
        gen.SetPublicKey(pair.Public);
        gen.AddExtension(X509Extensions.BasicConstraints, true, new BasicConstraints(false));
        gen.AddExtension(X509Extensions.ExtendedKeyUsage, false, new ExtendedKeyUsage(KeyPurposeID.id_kp_serverAuth));
        var cert = gen.Generate(new Asn1SignatureFactory("SHA256WITHRSA", pair.Private, random));

        var store = new Pkcs12StoreBuilder().Build();
        store.SetKeyEntry("trackpad", new AsymmetricKeyEntry(pair.Private), new[] { new X509CertificateEntry(cert) });
        using var ms = new MemoryStream();
        store.Save(ms, Array.Empty<char>(), random);
        return ms.ToArray();
    }
}
