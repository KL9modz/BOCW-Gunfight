using System.IO;
using System.Net.Http;
using System.Windows.Media.Imaging;
using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>
/// The map pictures under the spawn plot. Wiki art is fetched once (1920 px wide PNG) into
/// %LOCALAPPDATA%\GfPanel\mapart and read from there after; a user-picked image is read in place. Nothing
/// is written to the repo or shipped in the bundle - the pictures are the wiki's, fetched by each panel.
/// </summary>
public sealed class MapArtCache
{
    private static readonly HttpClient Http = CreateClient();
    private readonly Dictionary<string, BitmapSource> _mem = new(StringComparer.OrdinalIgnoreCase);
    public string Dir { get; } = Path.Combine(App.DataDir, "mapart");

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(45) };
        // the CDN answers a browser; a bare client gets refused (measured with curl 2026-09-22)
        c.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36");
        c.DefaultRequestHeaders.Accept.ParseAdd("image/png,image/*;q=0.8");
        return c;
    }

    public bool IsCached(MapArtDef art) => art.Custom != null ? File.Exists(art.Custom) : File.Exists(LocalPath(art));

    private string LocalPath(MapArtDef art) => Path.Combine(Dir, art.File.Replace(' ', '_'));

    /// <summary>The picture, downloading it the first time. Throws on a network / decode failure.</summary>
    public async Task<BitmapSource> GetAsync(MapArtDef art)
    {
        var path = art.Custom ?? LocalPath(art);
        if (_mem.TryGetValue(path, out var hit)) return hit;
        if (art.Custom == null && !File.Exists(path))
        {
            Directory.CreateDirectory(Dir);
            var bytes = await Http.GetByteArrayAsync(MapArt.Url(art.File, 1920));
            if (bytes.Length < 1024 || bytes[0] != 0x89 || bytes[1] != 0x50 || bytes[2] != 0x4E || bytes[3] != 0x47)
                throw new InvalidDataException($"the wiki did not return a PNG for {art.File} ({bytes.Length} bytes)");
            var tmp = path + ".tmp";
            await File.WriteAllBytesAsync(tmp, bytes);
            File.Move(tmp, path, true);
        }
        var bmp = new BitmapImage();
        bmp.BeginInit();
        bmp.CacheOption = BitmapCacheOption.OnLoad;       // read now, keep no file handle
        bmp.UriSource = new Uri(path);
        bmp.EndInit();
        bmp.Freeze();
        _mem[path] = bmp;
        return bmp;
    }
}
