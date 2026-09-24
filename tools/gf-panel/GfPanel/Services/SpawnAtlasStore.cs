using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>How one picture sits on one map, on top of the game's minimap frame: a shift (world units along
/// the map's east / north), a scale and a turn about the frame's centre. All zero / 1 = the frame exactly.
/// Custom = a picture file the user chose instead of the wiki art.</summary>
public sealed class ArtAlign
{
    public double Dx { get; set; }
    public double Dy { get; set; }
    public double Scale { get; set; } = 1;
    public double Rot { get; set; }
    public ArtAlign Copy() => new() { Dx = Dx, Dy = Dy, Scale = Scale, Rot = Rot };
    public bool IsIdentity => Math.Abs(Dx) < 0.01 && Math.Abs(Dy) < 0.01 && Math.Abs(Scale - 1) < 1e-6 && Math.Abs(Rot) < 1e-6;
}

/// <summary>The art state of all maps (art-align.json): the chosen picture per map and each picture's alignment.</summary>
public sealed class ArtState
{
    /// <summary>map -> the chosen picture: a wiki file name, "custom:&lt;path&gt;", or "none".</summary>
    public Dictionary<string, string> Chosen { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>"&lt;map&gt;|&lt;picture&gt;" -> its alignment.</summary>
    public Dictionary<string, ArtAlign> Align { get; set; } = new(StringComparer.OrdinalIgnoreCase);
}

/// <summary>
/// The spawn atlas on disk: one &lt;map&gt;.json per scanned map + picks.json (the per-map spawn picks).
/// On the dev box the files live in the repo (docs/data/spawns - versioned, and the bundle ships them);
/// a friend's bundle writes to %LOCALAPPDATA%\GfPanel\spawns and reads the bundle's spawns\ too.
/// Written atomically (temp + rename): the panel is killed routinely.
/// </summary>
public sealed class SpawnAtlasStore
{
    private static readonly JsonSerializerOptions Opts = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingDefault,
    };

    private readonly List<string> _dirs = new();
    public string WriteDir { get; }
    public Dictionary<string, SpawnPick> Picks { get; private set; } = new(StringComparer.OrdinalIgnoreCase);
    public ArtState Art { get; private set; } = new();
    private readonly Dictionary<string, SpawnAtlas?> _cache = new(StringComparer.OrdinalIgnoreCase);

    public SpawnAtlasStore()
    {
        if (App.RepoDir != null) _dirs.Add(Path.Combine(App.RepoDir, "docs", "data", "spawns"));
        _dirs.Add(Path.Combine(App.DataDir, "spawns"));
        _dirs.Add(Path.Combine(App.BaseDir, "spawns"));
        WriteDir = _dirs[0];
        try { Directory.CreateDirectory(WriteDir); } catch { }
        LoadPicks();
        LoadArt();
    }

    private void LoadArt()
    {
        foreach (var d in _dirs)
        {
            var f = Path.Combine(d, "art-align.json");
            if (!File.Exists(f)) continue;
            try
            {
                var a = JsonSerializer.Deserialize<ArtState>(File.ReadAllText(f), Opts);
                if (a == null) continue;
                Art = new ArtState
                {
                    Chosen = new Dictionary<string, string>(a.Chosen, StringComparer.OrdinalIgnoreCase),
                    Align = new Dictionary<string, ArtAlign>(a.Align, StringComparer.OrdinalIgnoreCase),
                };
                foreach (var v in Art.Align.Values) if (v.Scale <= 0) v.Scale = 1;
                return;
            }
            catch { }
        }
    }

    public void SaveArt()
    {
        Directory.CreateDirectory(WriteDir);
        var sorted = new ArtState
        {
            Chosen = new Dictionary<string, string>(new SortedDictionary<string, string>(Art.Chosen, StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase),
            Align = new Dictionary<string, ArtAlign>(new SortedDictionary<string, ArtAlign>(Art.Align, StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase),
        };
        Write(Path.Combine(WriteDir, "art-align.json"), JsonSerializer.Serialize(sorted, Opts));
    }

    /// <summary>Every map with an atlas file in any of the folders.</summary>
    public HashSet<string> Maps()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var d in _dirs.Where(Directory.Exists))
            foreach (var f in Directory.GetFiles(d, "*.json"))
            {
                var n = Path.GetFileNameWithoutExtension(f);
                if (!n.Equals("picks", StringComparison.OrdinalIgnoreCase) && !n.Equals("art-align", StringComparison.OrdinalIgnoreCase)) set.Add(n);
            }
        return set;
    }

    public SpawnAtlas? Load(string map)
    {
        if (string.IsNullOrEmpty(map)) return null;
        if (_cache.TryGetValue(map, out var hit)) return hit;
        SpawnAtlas? a = null;
        foreach (var d in _dirs)
        {
            var f = Path.Combine(d, map + ".json");
            if (!File.Exists(f)) continue;
            try { a = JsonSerializer.Deserialize<SpawnAtlas>(File.ReadAllText(f), Opts); a?.Flatten(); } catch { a = null; }
            if (a != null) break;
        }
        _cache[map] = a;
        return a;
    }

    /// <summary>File a new scan: MERGED into the map's atlas (each mode's groups / lists / objectives kept side by
    /// side - a scan under S&amp;D no longer wipes what an FFA scan found). Returns the merged atlas.</summary>
    public SpawnAtlas Save(SpawnAtlas a)
    {
        var merged = SpawnAtlas.Merge(Load(a.Map), a);
        Directory.CreateDirectory(WriteDir);
        Write(Path.Combine(WriteDir, a.Map + ".json"), JsonSerializer.Serialize(merged, Opts));
        _cache[a.Map] = merged;
        return merged;
    }

    private void LoadPicks()
    {
        foreach (var d in _dirs)
        {
            var f = Path.Combine(d, "picks.json");
            if (!File.Exists(f)) continue;
            try
            {
                var p = JsonSerializer.Deserialize<Dictionary<string, SpawnPick>>(File.ReadAllText(f), Opts);
                if (p != null) { Picks = new Dictionary<string, SpawnPick>(p, StringComparer.OrdinalIgnoreCase); return; }
            }
            catch { }
        }
    }

    public void SavePicks()
    {
        Directory.CreateDirectory(WriteDir);
        Write(Path.Combine(WriteDir, "picks.json"), JsonSerializer.Serialize(new SortedDictionary<string, SpawnPick>(Picks, StringComparer.OrdinalIgnoreCase), Opts));
    }

    private static void Write(string path, string text)
    {
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text);
        File.Move(tmp, path, true);
    }
}
