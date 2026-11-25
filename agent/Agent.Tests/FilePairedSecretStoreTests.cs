using Agent.Core.Pairing;
using Xunit;

namespace Agent.Tests;

public class FilePairedSecretStoreTests
{
    [Fact]
    public void SavedSecretSurvivesRestartAndIsRecognisedAsPairedHost()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "paired.txt");
        try
        {
            var secret = new byte[32];
            for (var i = 0; i < secret.Length; i++) secret[i] = (byte)i;
            var fp = SecretFingerprint.Compute(secret);

            new FilePairedSecretStore(path).SaveSecret(secret);

            var reloaded = new FilePairedSecretStore(path);
            Assert.True(reloaded.Contains(fp));
            Assert.Equal(secret, reloaded.TryGetSecret(fp));

            reloaded.Remove(fp);
            var afterRemove = new FilePairedSecretStore(path);
            Assert.False(afterRemove.Contains(fp));
            Assert.Null(afterRemove.TryGetSecret(fp));
        }
        finally
        {
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }
}
