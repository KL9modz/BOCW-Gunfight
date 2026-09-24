using System.Globalization;
using GfPanel.Native;

namespace GfPanel.Game;

/// <summary>One entity the mod spawned that is still in the level (gunfight_menu.gsc ents_records): a prop, an
/// explosive barrel or a vehicle. Positions / distance come in 50-unit steps.</summary>
public sealed record GfEntity(char Kind, int EntNum, string Label, string Owner, int Dist, int X, int Y, int Z, string Flags)
{
    public bool IsVehicle => Kind == 'v';
    public bool IsProp => Kind is 'p' or 'b';
    public bool Occupied => Flags.Contains('o');
    public bool VehicleMode => Flags.Contains('m');
    public string KindText => Kind switch { 'v' => VehicleMode ? "Vehicle (mode ride)" : "Vehicle", 'b' => "Explosive barrel", _ => "Prop" };
    public string Icon => Kind switch { 'v' => "🚗", 'b' => "🛢", _ => "📦" };
    /// <summary>"480 u (12 m)" from the host; "-" when the host had no position.</summary>
    public string DistText => Dist < 0 ? "-" : $"{Dist} u ({Dist / 39.37:0} m)";
    public string OwnerText => Owner is "" or "-" ? "—" : Owner;
    public string Status => Occupied ? "occupied" : "";
}

/// <summary>GFENTS|&lt;stamp&gt;|&lt;i&gt;|&lt;n&gt;|&lt;rec&gt;;...|END - the spawned-entity list in chunks (ents_publish).
/// rec = kind,entnum,label,owner,dist,x,y,z,flags.</summary>
public static class EntityList
{
    /// <summary>The newest COMPLETE publish among every copy in memory: (stamp, entities). null when none is complete.</summary>
    public static (long Stamp, List<GfEntity> Items)? FromHits(IEnumerable<MemoryScanner.Hit> hits)
    {
        var parsed = new List<(long Stamp, int I, int N, string Rec)>();
        foreach (var h in hits)
        {
            var p = h.Body.Split('|', 3);    // <i>|<n>|<records>
            if (p.Length < 3 || !int.TryParse(p[0], out var i) || !int.TryParse(p[1], out var n) || n <= 0 || i < 0 || i >= n) continue;
            parsed.Add((h.Tick, i, n, p[2]));
        }
        foreach (var g in parsed.GroupBy(x => x.Stamp).OrderByDescending(g => g.Key))
        {
            var n = g.Max(x => x.N);
            var byI = new string?[n];
            foreach (var x in g) if (x.N == n) byI[x.I] = x.Rec;
            if (byI.Any(b => b == null)) continue;
            return (g.Key, Parse(string.Join(";", byI!)));
        }
        return null;
    }

    public static List<GfEntity> Parse(string records)
    {
        var list = new List<GfEntity>();
        foreach (var rec in records.Split(';'))
        {
            if (rec.Length < 3) continue;
            var f = rec.Split(',');
            if (f.Length < 9 || f[0].Length != 1) continue;
            int I(int k) => int.TryParse(f[k], NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 0;
            list.Add(new GfEntity(f[0][0], I(1), GfState.StripColors(f[2]), GfState.StripColors(f[3]), I(4), I(5), I(6), I(7), f[8]));
        }
        return list;
    }
}
