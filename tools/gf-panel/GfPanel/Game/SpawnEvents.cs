using System.Globalization;
using GfPanel.Native;

namespace GfPanel.Game;

/// <summary>One spawn that happened in the match (gunfight_menu.gsc spawnev_add): who, where, facing which
/// way, in which order this round, and how the mod placed them.</summary>
public sealed record SpawnEvent(long Match, int Round, int Order, int Ent, int Team, double X, double Y, double Z, int Yaw,
                                char How, string Slot, bool Bot, string Name)
{
    public string HowText => How switch
    {
        'e' => "the engine's start picker",
        'a' => Slot != "-" ? $"the mod's anchors, slot {Slot}" : "the mod's anchors",
        _ => "the stock spawn path",
    };
    public string TeamText => Team switch { 1 => "allies", 2 => "axis", _ => "no team" };
    public string Key => $"{Match}/{Round}/{Order}";

    public string Describe(AtlasPoint? spot) =>
        $"#{Order}  {Name}{(Bot ? " (bot)" : "")} · {TeamText} · round {Round + 1}\n" +
        $"placed by {HowText}\n({X:0}, {Y:0}, {Z:0})  yaw {Yaw}" +
        (spot != null ? $"\non {(spot.Kind == "M" ? $"marker #{spot.Index}" : spot.Kind == "N" ? spot.Name : $"S&D group {spot.Index} point")}" +
                        (spot.Kind == "M" ? (spot.Start ? " (a start)" : " (a respawn)") : "") : "\nno scanned spot within 48u");
}

/// <summary>The GFSPAWNED channel: the match's spawn events in chunks, like the atlas.</summary>
public static class SpawnEvents
{
    /// <summary>The newest complete publish for <paramref name="map"/>: (match id, version, events). null when no complete set.</summary>
    public static (long Match, long Ver, List<SpawnEvent> Events)? FromHits(IEnumerable<MemoryScanner.Hit> hits, string map)
    {
        var parsed = new List<(long Stamp, int I, int N, string Rec)>();
        foreach (var h in hits)
        {
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
            var r = Parse(string.Join(";", byI!));
            if (r != null) return r;
        }
        return null;
    }

    private static (long Match, long Ver, List<SpawnEvent> Events)? Parse(string records)
    {
        long match = -1, ver = 0;
        var list = new List<SpawnEvent>();
        foreach (var rec in records.Split(';'))
        {
            if (rec.Length < 2) continue;
            var f = rec.Split(',');
            if (f[0] == "V" && f.Length >= 3)
            {
                long.TryParse(f[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out match);
                long.TryParse(f[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out ver);
                continue;
            }
            if (f[0] != "E" || f.Length < 13) continue;
            int I(int k) => int.TryParse(f[k], NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 0;
            list.Add(new SpawnEvent(match, I(1), I(2), I(3), I(4), I(5), I(6), I(7), I(8),
                f[9].Length > 0 ? f[9][0] : 's', f[10], f[11] == "1", string.Join(",", f.Skip(12))));
        }
        return match < 0 ? null : (match, ver, list);
    }
}
