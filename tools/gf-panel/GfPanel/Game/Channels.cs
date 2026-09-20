using System.Text.RegularExpressions;

namespace GfPanel.Game;

/// <summary>GFSTATE|tick|k=v|...|say=text  (state_build in gunfight_menu.gsc). Every field optional.</summary>
public sealed record GfState
{
    public long Tick { get; init; }
    public string Map { get; init; } = "";
    public string Gametype { get; init; } = "";
    public int Round { get; init; } = 1;
    public int ScoreA { get; init; }
    public int ScoreX { get; init; }
    public int AliveA { get; init; }
    public int AliveX { get; init; }
    public int PlayersA { get; init; }
    public int PlayersX { get; init; }
    public int BotsA { get; init; }
    public int BotsX { get; init; }
    public int Spectators { get; init; }
    public int TimeLimitMs { get; init; }
    public int TimePassedMs { get; init; }
    public string Phase { get; init; } = "";
    public bool Overtime { get; init; }
    public bool Paused { get; init; }
    public bool FrozenAll { get; init; }
    public string StagedMap { get; init; } = "";
    public string StagedGametype { get; init; } = "";
    public int MaxClients { get; init; }
    public int TeamSize { get; init; }
    public int TimerSeconds { get; init; }
    public long AckSeq { get; init; }
    public bool Drunk { get; init; }
    public bool InvisibleAll { get; init; }
    public bool GodAll { get; init; }
    public bool ThirdPersonAll { get; init; }
    public int PerksAll { get; init; }
    public int Bans { get; init; }
    public int Staged { get; init; }
    public string Host { get; init; } = "";
    public string Say { get; init; } = "";
    /// <summary>The GSC's state_build() died this many times (a fallback line carries err= / st=);
    /// Stage = the numbered step it died in. 0 = healthy.</summary>
    public int Err { get; init; }
    public int Stage { get; init; }
    public bool IsFallback => Err > 0 && Map.Length == 0;

    public int TimeLeftMs => TimeLimitMs > 0 ? Math.Max(0, TimeLimitMs - TimePassedMs) : -1;

    public static GfState? Parse(long tick, string body)
    {
        var kv = new Dictionary<string, string>();
        var parts = body.Split('|');
        for (var i = 0; i < parts.Length; i++)
        {
            var p = parts[i];
            var eq = p.IndexOf('=');
            if (eq <= 0) continue;
            var k = p[..eq];
            var v = p[(eq + 1)..];
            if (k == "say") { v = string.Join("|", parts.Skip(i).Select(x => x)).Substring(4); kv[k] = v; break; }
            kv[k] = v;
        }
        if (!kv.ContainsKey("v")) return null;
        int I(string k, int d = 0) => kv.TryGetValue(k, out var s) && int.TryParse(s, out var n) ? n : d;
        bool B(string k) => I(k) == 1;
        string S(string k) => kv.TryGetValue(k, out var s) ? s : "";
        return new GfState
        {
            Tick = tick, Map = S("map"), Gametype = S("gt"), Round = I("rnd", 1),
            ScoreA = I("sa"), ScoreX = I("sx"), AliveA = I("aa"), AliveX = I("ax"),
            PlayersA = I("na"), PlayersX = I("nx"), BotsA = I("ba"), BotsX = I("bx"), Spectators = I("sp"),
            TimeLimitMs = I("tl"), TimePassedMs = I("tp"), Phase = S("ph"), Overtime = B("ot"), Paused = B("pz"), FrozenAll = B("frz"),
            StagedMap = S("stm"), StagedGametype = S("stg"), MaxClients = I("mc"), TeamSize = I("ts"), TimerSeconds = I("tmr"),
            AckSeq = I("ack"), Drunk = B("drk"), InvisibleAll = B("inv"), GodAll = B("god"), ThirdPersonAll = B("tp3"),
            PerksAll = I("prk"), Bans = I("ban"), Staged = I("stgd"), Host = S("host"), Say = StripColors(S("say")),
            Err = I("err"), Stage = I("st"),
        };
    }

    private static readonly Regex Color = new(@"\^[0-9a-zA-Z]", RegexOptions.Compiled);
    public static string StripColors(string s) => Color.Replace(s, "");
}

/// <summary>One roster row. From GFPLAYERS (rich) or GFROSTER (the older 4-field line, as a fallback).</summary>
public sealed record GfPlayer(int EntNum, string Name, string Team, string Kind, string Xuid, bool Alive, int Score, int Kills, int Deaths, string Flags)
{
    public bool IsBot => Kind == "bot";
    public bool IsHost => Kind == "host";
    public bool God => Flags.Contains('g');
    public bool Fly => Flags.Contains('f');
    public bool ThirdPerson => Flags.Contains('t');
    public bool Frozen => Flags.Contains('z');
    public bool Riding => Flags.Contains('v');
    /// <summary>Stable identity across ticks: xuid for humans, name for bots.</summary>
    public string Key => string.IsNullOrEmpty(Xuid) ? "n:" + Name : "x:" + Xuid;
}

public static class Roster
{
    /// <summary>GFPLAYERS|tick|n|entnum;name;team;kind;xuid;alive;score;kills;deaths;flags|...</summary>
    public static List<GfPlayer>? ParsePlayers(string body)
    {
        var parts = body.Split('|');
        if (parts.Length < 1 || !int.TryParse(parts[0], out var count)) return null;
        var list = new List<GfPlayer>();
        foreach (var rec in parts.Skip(1))
        {
            if (rec.Length == 0) continue;
            var f = rec.Split(';');
            if (f.Length < 10) return null;
            // a name may itself contain ';' - the first field and the last 8 are fixed, the name is the middle
            var nameParts = f.Skip(1).Take(f.Length - 9);
            var name = string.Join(";", nameParts);
            var t = f.Length - 8;
            int N(int i) => int.TryParse(f[i], out var n) ? n : 0;
            list.Add(new GfPlayer(N(0), name, f[t], f[t + 1], f[t + 2], f[t + 3] == "1", N(t + 4), N(t + 5), N(t + 6), f[t + 7]));
        }
        return list.Count == count ? list : null;
    }

    /// <summary>GFROSTER|tick|count|name;team;kind;xuid|... (the older line; no entnum / alive / score).</summary>
    public static List<GfPlayer>? ParseRoster(string body)
    {
        var parts = body.Split('|');
        if (parts.Length < 1 || !int.TryParse(parts[0], out var count)) return null;
        var list = new List<GfPlayer>();
        foreach (var rec in parts.Skip(1))
        {
            if (rec.Length == 0) continue;
            var f = rec.Split(';');
            if (f.Length != 4) return null;
            list.Add(new GfPlayer(-1, f[0], f[1], f[2], f[3], true, 0, 0, 0, ""));
        }
        return list.Count == count ? list : null;
    }
}

/// <summary>GFCFG|tick|c0|..|c8|oob=|bar=|trk=|veh=|bot=|bot2=|race=|dbg=|misc=  (config_publish).</summary>
public sealed class GfConfig
{
    public long Tick { get; init; }
    public Dictionary<string, int> Values { get; } = new();
    public string Track { get; init; } = "";
    /// <summary>Raw chunk strings as the game holds them (empty = never written).</summary>
    public string[] Chunks { get; init; } = new string[Packing.ChunkCount];

    public static GfConfig? Parse(long tick, string body)
    {
        var parts = body.Split('|');
        if (parts.Length < Packing.ChunkCount) return null;
        var cfg = new GfConfig { Tick = tick, Chunks = parts.Take(Packing.ChunkCount).ToArray(),
                                 Track = parts.FirstOrDefault(p => p.StartsWith("trk="))?[4..] ?? "" };
        for (var c = 0; c < Packing.ChunkCount; c++) Packing.UnpackChunk(c, parts[c], cfg.Values);
        foreach (var e in parts.Skip(Packing.ChunkCount))
        {
            var eq = e.IndexOf('=');
            if (eq <= 0) continue;
            var k = e[..eq]; var v = e[(eq + 1)..];
            switch (k)
            {
                case "oob": if (int.TryParse(v, out var oob)) cfg.Values["gf_oob"] = oob; break;
                case "bar": if (int.TryParse(v, out var bar)) cfg.Values["gf_deathbarrier"] = bar; break;
                case "bot": Packing.UnpackList(Packing.BotPack.Take(8).ToArray(), v, cfg.Values); break;
                case "bot2": Packing.UnpackList(Packing.BotPack.Skip(8).ToArray(), v, cfg.Values); break;
                case "veh": Packing.UnpackList(Packing.VehOrder, v, cfg.Values); break;
                case "race": Packing.UnpackList(Packing.RaceOrder, v, cfg.Values); break;
                case "dbg": Packing.UnpackList(Packing.DbgOrder, v, cfg.Values); break;
                case "misc": Packing.UnpackList(Packing.MiscOrder, v, cfg.Values); break;
            }
        }
        return cfg;
    }
}

/// <summary>GFMAPVEH / GFMAPPROP / GFMAPSPAWN / GFMAPDEST - the per-map census (mapdata_scan.py), kept for the Maps tab.</summary>
public sealed class GfMapData
{
    public string Map { get; init; } = "";
    public string Gametype { get; init; } = "";
    public List<string> VehiclesDrive { get; init; } = new();
    public List<string> VehiclesOther { get; init; } = new();
    public List<(string Model, string Size)> Props { get; init; } = new();
    public string SpawnTally { get; init; } = "";
    public string DestructSummary { get; init; } = "";

    public static (string Kind, string Map, GfMapData Data)? Parse(string marker, string body)
    {
        var parts = body.Split('|');
        if (parts.Length < 2 || parts[0].Length == 0) return null;
        var map = parts[0];
        switch (marker)
        {
            case "GFMAPVEH" when parts.Length >= 4:
                return ("VEH", map, new GfMapData { Map = map, Gametype = parts[1],
                    VehiclesDrive = parts[2].Split(',', StringSplitOptions.RemoveEmptyEntries).ToList(),
                    VehiclesOther = parts[3].Split(',', StringSplitOptions.RemoveEmptyEntries).ToList() });
            case "GFMAPPROP":
                var props = new List<(string, string)>();
                if (parts.Length >= 4)
                    foreach (var cell in parts[3].Split(',', StringSplitOptions.RemoveEmptyEntries))
                    {
                        var c = cell.Split(':');
                        props.Add((c[0], c.Length > 1 ? c[1] : ""));
                    }
                return ("PROP", map, new GfMapData { Map = map, Props = props });
            case "GFMAPSPAWN":
                return ("SPAWN", map, new GfMapData { Map = map, SpawnTally = string.Join(" | ", parts.Skip(1)) });
            case "GFMAPDEST":
                return ("DEST", map, new GfMapData { Map = map, DestructSummary = string.Join(" ", parts.Skip(1)) });
        }
        return null;
    }
}
