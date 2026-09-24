using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using GfPanel.Native;

namespace GfPanel.Game;

// The RACING page's model (2026-09-24, docs/notes/racing.md §11): the game's track (GFTRACK), the live race
// (GFRACE), the editor's bridge arguments and the saved-track library. UI-free, so GfPanel.Tests compiles it.

/// <summary>A race gate as the game stores it (gunfight_menu.gsc race_gate_make): centre, the travel yaw in the
/// game's degrees (0 = +x, 90 = +y), width in units. The two posts sit across the travel direction.</summary>
public sealed record RaceGate(int X, int Y, int Z, int Yaw, int W)
{
    /// <summary>race_gate_app's clamp for a width the app sends.</summary>
    public const int MinWidth = 64, MaxWidth = 4000;

    /// <summary>"x,y,z,yaw,w" - the game's own text (race_gate_text: the gf_gp dvars, GFTRACK, racegate).</summary>
    public string Text => string.Create(CultureInfo.InvariantCulture, $"{X},{Y},{Z},{Yaw},{W}");

    public static RaceGate? Parse(string s)
    {
        var f = s.Split(',');
        if (f.Length < 5) return null;
        var v = new int[5];
        for (var i = 0; i < 5; i++)
            if (!int.TryParse(f[i].Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v[i])) return null;
        return new RaceGate(v[0], v[1], v[2], v[3], v[4]);
    }

    public (double X, double Y) Fwd { get { var a = Yaw * Math.PI / 180; return (Math.Cos(a), Math.Sin(a)); } }
    /// <summary>anglestoright: the forward turned a quarter clockwise (x east, y north: facing east, right is south).</summary>
    public (double X, double Y) Right { get { var a = Yaw * Math.PI / 180; return (Math.Sin(a), -Math.Cos(a)); } }
    public (double X, double Y) PostA { get { var r = Right; return (X - r.X * W / 2.0, Y - r.Y * W / 2.0); } }
    public (double X, double Y) PostB { get { var r = Right; return (X + r.X * W / 2.0, Y + r.Y * W / 2.0); } }

    /// <summary>The game's yaw range, -179..180.</summary>
    public static int NormYaw(double deg)
    {
        var d = Math.Round(deg) % 360;
        if (d > 180) d -= 360;
        if (d <= -180) d += 360;
        return (int)d;
    }

    /// <summary>The yaw facing from (x0, y0) towards (x1, y1).</summary>
    public static int YawTo(double x0, double y0, double x1, double y1) => NormYaw(Math.Atan2(y1 - y0, x1 - x0) * 180 / Math.PI);

    public static int ClampWidth(double w) => (int)Math.Clamp(Math.Round(w), MinWidth, MaxWidth);

    public RaceGate MovedTo(double x, double y) => this with { X = (int)Math.Round(x), Y = (int)Math.Round(y) };
    public RaceGate Turned(double byDeg) => this with { Yaw = NormYaw(Yaw + byDeg) };
    public RaceGate Widened(double by) => this with { W = ClampWidth(W + by) };

    /// <summary>A post dragged to (px, py): the width is twice its reach from the centre and the yaw turns so the
    /// posts stay across the travel direction (post B = centre + right x w/2, post A the other side).</summary>
    public RaceGate WithPost(bool postB, double px, double py)
    {
        double vx = px - X, vy = py - Y;
        var half = Math.Sqrt(vx * vx + vy * vy);
        if (half < 1) return this;
        double rx = vx / half, ry = vy / half;
        if (!postB) { rx = -rx; ry = -ry; }
        // right = (sin a, -cos a)  ->  a = atan2(rx, -ry)
        return this with { Yaw = NormYaw(Math.Atan2(rx, -ry) * 180 / Math.PI), W = ClampWidth(half * 2) };
    }

    /// <summary>The start grid slots behind this gate (race_grid_place): columns across at gap, rows 300 u apart
    /// from 200 u behind the line.</summary>
    public List<(double X, double Y)> GridSlots(int count, int gap)
    {
        var slots = new List<(double X, double Y)>();
        if (gap <= 0) return slots;
        var cols = Math.Max(1, (W - 100) / gap);
        var f = Fwd; var r = Right;
        for (var i = 0; i < count; i++)
        {
            int row = i / cols, col = i % cols;
            var lateral = (col - (cols - 1) * 0.5) * gap;
            var back = 200 + row * 300;
            slots.Add((X - f.X * back + r.X * lateral, Y - f.Y * back + r.Y * lateral));
        }
        return slots;
    }
}

/// <summary>The game's track - GFTRACK (race_track_build), every gate, never cut:
/// <c>GFTRACK|&lt;ver&gt;|&lt;i&gt;|&lt;n&gt;|&lt;map&gt;|&lt;count&gt;|&lt;gate&gt;;&lt;gate&gt;;...|END</c>.</summary>
public sealed class RaceTrack
{
    /// <summary>gunfight_menu.gsc race_max_gates() (4 gates packed to each of 16 dvars).</summary>
    public const int MaxGates = 64;

    public string Map { get; init; } = "";
    /// <summary>race_ver(): getrealtime() at the track's last change.</summary>
    public long Ver { get; init; }
    public List<RaceGate> Gates { get; init; } = new();

    /// <summary>The newest COMPLETE publish among every copy in memory; null when none is complete. A copy whose
    /// gates do not add up to its own count (a torn read) is skipped.</summary>
    public static RaceTrack? FromHits(IEnumerable<MemoryScanner.Hit> hits)
    {
        var parsed = new List<(long Ver, int I, int N, string Map, int Count, string Gates)>();
        foreach (var h in hits)
        {
            var p = h.Body.Split('|');     // i|n|map|count|gates
            if (p.Length < 5 || !int.TryParse(p[0], out var i) || !int.TryParse(p[1], out var n) || n <= 0 || i < 0 || i >= n
                || !int.TryParse(p[3], out var count) || count < 0) continue;
            parsed.Add((h.Tick, i, n, p[2], count, p[4]));
        }
        foreach (var g in parsed.GroupBy(x => x.Ver).OrderByDescending(g => g.Key))
        {
            var n = g.Max(x => x.N);
            var byI = new string?[n];
            var head = g.First(x => x.N == n);
            foreach (var x in g) if (x.N == n) byI[x.I] = x.Gates;
            if (byI.Any(b => b == null)) continue;
            var gates = byI.SelectMany(b => b!.Split(';', StringSplitOptions.RemoveEmptyEntries)).Select(RaceGate.Parse).ToList();
            if (gates.Any(x => x == null) || gates.Count != head.Count) continue;
            return new RaceTrack { Map = head.Map, Ver = g.Key, Gates = gates.Select(x => x!).ToList() };
        }
        return null;
    }
}

/// <summary>One player on the live line.</summary>
public sealed record RacePlayer(int EntNum, int X, int Y, int Yaw, string Flags, int Lap, int Next, int Place, int Tenths)
{
    public bool IsHost => Flags.Contains('h');
    public bool Riding => Flags.Contains('v');
    public bool Dead => Flags.Contains('d');
    public bool Spectator => Flags.Contains('s');
    /// <summary>In the current race (the race id matched).</summary>
    public bool Racing => Flags.Contains('r');
    public bool Finished => Flags.Contains('f');
    public bool OffTrack => Flags.Contains('o');
}

/// <summary>The live race - GFRACE (race_live_line), every 0.5 s while gf_race_live is 1:
/// <c>GFRACE|&lt;tick&gt;|&lt;st&gt;|&lt;laps&gt;|&lt;sprint&gt;|&lt;n&gt;|&lt;ver&gt;|&lt;el&gt;|&lt;ff&gt;|&lt;se&gt;|&lt;rec&gt;;...|END</c>,
/// rec = entnum,x,y,yaw,flags,lap,next,place,tenths.</summary>
public sealed class RaceLive
{
    public long Tick { get; init; }
    /// <summary>0 idle / 1 countdown / 2 running / 3 over (race_state().state).</summary>
    public int State { get; init; }
    public int Laps { get; init; }
    public bool Sprint { get; init; }
    public int GateCount { get; init; }
    public long TrackVer { get; init; }
    public int ElapsedMs { get; init; }
    /// <summary>Seconds the finish timer has left, -1 before the first finish.</summary>
    public int FinishLeft { get; init; } = -1;
    /// <summary>race_gates_save's read-back check: "" = fine, else "chunk:read/wrote" (a dvar cut short).</summary>
    public string StoreErr { get; init; } = "";
    public List<RacePlayer> Players { get; init; } = new();

    public string StateName => State switch { 1 => "countdown", 2 => "running", 3 => "over", _ => "idle" };

    public static RaceLive? Parse(long tick, string body)
    {
        var p = body.Split('|');     // st|laps|sprint|n|ver|el|ff|se|recs
        if (p.Length < 9) return null;
        static int I(string s, int d = 0) => int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : d;
        if (!int.TryParse(p[0], out var st)) return null;
        var players = new List<RacePlayer>();
        foreach (var rec in p[8].Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var f = rec.Split(',');
            if (f.Length < 9 || !int.TryParse(f[0], out var ent)) continue;
            players.Add(new RacePlayer(ent, I(f[1]), I(f[2]), I(f[3]), f[4], I(f[5]), I(f[6]), I(f[7]), I(f[8])));
        }
        return new RaceLive
        {
            Tick = tick, State = st, Laps = I(p[1], 1), Sprint = I(p[2]) != 0, GateCount = I(p[3]),
            TrackVer = long.TryParse(p[4], out var tv) ? tv : 0, ElapsedMs = I(p[5]), FinishLeft = I(p[6], -1), StoreErr = p[7], Players = players,
        };
    }

    /// <summary>m:ss.t, the game's race_clock.</summary>
    public static string Clock(int ms)
    {
        if (ms < 0) ms = 0;
        var s = ms / 1000;
        return $"{s / 60}:{s % 60:00}.{ms % 1000 / 100}";
    }
}

/// <summary>The editor's bridge arguments (the gf_cmd_arg slot takes Commands.MaxArgChars; the longest here is
/// "63,-45678,-45678,-179,4000" = 26).</summary>
public static class RaceArgs
{
    /// <summary>racegate: a whole gate, height included (a saved track).</summary>
    public static string Gate(RaceGate g) => g.Text;
    /// <summary>racegset / racegins: index + x, y, yaw, width - the game floors the height itself.</summary>
    public static string Edit(int index, RaceGate g) => string.Create(CultureInfo.InvariantCulture, $"{index},{g.X},{g.Y},{g.Yaw},{g.W}");
    /// <summary>racegmov: from, to.</summary>
    public static string Move(int from, int to) => string.Create(CultureInfo.InvariantCulture, $"{from},{to}");
}

/// <summary>A track in the panel's library (race-tracks.json; one per map + name). Gates are the game's own
/// "x,y,z,yaw,w" text, so a saved track goes back exactly as it came.</summary>
public sealed class SavedTrack
{
    public string Map { get; set; } = "";
    public string Name { get; set; } = "";
    public List<string> Gates { get; set; } = new();
    /// <summary>The course the track was built for: true = A to B (gf_race_sprint 1).</summary>
    public bool Sprint { get; set; }
    public int Laps { get; set; } = 1;
    public DateTime Saved { get; set; }

    [JsonIgnore] public List<RaceGate> GateList => Gates.Select(RaceGate.Parse).Where(g => g != null).Select(g => g!).ToList();
    [JsonIgnore] public string Label => $"{Name}  ·  {Gates.Count} gates{(Sprint ? " · A to B" : "")}";
}

public static class TrackLibrary
{
    public sealed class LibraryFile
    {
        public int Version { get; set; } = 1;
        public List<SavedTrack> Tracks { get; set; } = new();
    }

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static string ToJson(LibraryFile f) => JsonSerializer.Serialize(f, Json);

    public static LibraryFile? FromJson(string json)
    {
        try { return JsonSerializer.Deserialize<LibraryFile>(json); }
        catch (JsonException) { return null; }
    }

    /// <summary>The tracks.json the panel kept until 2026-09-24 (map -> name -> gates), as library entries.
    /// The old file is left alone (an older panel still reads it).</summary>
    public static List<SavedTrack> FromLegacy(string json)
    {
        try
        {
            var old = JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, List<string>>>>(json);
            if (old == null) return new();
            return old.SelectMany(m => m.Value.Select(t => new SavedTrack { Map = m.Key, Name = t.Key, Gates = t.Value.ToList() })).ToList();
        }
        catch (JsonException) { return new(); }
    }

    /// <summary>One track as a file to share.</summary>
    public static string Export(SavedTrack t) => JsonSerializer.Serialize(t, Json);

    /// <summary>A shared track file, checked: a map, a name, 1..MaxGates gates the game would take. Null + why otherwise.</summary>
    public static SavedTrack? Import(string json, out string why)
    {
        SavedTrack? t;
        try { t = JsonSerializer.Deserialize<SavedTrack>(json); }
        catch (JsonException e) { why = "not a track file: " + e.Message; return null; }
        if (t == null || string.IsNullOrWhiteSpace(t.Map) || string.IsNullOrWhiteSpace(t.Name)) { why = "not a track file (no map or name)"; return null; }
        if (t.Gates.Count == 0 || t.Gates.Count > RaceTrack.MaxGates) { why = $"{t.Gates.Count} gates - a track holds 1 to {RaceTrack.MaxGates}"; return null; }
        if (t.Gates.Any(g => RaceGate.Parse(g) == null)) { why = "a gate is not x,y,z,yaw,w"; return null; }
        why = "";
        return t;
    }
}

public enum TrackEditKind { Select, Set, Insert, Delete }

/// <summary>What the RACING page's map asks for: Select gate Index; Set gate Index := Gate (a move, turn or width);
/// Insert a new gate after Index (-1 = at the end) at X, Y; Delete gate Index.</summary>
public sealed record TrackEdit(TrackEditKind Kind, int Index, RaceGate? Gate = null, double X = 0, double Y = 0);

/// <summary>A player as the RACING page's map draws it.</summary>
public sealed record RaceDot(double X, double Y, int Yaw, string Name, string Info, bool IsHost, bool Racing, bool Finished, bool Dead, bool Riding);
