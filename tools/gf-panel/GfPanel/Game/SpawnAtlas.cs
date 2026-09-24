using System.Globalization;
using System.Text.Json.Serialization;
using GfPanel.Native;

namespace GfPanel.Game;

// ═════════════════════════════════════════════════════════════════════════════
// The SPAWN ATLAS (klaze 2026-09-22: "calculate every spawn group on every map for every mode and
// include starting spawns and mid match respawn points ... if theres enough spots grouped together
// in certain areas, we may want to use those as our starting spots instead. so we need a clear
// picture of every possibility"). The game publishes one map's full spawn census on request
// (gunfight_menu.gsc spawn_atlas_scan, the GFSPAWN chunks); this file parses it, keeps it per map
// and derives everything the SPAWNS tab shows: every mode's starts and respawn pools, the S&D
// groups, the BO2-named starts, the engine's live lists, the DENSE AREAS, and the ranked start
// layouts a per-map pick can be made from. docs/notes/spawn-atlas.md
// ═════════════════════════════════════════════════════════════════════════════

/// <summary>One flag of the engine's spawn-mode vocabulary (function_82ca1565 in the dump's spawning
/// script): Word 1 = the 25 modes, 2 = the objective sub-sets, 3 = the numbered zone lists.
/// Family = the GSC gf_spawn_family number a pick can use (0 = none: area picks only).</summary>
public sealed record SpawnMode(string Key, string Label, int Word, int Bit, int Family = 0, string UsedBy = "")
{
    public long Mask => 1L << Bit;
    public bool In(AtlasPoint p) => ((Word == 1 ? p.M1 : Word == 2 ? p.M2 : p.M3) & Mask) != 0;
}

public static class SpawnModes
{
    // Word 1, in the GSC's atlas_m1 order. UsedBy = the stock gametypes that register this spawn
    // type (addsupportedspawnpointtype in scripts/mp_common/gametypes/*.gsc + the hashed modes).
    public static readonly SpawnMode[] Core =
    {
        new("base", "base", 1, 0),
        new("ffa", "FFA", 1, 1, 7, "Free-for-all, Gun Game, Infected, One in the Chamber, Sticks & Stones, Scream"),
        new("sd", "S&D", 1, 2, 2, "Search & Destroy"),
        new("ctf", "CTF", 1, 3, 4, "Capture the Flag"),
        new("dom", "Domination", 1, 4, 3, "Domination"),
        new("dem", "Demolition", 1, 5, 0, "Demolition"),
        new("gg", "gg", 1, 6),
        new("tdm", "TDM", 1, 7, 1, "TDM, Kill Confirmed, GUNFIGHT, Prop Hunt, Dropkick, Fireteam"),
        new("infil", "infiltration", 1, 8),
        new("control", "Control", 1, 9, 6, "Control"),
        new("uplink", "uplink", 1, 10),
        new("kc", "kc", 1, 11),
        new("hardpoint", "Hardpoint", 1, 12, 5, "Hardpoint"),
        new("frontline", "frontline", 1, 13),
        new("ct", "ct", 1, 14),
        new("escort", "escort", 1, 15),
        new("bounty", "bounty", 1, 16),
        new("fireteam", "Fireteam", 1, 17, 0, "Fireteam modes"),
        new("vip", "VIP Escort", 1, 18, 0, "VIP Escort"),
        new("war", "war zones", 1, 19, 0, "the war_zone mode"),
        new("dropkick", "Dropkick", 1, 20, 0, "Dropkick"),
        new("spy", "Spy", 1, 21, 0, "Spy"),
        new("m3cb82e5e", "mode #3cb82e5e", 1, 22),
        new("md8e690f8", "mode #d8e690f8", 1, 23),
        new("m3d72e6da", "mode #3d72e6da", 1, 24),
    };

    // Word 2, the GSC's atlas_m2 order: which objective state a respawn point serves.
    public static readonly SpawnMode[] Sub =
    {
        new("domA", "DOM flag A", 2, 0), new("domB", "DOM flag B", 2, 1), new("domC", "DOM flag C", 2, 2),
        new("domD", "DOM flag D", 2, 3), new("domE", "DOM flag E", 2, 4), new("domF", "DOM flag F", 2, 5),
        new("demAtkA", "Dem attack A", 2, 6), new("demAtkB", "Dem attack B", 2, 7),
        new("demRemA", "Dem remove A", 2, 8), new("demRemB", "Dem remove B", 2, 9),
        new("demOT", "Dem overtime", 2, 10), new("demStart", "Dem start", 2, 11),
        new("demDefA", "Dem defend A", 2, 12), new("demDefB", "Dem defend B", 2, 13),
        new("ctlAtkAddA", "Control attack+ A", 2, 14), new("ctlAtkAddB", "Control attack+ B", 2, 15),
        new("ctlAtkRemA", "Control attack- A", 2, 16), new("ctlAtkRemB", "Control attack- B", 2, 17),
        new("ctlDefAddA", "Control defend+ A", 2, 18), new("ctlDefAddB", "Control defend+ B", 2, 19),
        new("ctlDefRemA", "Control defend- A", 2, 20), new("ctlDefRemB", "Control defend- B", 2, 21),
    };

    // Word 3, the GSC's atlas_m3 order: Hardpoint's per-zone respawn lists and the war zones.
    public static readonly SpawnMode[] Zones =
        Enumerable.Range(0, 10).Select(i => new SpawnMode("hp" + i, "Hardpoint zone " + (i + 1), 3, i))
        .Concat(Enumerable.Range(0, 5).Select(i => new SpawnMode("war" + i, "war zone " + (i + 1), 3, 10 + i)))
        .ToArray();

    public static IEnumerable<SpawnMode> All => Core.Concat(Sub).Concat(Zones);
    public static SpawnMode? ByKey(string key) => All.FirstOrDefault(m => m.Key == key);
    public static SpawnMode? ByFamily(int f) => Core.FirstOrDefault(m => m.Family == f);

    /// <summary>The GSC family_name() spelling of a gf_spawn_family number.</summary>
    public static string FamilyName(int f) => f switch
    {
        1 => "TDM", 2 => "S&D", 3 => "Domination", 4 => "CTF", 5 => "Hardpoint", 6 => "Control", 7 => "FFA",
        8 => "AUTO", 9 => "area", 10 => "stock", _ => "none",
    };
}

/// <summary>The legacy-named spawn structs (mod_spawn_families): what each name means.</summary>
public static class SpawnNames
{
    public readonly record struct NameInfo(string Mode, int Side, bool Start);

    public static NameInfo Info(string? n) => n switch
    {
        "mp_spawn_point_allies" => new("any", 1, false),
        "mp_spawn_point_axis" => new("any", 2, false),
        "mp_dm_spawn" => new("ffa", 0, false),
        "mp_dm_spawn_start" => new("ffa", 0, true),
        "mp_tdm_spawn" => new("tdm", 0, false),
        "mp_tdm_spawn_allies_start" or "mp_tdm_spawn_team1_start" => new("tdm", 1, true),
        "mp_tdm_spawn_axis_start" or "mp_tdm_spawn_team2_start" => new("tdm", 2, true),
        "mp_dom_spawn" => new("dom", 0, false),
        "mp_dom_spawn_allies_start" => new("dom", 1, true),
        "mp_dom_spawn_axis_start" => new("dom", 2, true),
        "mp_sd_spawn_attacker" => new("sd", 1, true),
        "mp_sd_spawn_defender" => new("sd", 2, true),
        "mp_ctf_spawn_allies" => new("ctf", 1, false),
        "mp_ctf_spawn_axis" => new("ctf", 2, false),
        "mp_ctf_spawn_allies_start" => new("ctf", 1, true),
        "mp_ctf_spawn_axis_start" => new("ctf", 2, true),
        "mp_twar_spawn" => new("war", 0, false),
        "mp_twar_spawn_allies_start" => new("war", 1, true),
        "mp_twar_spawn_axis_start" => new("war", 2, true),
        _ => new("?", 0, false),
    };

    /// <summary>The GSC's mod_named_side: which named structs count as family f's authored starts.</summary>
    public static int GscNamedSide(string? n, int fam) => fam switch
    {
        1 => n is "mp_tdm_spawn_allies_start" or "mp_tdm_spawn_team1_start" ? 1 : n is "mp_tdm_spawn_axis_start" or "mp_tdm_spawn_team2_start" ? 2 : 0,
        2 => n == "mp_sd_spawn_attacker" ? 1 : n == "mp_sd_spawn_defender" ? 2 : 0,
        3 => n == "mp_dom_spawn_allies_start" ? 1 : n == "mp_dom_spawn_axis_start" ? 2 : 0,
        4 => n is "mp_ctf_spawn_allies_start" or "mp_ctf_spawn_allies" ? 1 : n is "mp_ctf_spawn_axis_start" or "mp_ctf_spawn_axis" ? 2 : 0,
        _ => 0,
    };
}

/// <summary>One spawn point: M = an mp_spawn_point marker, N = a legacy-named struct, Q = an S&D group point.</summary>
public sealed class AtlasPoint
{
    public string Kind { get; set; } = "M";
    /// <summary>M: the marker's index in struct::get_array("mp_spawn_point"); N: the name key; Q: the group id.</summary>
    public int Index { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
    public double Z { get; set; }
    public int Yaw { get; set; }
    /// <summary>M: .group_index (1 allies, 2 axis, 0 either, -1 unset); Q: its group's side.</summary>
    public int Group { get; set; }
    /// <summary>M: 1 start (the engine's start_spawn flag), 2 hq, 4 disabled.</summary>
    public int Flags { get; set; }
    public long M1 { get; set; }
    public long M2 { get; set; }
    public long M3 { get; set; }
    public string? Name { get; set; }

    [JsonIgnore] public bool Start => (Flags & 1) != 0;
    [JsonIgnore] public bool Hq => (Flags & 2) != 0;
    [JsonIgnore] public bool Disabled => (Flags & 4) != 0;
    /// <summary>1 allies side / 2 axis side / 0 either.</summary>
    [JsonIgnore] public int Side => Kind == "N" ? SpawnNames.Info(Name).Side : (Group is 1 or 2 ? Group : 0);
    /// <summary>The GSC's position key (atlas_v): truncated ints.</summary>
    [JsonIgnore] public string Key => $"{(long)X}/{(long)Y}/{(long)Z}";

    public double Dist2(double x, double y) => (X - x) * (X - x) + (Y - y) * (Y - y);

    public IEnumerable<SpawnMode> Modes => SpawnModes.All.Where(m => m.In(this));

    public string Describe()
    {
        var head = Kind switch
        {
            "M" => $"marker #{Index}",
            "N" => Name ?? "named",
            _ => $"S&D group {Index} point",
        };
        var side = Side switch { 1 => "allies side", 2 => "axis side", _ => "either side" };
        var bits = new List<string>();
        if (Kind == "M") { bits.Add(Start ? "START" : "respawn"); if (Hq) bits.Add("hq"); if (Disabled) bits.Add("disabled"); }
        var modes = string.Join(" ", Modes.Select(m => m.Label));
        return $"{head} · {side} · {string.Join(" ", bits)}\n({X:0}, {Y:0}, {Z:0})  yaw {Yaw}" + (modes.Length > 0 ? "\n" + modes : "");
    }
}

/// <summary>The in-game map's world rectangle: its four corners and the north yaw it is drawn with.</summary>
public readonly record struct MinimapFrame(double NWx, double NWy, double NEx, double NEy, double SWx, double SWy, double SEx, double SEy, double NorthYaw)
{
    public double Width => Math.Sqrt((NEx - NWx) * (NEx - NWx) + (NEy - NWy) * (NEy - NWy));
    public double Height => Math.Sqrt((SWx - NWx) * (SWx - NWx) + (SWy - NWy) * (SWy - NWy));
}

public sealed class AtlasGroup
{
    public int Id { get; set; }
    public int Side { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
    public double Z { get; set; }
    public int Yaw { get; set; }
    public string Target { get; set; } = "";
    public string Objective { get; set; } = "";
    public string Team { get; set; } = "";
    /// <summary>The mode the scan that saw it ran under (set when a map's scans are merged).</summary>
    public string Gametype { get; set; } = "";
}

/// <summary>One objective of the mode a scan ran under (O record): a bomb site, a DOM flag, a Hardpoint / Control
/// zone, a CTF flag, the Gunfight flag, or another entity the gametype kept for that mode (Kind "ent").</summary>
public sealed class AtlasObjective
{
    public string Kind { get; set; } = "";
    public double X { get; set; }
    public double Y { get; set; }
    public double Z { get; set; }
    public int Yaw { get; set; }
    public int Radius { get; set; }
    public string Target { get; set; } = "";
    public string Label { get; set; } = "";
    public string GameObj { get; set; } = "";
    /// <summary>The mode the scan ran under (objectives exist only in their own mode).</summary>
    public string Gametype { get; set; } = "";

    /// <summary>A short label for the map: "A", "B", "flag C", "HP", ...</summary>
    [JsonIgnore]
    public string Short
    {
        get
        {
            var l = Label.TrimStart('_').ToUpperInvariant();
            if (l.Length > 3 || l == "-" || l == "#") l = "";
            return Kind switch
            {
                "bombzone" => l.Length > 0 ? l : "bomb",
                "flag_primary" or "flag_secondary" => l.Length > 0 ? l : "flag",
                "koth_zone_center" => "HP" + l,
                "control_zone_center" => "CTL" + l,
                "ctf_flag_pickup_trig" => "flag",
                "ctf_flag_zone_trig" => "cap",
                "gunfight_zone_center" or "gunfight_flag_neutral" => "GF",
                _ => "",
            };
        }
    }

    [JsonIgnore]
    public string KindText => Kind switch
    {
        "bombzone" => "bomb site",
        "flag_primary" or "flag_secondary" => "Domination flag",
        "koth_zone_center" => "Hardpoint zone",
        "control_zone_center" => "Control zone",
        "ctf_flag_pickup_trig" => "CTF flag",
        "ctf_flag_zone_trig" => "CTF capture zone",
        "gunfight_zone_center" or "gunfight_flag_neutral" => "Gunfight overtime flag",
        _ => "mode entity",
    };

    public string Describe() =>
        $"{KindText}{(Short.Length > 0 && Short != "bomb" && Short != "flag" ? " " + Short : "")} · {Gametype}\n({X:0}, {Y:0}, {Z:0})" +
        (Radius > 0 ? $"  radius {Radius}" : "") + (Target is { Length: > 0 } t && t != "-" && t != "#" ? $"\n{t}" : "") +
        (GameObj is { Length: > 0 } g && g != "-" ? $"\nfor: {g}" : "");
}

/// <summary>What one scan saw that belongs to the mode it ran under: the engine's live lists, the spawn groups and
/// the objectives (both deleted at load in other modes). A map's atlas keeps one per mode scanned.</summary>
public sealed class ModeScan
{
    public string Gametype { get; set; } = "";
    public DateTime Captured { get; set; }
    public List<AtlasList> Lists { get; set; } = new();
    public List<AtlasGroup> Groups { get; set; } = new();
    public List<AtlasPoint> GroupPoints { get; set; } = new();
    public List<AtlasObjective> Objectives { get; set; } = new();
    public double[]? Host { get; set; }
    public string Note { get; set; } = "";
    public int TeamSize { get; set; }
    public int Guard { get; set; }
    public int Family { get; set; }

    public static ModeScan From(SpawnAtlas a) => new()
    {
        Gametype = a.Gametype, Captured = a.Captured, Lists = a.Lists, Groups = a.Groups, GroupPoints = a.GroupPoints,
        Objectives = a.Objectives, Host = a.Host, Note = a.Note, TeamSize = a.TeamSize, Guard = a.Guard, Family = a.Family,
    };
}

/// <summary>One of the engine's live spawn lists for the gametype the scan ran under, one side.</summary>
public sealed class AtlasList
{
    public string Name { get; set; } = "";
    public int Side { get; set; }
    public int Size { get; set; }
    public List<int> Members { get; set; } = new();
    /// <summary>Points the list holds that are not markers: x, y, z.</summary>
    public List<double[]> Extra { get; set; } = new();
}

public sealed class SpawnAtlas
{
    public int Version { get; set; } = 1;
    public string Map { get; set; } = "";
    public string Gametype { get; set; } = "";
    public int MarkerCount { get; set; }
    public double[]? MapCenter { get; set; }
    /// <summary>The host at scan time: x, y, z, yaw.</summary>
    public double[]? Host { get; set; }
    public bool Switched { get; set; }
    public int TeamSize { get; set; }
    public int Guard { get; set; }
    public int Family { get; set; }
    public string Note { get; set; } = "";
    public DateTime Captured { get; set; }
    public long Stamp { get; set; }
    public int Chunks { get; set; }
    public List<AtlasPoint> Markers { get; set; } = new();
    public List<AtlasPoint> Named { get; set; } = new();
    public List<AtlasGroup> Groups { get; set; } = new();
    public List<AtlasPoint> GroupPoints { get; set; } = new();
    public List<AtlasList> Lists { get; set; } = new();
    /// <summary>The C record: the two minimap_corner points (x0, y0, x1, y1) - null when the map has no pair.</summary>
    public double[]? Minimap { get; set; }
    /// <summary>getnorthyaw(): the world yaw the in-game map calls north (null on scans before the C record).</summary>
    public double? NorthYaw { get; set; }
    /// <summary>Every mode's objectives seen so far (the union over Scans).</summary>
    public List<AtlasObjective> Objectives { get; set; } = new();
    /// <summary>One entry per mode this map was scanned under (a rescan of a mode replaces its entry). Empty on
    /// files written before 2026-09-22 late - those hold one scan in the top-level fields.</summary>
    public List<ModeScan> Scans { get; set; } = new();

    /// <summary>"dm, gunfight, sd" - the modes this atlas has seen.</summary>
    [JsonIgnore] public string ScannedModes => Scans.Count > 0 ? string.Join(", ", Scans.Select(x => x.Gametype)) : Gametype;

    /// <summary>Gunfight and Gunfight 3v3 are one gametype script (gunfight.gsc, settings apart): one scan slot.</summary>
    public static string ModeFamily(string g) => (g ?? "").ToLowerInvariant() is var l && l.StartsWith("gunfight") ? "gunfight" : (g ?? "").ToLowerInvariant();
    public static bool SameMode(string a, string b) => ModeFamily(a) == ModeFamily(b);

    /// <summary>A new scan merged into this map's atlas: the markers / named structs / frame from the new scan (the
    /// same in every mode), each mode's lists / groups / objectives kept side by side, then flattened: groups and
    /// objectives = the union; the lists (and Gametype) = the preferred scan's - Gunfight, else a tdm-type mode,
    /// else the latest.</summary>
    public static SpawnAtlas Merge(SpawnAtlas? old, SpawnAtlas inc)
    {
        var scans = new List<ModeScan>();
        if (old != null)
        {
            var prev = old.Scans.Count > 0 ? old.Scans : new List<ModeScan> { ModeScan.From(old) };
            scans.AddRange(prev.Where(x => !SameMode(x.Gametype, inc.Gametype)));
        }
        foreach (var o in inc.Objectives) o.Gametype = inc.Gametype;
        scans.Add(ModeScan.From(inc));
        var m = new SpawnAtlas
        {
            Version = inc.Version, Map = inc.Map, MarkerCount = inc.MarkerCount, MapCenter = inc.MapCenter,
            Switched = inc.Switched, Stamp = inc.Stamp, Chunks = inc.Chunks,
            Markers = inc.Markers, Named = inc.Named, Minimap = inc.Minimap ?? old?.Minimap, NorthYaw = inc.NorthYaw ?? old?.NorthYaw,
            Scans = scans.OrderBy(x => x.Captured).ToList(),
        };
        m.Flatten();
        return m;
    }

    /// <summary>Fill the top-level views from Scans (see Merge). A no-op on an old single-scan file.</summary>
    public void Flatten()
    {
        if (Scans.Count == 0) return;
        bool Tdm(string g) => g.StartsWith("gunfight") || g.StartsWith("tdm") || g.StartsWith("conf") || g.StartsWith("prop") || g.StartsWith("dropkick") || g.StartsWith("fireteam") || g == "clean";
        var latest = Scans.OrderBy(x => x.Captured).Last();
        var pref = Scans.FirstOrDefault(x => x.Gametype.StartsWith("gunfight", StringComparison.OrdinalIgnoreCase))
                   ?? Scans.Where(x => Tdm(x.Gametype.ToLowerInvariant())).OrderBy(x => x.Captured).LastOrDefault()
                   ?? latest;
        Gametype = pref.Gametype;
        Lists = pref.Lists;
        Captured = latest.Captured;
        Host = latest.Host; Note = latest.Note; TeamSize = latest.TeamSize; Guard = latest.Guard; Family = latest.Family;
        // group ids shifted past the previous scans' so two modes' groups never collide (the usual case - only
        // the S&D scan has groups - keeps its own ids)
        Groups = new List<AtlasGroup>();
        GroupPoints = new List<AtlasPoint>();
        Objectives = new List<AtlasObjective>();
        var baseId = 0;
        foreach (var sc in Scans)
        {
            foreach (var g in sc.Groups)
                Groups.Add(new AtlasGroup { Id = baseId + g.Id, Side = g.Side, X = g.X, Y = g.Y, Z = g.Z, Yaw = g.Yaw, Target = g.Target, Objective = g.Objective, Team = g.Team, Gametype = sc.Gametype });
            foreach (var q in sc.GroupPoints)
                GroupPoints.Add(new AtlasPoint { Kind = "Q", Index = baseId + q.Index, X = q.X, Y = q.Y, Z = q.Z, Yaw = q.Yaw, Group = q.Group });
            foreach (var o in sc.Objectives) if (o.Gametype.Length == 0) o.Gametype = sc.Gametype;
            Objectives.AddRange(sc.Objectives);
            if (sc.Groups.Count > 0) baseId += sc.Groups.Max(g => g.Id) + 1;
        }
    }

    [JsonIgnore] public IEnumerable<AtlasPoint> AllPoints => Markers.Concat(Named).Concat(GroupPoints);

    /// <summary>The world rectangle the in-game map shows, as compass.gsc function_d6cba2e9 hands it to
    /// setminimap: the two corners sorted into north-west / south-east along the map's north, plus the
    /// other two corners. null without a corner pair.</summary>
    public MinimapFrame? Frame()
    {
        if (Minimap is not { Length: 4 } m) return null;
        var a = (NorthYaw ?? 90) * Math.PI / 180;
        double nx = Math.Cos(a), ny = Math.Sin(a);          // north
        double wx = -ny, wy = nx;                           // west = ( -north.y, north.x )
        double c0x = m[0], c0y = m[1], c1x = m[2], c1y = m[3];
        double dx = c1x - c0x, dy = c1y - c0y;
        double dW = dx * wx + dy * wy, dN = dx * nx + dy * ny;
        double nwx, nwy, sex, sey;
        if (dW > 0)
        {
            if (dN > 0) { nwx = c1x; nwy = c1y; sex = c0x; sey = c0y; }
            else { double sx = nx * dN, sy = ny * dN; nwx = c1x - sx; nwy = c1y - sy; sex = c0x + sx; sey = c0y + sy; }
        }
        else if (dN > 0) { double sx = nx * dN, sy = ny * dN; nwx = c0x + sx; nwy = c0y + sy; sex = c1x - sx; sey = c1y - sy; }
        else { nwx = c0x; nwy = c0y; sex = c1x; sey = c1y; }
        double ex = -wx, ey = -wy;                          // east
        var width = (sex - nwx) * ex + (sey - nwy) * ey;    // along east
        var height = -((sex - nwx) * nx + (sey - nwy) * ny); // along south
        return new MinimapFrame(nwx, nwy, nwx + ex * width, nwy + ey * width, nwx - nx * height, nwy - ny * height, sex, sey, NorthYaw ?? 90);
    }

    /// <summary>The de-duplicated pool the GSC's AREA pick draws from (spawn_pick_pool): markers + named
    /// structs (mod_gather_spawns), then the points of the sided S&D groups (mod_spawn_groups).</summary>
    public List<AtlasPoint> PickPool()
    {
        var seen = new HashSet<string>();
        var pool = new List<AtlasPoint>();
        var sided = Groups.Where(g => g.Side is 1 or 2 && g.Target != "-" && g.Target.Length > 0).Select(g => g.Id).ToHashSet();
        foreach (var p in Markers.Concat(Named).Concat(GroupPoints.Where(q => sided.Contains(q.Index))))
            if (seen.Add(p.Key)) pool.Add(p);
        return pool;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // wire
    // ─────────────────────────────────────────────────────────────────────────
    private static int I(string[] f, int i, int d = 0) => i < f.Length && int.TryParse(f[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : d;
    private static long L(string[] f, int i) => i < f.Length && long.TryParse(f[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 0;
    private static double D(string[] f, int i) => i < f.Length && double.TryParse(f[i], NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;
    private static string S(string[] f, int i) => i < f.Length ? f[i] : "";

    private static double[]? Vec(string s, int n)
    {
        if (s == "-" || s.Length == 0) return null;
        var p = s.Split('/');
        if (p.Length < n) return null;
        var v = new double[n];
        for (var i = 0; i < n; i++) if (!double.TryParse(p[i], NumberStyles.Float, CultureInfo.InvariantCulture, out v[i])) return null;
        return v;
    }

    /// <summary>Parse one scan: the records of chunks 0..n-1 in order.</summary>
    public static SpawnAtlas? Parse(IReadOnlyList<string> chunkRecords, long stamp)
    {
        var a = new SpawnAtlas { Stamp = stamp, Chunks = chunkRecords.Count, Captured = DateTime.Now };
        var names = new Dictionary<int, string>();
        var groupSide = new Dictionary<int, int>();

        foreach (var rec in string.Join(";", chunkRecords).Split(';'))
        {
            if (rec.Length < 2) continue;
            var f = rec.Split(',');
            switch (f[0])
            {
                case "H":
                    a.Version = I(f, 1, 1); a.Map = S(f, 2); a.Gametype = S(f, 3); a.MarkerCount = I(f, 4);
                    a.MapCenter = Vec(S(f, 5), 3); a.Host = Vec(S(f, 6), 4); a.Switched = I(f, 7) == 1;
                    a.TeamSize = I(f, 8); a.Guard = I(f, 9); a.Family = I(f, 10);
                    a.Note = f.Length > 11 ? string.Join(",", f.Skip(11)) : "";
                    break;
                case "C":
                    if (f.Length > 4 && f[1] != "-")
                        a.Minimap = new[] { D(f, 1), D(f, 2), D(f, 3), D(f, 4) };
                    if (f.Length > 5 && double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out var nyaw)) a.NorthYaw = nyaw;
                    break;
                case "O":
                    a.Objectives.Add(new AtlasObjective
                    {
                        Kind = S(f, 1), X = D(f, 2), Y = D(f, 3), Z = D(f, 4), Yaw = I(f, 5), Radius = I(f, 6),
                        Target = S(f, 7), Label = S(f, 8), GameObj = S(f, 9),
                    });
                    break;
                case "M":
                    a.Markers.Add(new AtlasPoint
                    {
                        Kind = "M", Index = I(f, 1), X = D(f, 2), Y = D(f, 3), Z = D(f, 4), Yaw = I(f, 5),
                        Group = I(f, 6, -1), Flags = I(f, 7), M1 = L(f, 8), M2 = L(f, 9), M3 = L(f, 10),
                    });
                    break;
                case "D":
                    names[I(f, 1)] = S(f, 2);
                    break;
                case "N":
                {
                    var k = I(f, 1);
                    a.Named.Add(new AtlasPoint { Kind = "N", Index = k, X = D(f, 2), Y = D(f, 3), Z = D(f, 4), Yaw = I(f, 5), Name = names.GetValueOrDefault(k, "?") });
                    break;
                }
                case "G":
                {
                    var g = new AtlasGroup { Id = I(f, 1), Side = I(f, 2), X = D(f, 3), Y = D(f, 4), Z = D(f, 5), Yaw = I(f, 6), Target = S(f, 7), Objective = S(f, 8), Team = S(f, 9) };
                    a.Groups.Add(g);
                    groupSide[g.Id] = g.Side;
                    break;
                }
                case "Q":
                {
                    var gid = I(f, 1);
                    a.GroupPoints.Add(new AtlasPoint { Kind = "Q", Index = gid, X = D(f, 2), Y = D(f, 3), Z = D(f, 4), Yaw = I(f, 5), Group = groupSide.GetValueOrDefault(gid, 0) });
                    break;
                }
                case "L":
                {
                    var name = S(f, 1);
                    var side = I(f, 2);
                    var list = a.Lists.FirstOrDefault(l => l.Name == name && l.Side == side);
                    if (list == null) { list = new AtlasList { Name = name, Side = side }; a.Lists.Add(list); }
                    list.Size = I(f, 3);
                    foreach (var m in S(f, 4).Split(' ', StringSplitOptions.RemoveEmptyEntries))
                    {
                        if (m[0] == '@')
                        {
                            var v = m[1..].Split(':');
                            if (v.Length == 3 && double.TryParse(v[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var x)
                                && double.TryParse(v[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var y)
                                && double.TryParse(v[2], NumberStyles.Float, CultureInfo.InvariantCulture, out var z))
                                list.Extra.Add(new[] { x, y, z });
                        }
                        else if (int.TryParse(m, NumberStyles.Integer, CultureInfo.InvariantCulture, out var idx)) list.Members.Add(idx);
                    }
                    break;
                }
            }
        }
        foreach (var o in a.Objectives) o.Gametype = a.Gametype;
        return a.Map.Length > 0 ? a : null;
    }

    /// <summary>From the sweep's hits (every copy of every chunk, stale ones included): the newest scan
    /// stamped at/after <paramref name="since"/> for <paramref name="map"/> whose chunks are ALL present.</summary>
    public static SpawnAtlas? FromHits(IEnumerable<MemoryScanner.Hit> hits, long since, string map)
    {
        var parsed = new List<(long Stamp, int I, int N, string Rec)>();
        foreach (var h in hits)
        {
            if (h.Tick < since) continue;
            var p = h.Body.Split('|', 4);    // <map>|<i>|<n>|<records>
            if (p.Length < 4 || !int.TryParse(p[1], out var i) || !int.TryParse(p[2], out var n) || n <= 0 || i < 0 || i >= n) continue;
            if (map.Length > 0 && !string.Equals(p[0], map, StringComparison.OrdinalIgnoreCase)) continue;
            parsed.Add((h.Tick, i, n, p[3]));
        }
        foreach (var g in parsed.GroupBy(x => x.Stamp).OrderByDescending(g => g.Key))
        {
            var n = g.Max(x => x.N);
            var byI = new string?[n];
            foreach (var x in g) if (x.N == n) byI[x.I] = x.Rec;
            if (byI.Any(b => b == null)) continue;
            var a = Parse(byI!, g.Key);
            if (a != null) return a;
        }
        return null;
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// analysis
// ═════════════════════════════════════════════════════════════════════════════

/// <summary>One mode's spawn set on a map: markers, authored starts per side, respawn pool per side.</summary>
public sealed class ModeRow
{
    public string Key { get; init; } = "";
    public string Label { get; init; } = "";
    public string UsedBy { get; init; } = "";
    public int Markers { get; init; }
    public int StartsA { get; init; }
    public int StartsB { get; init; }
    public int StartsEither { get; init; }
    public int RespawnA { get; init; }
    public int RespawnB { get; init; }
    public int RespawnEither { get; init; }
    public bool IsSub { get; init; }
    public string StartsText => StartsA + StartsB == 0 ? "—" : $"{StartsA} + {StartsB}";
    public string RespawnText => RespawnA + RespawnB == 0 ? "—" : $"{RespawnA} + {RespawnB}";
    /// <summary>Starts / respawns with no side (.group_index 0): usable by either team.</summary>
    public string EitherText => StartsEither + RespawnEither == 0 ? "—" : StartsEither > 0 ? $"{RespawnEither} +{StartsEither}s" : $"{RespawnEither}";
    public string Tip => (UsedBy.Length > 0 ? "Used by: " + UsedBy + "\n" : "") +
                         "Starts = markers with this mode's flag AND the start flag, by side (.group_index): where the mode OPENS.\n" +
                         "Respawns = the mode's markers without the start flag: its MID-MATCH respawn pool (the engine's auto_normal list).";
}

/// <summary>A dense area: spawn points bunched inside one radius / height band.</summary>
public sealed class SpawnArea
{
    public int Id { get; init; }
    public List<AtlasPoint> Points { get; init; } = new();
    public double X { get; init; }
    public double Y { get; init; }
    public double Z { get; init; }
    public double R { get; init; }
    public double ZSpread { get; init; }
    public int Starts => Points.Count(p => p.Kind == "M" && p.Start);
    public string Modes { get; init; } = "";
    /// <summary>The GSC area spec "x,y,z,r,zr" that re-selects these points in game.</summary>
    public int[] Spec => new[] { (int)Math.Round(X), (int)Math.Round(Y), (int)Math.Round(Z), (int)Math.Ceiling(R + 24), Math.Max(64, (int)Math.Ceiling(ZSpread + 32)) };
    public string Label => $"area {Id} · {Points.Count} spots · r {R:0}" + (Modes.Length > 0 ? " · " + Modes : "");

    public static SpawnArea Of(int id, List<AtlasPoint> pts)
    {
        var x = pts.Average(p => p.X);
        var y = pts.Average(p => p.Y);
        var z = pts.Average(p => p.Z);
        var r = pts.Max(p => Math.Sqrt(p.Dist2(x, y)));
        var zs = pts.Max(p => Math.Abs(p.Z - z));
        var modes = SpawnModes.Core.Select(m => (m, n: pts.Count(m.In))).Where(t => t.n > 0).OrderByDescending(t => t.n).Take(3)
                                   .Select(t => t.m.Label);
        return new SpawnArea { Id = id, Points = pts, X = x, Y = y, Z = z, R = r, ZSpread = zs, Modes = string.Join(" ", modes) };
    }

    /// <summary>What the game would arm for this area (the GSC's spawn_pick_points over the pick pool).</summary>
    public List<AtlasPoint> InGame(SpawnAtlas a)
    {
        var s = Spec;
        var r2 = (double)s[3] * s[3];
        return a.PickPool().Where(p => Math.Abs(p.Z - s[2]) <= s[4] && p.Dist2(s[0], s[1]) <= r2).ToList();
    }
}

/// <summary>A per-map spawn pick, as stored (picks.json) and as sent (gf_sp_map / gf_sp_a / gf_sp_b).</summary>
public sealed class SpawnPick
{
    /// <summary>1-7 a family's authored starts (gf_spawn_family numbering), 9 area, 10 stock.</summary>
    public int Kind { get; set; }
    public int[]? A { get; set; }
    public int[]? B { get; set; }
    public string Label { get; set; } = "";
    public DateTime At { get; set; }

    public string KindText => Kind switch { 9 => "area", 10 => "stock", _ => SpawnModes.FamilyName(Kind) + " starts" };

    /// <summary>The bridge lines: the areas first, the map key LAST (it arms the pick).</summary>
    public List<string> Lines(string map)
    {
        var l = new List<string>();
        static string V(int[] v) => string.Join(",", v.Select(x => x.ToString(CultureInfo.InvariantCulture)));
        if (Kind == 9 && A != null && B != null)
        {
            l.Add("set gf_sp_a " + V(A));
            l.Add("set gf_sp_b " + V(B));
        }
        l.Add($"set gf_sp_map {map}:{Kind}");
        return l;
    }
}

/// <summary>One way the two teams could start: two point sets + where it came from + how to pick it.</summary>
public sealed class SpawnLayout
{
    public string Source { get; init; } = "";
    public string Why { get; init; } = "";
    /// <summary>family / area / stock</summary>
    public string Kind { get; init; } = "area";
    public int Family { get; init; }
    public List<AtlasPoint> A { get; init; } = new();
    public List<AtlasPoint> B { get; init; } = new();
    public SpawnArea? AreaA { get; init; }
    public SpawnArea? AreaB { get; init; }
    public double Score { get; init; }
    /// <summary>What the game would arm for this pick (area picks re-select by radius, so it can differ):
    /// the plot halos these, so what is shown is what the game uses.</summary>
    public List<AtlasPoint> GameAPoints { get; set; } = new();
    public List<AtlasPoint> GameBPoints { get; set; } = new();
    public int GameA => GameAPoints.Count;
    public int GameB => GameBPoints.Count;
    public string Tag { get; set; } = "";

    public double AX => A.Count > 0 ? A.Average(p => p.X) : 0;
    public double AY => A.Count > 0 ? A.Average(p => p.Y) : 0;
    public double AZ => A.Count > 0 ? A.Average(p => p.Z) : 0;
    public double BX => B.Count > 0 ? B.Average(p => p.X) : 0;
    public double BY => B.Count > 0 ? B.Average(p => p.Y) : 0;
    public double BZ => B.Count > 0 ? B.Average(p => p.Z) : 0;
    public double Separation => Math.Sqrt((AX - BX) * (AX - BX) + (AY - BY) * (AY - BY));
    public double Dz => Math.Abs(AZ - BZ);
    public int MinSide => Math.Min(A.Count, B.Count);
    public string Metrics => $"{A.Count} + {B.Count} spots · {Separation:0}u apart" + (Dz >= 96 ? $" · {Dz:0}u height gap" : "") +
                             (Kind == "area" && (GameA != A.Count || GameB != B.Count) ? $" · game arms {GameA} + {GameB}" : "");

    public SpawnPick ToPick() => Kind switch
    {
        "family" => new SpawnPick { Kind = Family },
        "stock" => new SpawnPick { Kind = 10 },
        _ => new SpawnPick { Kind = 9, A = (AreaA ?? SpawnArea.Of(0, A)).Spec, B = (AreaB ?? SpawnArea.Of(0, B)).Spec },
    };
}

public static class SpawnAnalysis
{
    /// <summary>Fill a layout's in-game sets: an area pick re-selects every pick-pool point inside each area's
    /// radius / band (spawn_pick_points); a family or stock pick arms exactly its own points.</summary>
    public static void Arm(SpawnAtlas a, SpawnLayout l)
    {
        if (l.Kind == "area")
        {
            l.GameAPoints = (l.AreaA ?? (l.A.Count > 0 ? SpawnArea.Of(0, l.A) : null))?.InGame(a) ?? new List<AtlasPoint>();
            l.GameBPoints = (l.AreaB ?? (l.B.Count > 0 ? SpawnArea.Of(0, l.B) : null))?.InGame(a) ?? new List<AtlasPoint>();
        }
        else { l.GameAPoints = l.A; l.GameBPoints = l.B; }
    }

    /// <summary>Every mode flag present on the map (Core first, then the objective sub-sets and zones).</summary>
    public static List<ModeRow> Modes(SpawnAtlas a)
    {
        var rows = new List<ModeRow>();
        foreach (var m in SpawnModes.All)
        {
            var pts = a.Markers.Where(m.In).ToList();
            if (pts.Count == 0) continue;
            rows.Add(new ModeRow
            {
                Key = m.Key, Label = m.Label, UsedBy = m.UsedBy, Markers = pts.Count, IsSub = m.Word != 1,
                StartsA = pts.Count(p => p.Start && p.Group == 1), StartsB = pts.Count(p => p.Start && p.Group == 2),
                StartsEither = pts.Count(p => p.Start && p.Group is not (1 or 2)),
                RespawnA = pts.Count(p => !p.Start && p.Group == 1), RespawnB = pts.Count(p => !p.Start && p.Group == 2),
                RespawnEither = pts.Count(p => !p.Start && p.Group is not (1 or 2)),
            });
        }
        return rows;
    }

    /// <summary>The GSC's mod_family_starts: a family's AUTHORED starts, split by side. S&D = the largest
    /// spawn group a side when both have 2+; else flagged markers (flag + start + group 1/2) plus the
    /// legacy-named starts.</summary>
    public static (List<AtlasPoint> A, List<AtlasPoint> B, bool Groups) FamilyStarts(SpawnAtlas a, int fam)
    {
        if (fam == 2)
        {
            var (g1, g2) = LargestGroups(a);
            if (g1.Count >= 2 && g2.Count >= 2) return (g1, g2, true);
        }
        var mode = SpawnModes.ByFamily(fam);
        var A = new List<AtlasPoint>();
        var B = new List<AtlasPoint>();
        foreach (var p in a.Markers.Concat(a.Named))
        {
            var side = p.Kind == "N" ? SpawnNames.GscNamedSide(p.Name, fam) : 0;
            if (side == 0 && p.Kind == "M" && mode != null && mode.In(p) && p.Start) side = p.Group;
            if (side == 1) A.Add(p); else if (side == 2) B.Add(p);
        }
        return (A, B, false);
    }

    /// <summary>The largest S&D spawn group a side (mod_spawn_groups + mod_group_largest).</summary>
    public static (List<AtlasPoint> A, List<AtlasPoint> B) LargestGroups(SpawnAtlas a)
    {
        List<AtlasPoint> Best(int side) => a.Groups.Where(g => g.Side == side && g.Target != "-" && g.Target.Length > 0)
            .Select(g => a.GroupPoints.Where(q => q.Index == g.Id).ToList())
            .Where(l => l.Count > 0).OrderByDescending(l => l.Count).FirstOrDefault() ?? new List<AtlasPoint>();
        return (Best(1), Best(2));
    }

    /// <summary>The GSC's mod_family_auto (widened 2026-09-22): the first family whose authored starts cover
    /// the team size on both sides, S&D, TDM, CTF, DOM, Control, Hardpoint; else the most a side if 2+; else TDM.</summary>
    public static int AutoFamily(SpawnAtlas a, int teamSize)
    {
        var need = Math.Max(2, teamSize);
        int best = 1, bestMin = 0;
        foreach (var f in new[] { 2, 1, 4, 3, 6, 5 })
        {
            var (A, B, _) = FamilyStarts(a, f);
            var m = Math.Min(A.Count, B.Count);
            if (m >= need) return f;
            if (m > bestMin) { bestMin = m; best = f; }
        }
        return bestMin >= 2 ? best : 1;
    }

    /// <summary>Did the scan run under a mode that registers the tdm spawn type, as Gunfight does
    /// (gunfight / tdm / kill confirmed / prop hunt / dropkick / fireteam / clean)? Only then are its live
    /// engine lists the lists Gunfight uses.</summary>
    public static bool ScannedUnderTdmType(SpawnAtlas a)
    {
        var gt = a.Gametype.ToLowerInvariant();
        return gt.StartsWith("gunfight") || gt.StartsWith("tdm") || gt.StartsWith("conf") || gt.StartsWith("prop")
            || gt.StartsWith("dropkick") || gt.StartsWith("fireteam") || gt == "clean";
    }

    /// <summary>The engine's Gunfight start list per side. From the scan's live lists when the scan ran under a
    /// tdm-type mode; otherwise (MEASURED 2026-09-22: a Nuketown scan under dm read dm's start_spawn 1/1) rebuilt
    /// from the markers the way the engine builds start_spawn: the tdm flag + the start flag, by .group_index.</summary>
    public static (int A, int B, bool FromLists) EngineStarts(SpawnAtlas a)
    {
        if (ScannedUnderTdmType(a) && a.Lists.Count > 0)
            return (a.Lists.FirstOrDefault(l => l.Name == "start_spawn" && l.Side == 1)?.Size ?? 0,
                    a.Lists.FirstOrDefault(l => l.Name == "start_spawn" && l.Side == 2)?.Size ?? 0, true);
        var tdm = SpawnModes.ByKey("tdm")!;
        return (a.Markers.Count(p => tdm.In(p) && p.Start && p.Group == 1), a.Markers.Count(p => tdm.In(p) && p.Start && p.Group == 2), false);
    }

    /// <summary>A dense-area radius that fits the map: 6 % of the points' spread, 200-800 units (a 650 default
    /// swallowed 188 of Nuketown's 545 points in one area).</summary>
    public static double AutoRadius(SpawnAtlas a)
    {
        var pts = a.AllPoints.ToList();
        if (pts.Count < 2) return 500;
        double w = pts.Max(p => p.X) - pts.Min(p => p.X), h = pts.Max(p => p.Y) - pts.Min(p => p.Y);
        return Math.Clamp(Math.Sqrt(w * w + h * h) * 0.06, 200, 800);
    }

    /// <summary>What the mod does on this map with no pick: guard / family as given (live config).</summary>
    public static string Predict(SpawnAtlas a, int guard, int family, int teamSize)
    {
        if (guard == 0) return "Spawn guard OFF: stock spawns (the engine's start list; the map-centre pile where it has none).";
        var fam = family == 8 ? AutoFamily(a, teamSize) : family;
        var (A, B, groups) = fam > 0 ? FamilyStarts(a, fam) : (new List<AtlasPoint>(), new List<AtlasPoint>(), false);
        var anchors = fam == 0 ? "the geometric split" :
                      A.Count >= 2 && B.Count >= 2 ? $"{SpawnModes.FamilyName(fam)} {(groups ? "spawn groups" : "authored starts")} {A.Count} + {B.Count}" :
                      $"{SpawnModes.FamilyName(fam)} markers split geometrically (no authored starts)";
        if (guard == 2)
        {
            var (ea, eb, fromLists) = EngineStarts(a);
            var src = fromLists ? $"read live under {a.Gametype}" : $"TDM-flagged start markers - this scan ran under {a.Gametype}, whose own lists are not Gunfight's";
            if (ea > 0 && eb > 0) return $"AUTO: the engine's own Gunfight start spawns ({ea} + {eb}, {src}) - stock Gunfight on this map. (Anchors, used only if the engine had none: {anchors}.)";
            return $"AUTO: the engine has NO Gunfight start spawns here ({src}), so the mod places everyone on {anchors}.";
        }
        return $"FORCE: every spawn on {anchors}.";
    }

    /// <summary>Dense areas over the pick pool: greedy - the point with the most neighbours inside the
    /// radius / height band becomes an area (re-centred once), its points are taken, repeat.</summary>
    public static List<SpawnArea> Areas(SpawnAtlas a, double radius, double zBand, int minCount, int max = 40)
    {
        var pool = a.PickPool();
        var free = new bool[pool.Count];
        Array.Fill(free, true);
        var r2 = radius * radius;
        var areas = new List<SpawnArea>();

        List<int> Near(double x, double y, double z)
        {
            var l = new List<int>();
            for (var k = 0; k < pool.Count; k++)
                if (free[k] && Math.Abs(pool[k].Z - z) <= zBand && pool[k].Dist2(x, y) <= r2) l.Add(k);
            return l;
        }

        while (areas.Count < max)
        {
            List<int>? best = null;
            for (var i = 0; i < pool.Count; i++)
            {
                if (!free[i]) continue;
                var nb = Near(pool[i].X, pool[i].Y, pool[i].Z);
                if (best == null || nb.Count > best.Count) best = nb;
            }
            if (best == null || best.Count < Math.Max(2, minCount)) break;
            var cx = best.Average(k => pool[k].X);
            var cy = best.Average(k => pool[k].Y);
            var cz = best.Average(k => pool[k].Z);
            var refined = Near(cx, cy, cz);
            if (refined.Count >= best.Count) best = refined;
            foreach (var k in best) free[k] = false;
            areas.Add(SpawnArea.Of(areas.Count + 1, best.Select(k => pool[k]).ToList()));
        }
        return areas;
    }

    /// <summary>Every start layout worth showing: each mode's authored starts, the BO2-named sets, the S&D
    /// group pairs, the engine's own start list, and the best pairs of dense areas. Ranked: the ones that
    /// cover the team size first, then by separation.</summary>
    public static List<SpawnLayout> Layouts(SpawnAtlas a, List<SpawnArea> areas, int teamSize)
    {
        var need = Math.Max(2, teamSize);
        var outl = new List<SpawnLayout>();

        // 1. each mode's authored starts (flag + start + side), exactly what that mode opens on
        foreach (var m in SpawnModes.Core)
        {
            if (m.Family > 0)
            {
                var (A, B, groups) = FamilyStarts(a, m.Family);
                if (A.Count == 0 || B.Count == 0) continue;
                outl.Add(new SpawnLayout
                {
                    Source = groups ? "S&D spawn groups (largest a side)" : m.Label + " starts",
                    Why = groups ? "the S&D bases the map ships (spawn_group_marker groups)" :
                          $"markers flagged {m.Key} + start, sides from .group_index" + (A.Concat(B).Any(p => p.Kind == "N") ? " + the BO2-named start structs" : ""),
                    Kind = "family", Family = m.Family, A = A, B = B,
                });
            }
            else
            {
                var A = a.Markers.Where(p => m.In(p) && p.Start && p.Group == 1).ToList();
                var B = a.Markers.Where(p => m.In(p) && p.Start && p.Group == 2).ToList();
                if (A.Count == 0 || B.Count == 0) continue;
                outl.Add(new SpawnLayout { Source = m.Label + " starts", Why = $"markers flagged {m.Key} + start (no GSC family: picked as two areas)", Kind = "area", A = A, B = B });
            }
        }

        // 2. BO2-named war starts (the other named sets fold into their family above)
        {
            var A = a.Named.Where(p => p.Name == "mp_twar_spawn_allies_start").ToList();
            var B = a.Named.Where(p => p.Name == "mp_twar_spawn_axis_start").ToList();
            if (A.Count > 0 && B.Count > 0) outl.Add(new SpawnLayout { Source = "BO2 war starts", Why = "mp_twar_spawn_allies/axis_start structs", Kind = "area", A = A, B = B });
        }

        // 3. every pair of S&D groups (one per side): the selectable bases
        var g1 = a.Groups.Where(g => g.Side == 1).ToList();
        var g2 = a.Groups.Where(g => g.Side == 2).ToList();
        foreach (var x in g1)
            foreach (var y in g2)
            {
                var A = a.GroupPoints.Where(q => q.Index == x.Id).ToList();
                var B = a.GroupPoints.Where(q => q.Index == y.Id).ToList();
                if (A.Count == 0 || B.Count == 0) continue;
                outl.Add(new SpawnLayout
                {
                    Source = $"S&D group {x.Id} × {y.Id}", Why = $"spawn groups {x.Target} ({x.Objective}) vs {y.Target} ({y.Objective})",
                    Kind = "area", A = A, B = B,
                });
            }

        // 4. the engine's own Gunfight start list (only when the scan ran under a tdm-type mode - under dm the
        //    live start list is dm's, not what Gunfight would use)
        var es1 = a.Lists.FirstOrDefault(l => l.Name == "start_spawn" && l.Side == 1);
        var es2 = a.Lists.FirstOrDefault(l => l.Name == "start_spawn" && l.Side == 2);
        if (ScannedUnderTdmType(a) && es1 != null && es2 != null && es1.Members.Count + es1.Extra.Count > 0 && es2.Members.Count + es2.Extra.Count > 0)
        {
            var byIdx = a.Markers.ToDictionary(p => p.Index);
            List<AtlasPoint> Pts(AtlasList l) => l.Members.Where(byIdx.ContainsKey).Select(i => byIdx[i])
                .Concat(l.Extra.Select(v => new AtlasPoint { Kind = "M", Index = -1, X = v[0], Y = v[1], Z = v[2] })).ToList();
            outl.Add(new SpawnLayout
            {
                Source = "Engine start list (stock Gunfight)", Why = $"getspawnlists start_spawn under {a.Gametype} - what stock uses; a STOCK pick hands the map back to it",
                Kind = "stock", A = Pts(es1), B = Pts(es2),
            });
        }

        // 5. the best pairs of dense areas
        var big = areas.Where(x => x.Points.Count >= need).ToList();
        var pairs = new List<(SpawnArea X, SpawnArea Y, double Score)>();
        for (var i = 0; i < big.Count; i++)
            for (var j = i + 1; j < big.Count; j++)
            {
                var x = big[i]; var y = big[j];
                var sep = Math.Sqrt((x.X - y.X) * (x.X - y.X) + (x.Y - y.Y) * (x.Y - y.Y));
                if (sep < 900) continue;
                var dz = Math.Abs(x.Z - y.Z);
                var score = Math.Min(x.Points.Count, y.Points.Count) * 250 + Math.Min(sep, 6000) - dz * 2 - (x.R + y.R) * 0.3;
                pairs.Add((x, y, score));
            }
        foreach (var (x, y, score) in pairs.OrderByDescending(p => p.Score).Take(12))
            outl.Add(new SpawnLayout
            {
                Source = $"Dense areas {x.Id} × {y.Id}", Why = $"{x.Label}\n{y.Label}",
                Kind = "area", A = x.Points, B = y.Points, AreaA = x, AreaB = y, Score = score,
            });

        // what the game would arm for each pick
        foreach (var l in outl) Arm(a, l);

        return outl.OrderByDescending(l => Math.Min(l.GameA, l.GameB) >= need)
                   .ThenBy(l => l.Kind == "area" && l.Source.StartsWith("Dense") ? 1 : 0)
                   .ThenByDescending(l => l.Separation)
                   .ToList();
    }
}
