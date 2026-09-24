using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GfPanel.Services;

public sealed class MessagePreset
{
    public string Name { get; set; } = "";
    public string Text { get; set; } = "";
    public int Loc { get; set; }             // 0 centre, 1 feed, 2 banner
    public int Dur { get; set; }             // 0 once, >0 seconds, -1 held
    public string Audience { get; set; } = "all";
}

public sealed class ConfigPreset
{
    public string Name { get; set; } = "";
    public string Note { get; set; } = "";
    public Dictionary<string, int> Values { get; set; } = new();
}

public sealed class BotProfile
{
    public string Name { get; set; } = "";
    public string Note { get; set; } = "";
    public Dictionary<string, int> Values { get; set; } = new();   // the 15 gf_bot_* knobs
}

public sealed class PlaylistEntry
{
    public string Map { get; set; } = "";
    public string Gametype { get; set; } = "gunfight";
}

/// <summary>Panel state that follows the user, not the bundle: %LOCALAPPDATA%\GfPanel\prefs.json.
/// Written atomically (temp + rename) - the process is killed routinely.</summary>
public sealed class Prefs
{
    public List<string> Favorites { get; set; } = new() { "gf_team_size", "gf_timer_seconds", "gf_roundwinlimit", "gf_loadout", "gf_bot_diff_allies", "gf_gravity", "gf_speed" };
    public List<string> Collapsed { get; set; } = new();
    public double SidebarWidth { get; set; } = 440;
    public double ActivityHeight { get; set; } = 200;
    public double WindowWidth { get; set; } = 1440;
    public double WindowHeight { get; set; } = 900;
    public bool WindowMaximized { get; set; }
    public long CommandSeq { get; set; }
    public string LastTab { get; set; } = "dashboard";
    public List<MessagePreset> Messages { get; set; } = new();
    public List<ConfigPreset> ConfigPresets { get; set; } = new();
    public List<BotProfile> BotProfiles { get; set; } = new();
    public List<PlaylistEntry> Playlist { get; set; } = new();
    public bool PlaylistEnabled { get; set; }
    public int PlaylistIndex { get; set; }
    public bool JoinBeep { get; set; } = true;
    public bool JoinToast { get; set; } = true;
    public bool ApplyLiveOnChange { get; set; } = true;
    /// <summary>Set up all also injects payloads\gunfight_lobby.gscc (the lobby slot count) on its own replace target.</summary>
    public bool InjectLobby { get; set; } = true;
    public List<string> Bans { get; set; } = new();          // xuid list re-sent at match start
    public List<int> PropFavorites { get; set; } = new();     // universal prop indices the in-game menu shows (the GSC contract)
    // The same favourites by MODEL name: the universal list gets renumbered when the catalog is regenerated
    // (2026-09-21: 546 -> 514 when the debris props were dropped), so indices alone go stale; at startup the
    // index list is rebuilt from these names against the embedded catalog.
    public List<string> PropFavoriteModels { get; set; } = new();
    public int PropCatalogCount { get; set; }
    public Dictionary<string, string> TeamPlan { get; set; } = new();   // xuid -> a|x|s, re-sent at match start
    public Dictionary<string, string> KnownNames { get; set; } = new(); // xuid -> last seen name
    // SPAWNS tab (the spawn atlas): scan every map the first time it loads; the dense-area search radius /
    // height band (units); the minimum spots a side the area pairs must hold (0 = the team size)
    // OFF by default (2026-09-22: the first atlas build crashed a match on its auto-scan - fixed, but the scan
    // runs only when asked until one has been proven in game); renamed so an old saved "true" does not carry over
    public bool SpawnAutoScanOn { get; set; }
    public int SpawnAreaRadiusSet { get; set; }          // 0 = auto (scaled to the map); renamed from the fixed 650 default
    public int SpawnAreaBand { get; set; } = 160;
    public int SpawnMinPerSide { get; set; }

    [JsonIgnore] public static string Path => System.IO.Path.Combine(App.DataDir, "prefs.json");

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, DefaultIgnoreCondition = JsonIgnoreCondition.Never };

    public static Prefs Load()
    {
        try
        {
            if (File.Exists(Path))
            {
                var p = JsonSerializer.Deserialize<Prefs>(File.ReadAllText(Path), Json);
                if (p != null) return p;
            }
        }
        catch { /* a corrupt prefs file must never stop the panel; it is rewritten on the next save */ }
        return new Prefs();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(App.DataDir);
            var tmp = Path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(this, Json));
            File.Move(tmp, Path, true);
        }
        catch { }
    }
}
