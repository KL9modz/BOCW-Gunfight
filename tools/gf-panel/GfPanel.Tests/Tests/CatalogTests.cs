using System.Text.RegularExpressions;
using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>Lists the panel sends by INDEX (a name would overflow the 47-byte slot): the index means whatever
/// the GSC's table has at that row, so the two tables must match row for row.</summary>
public static class CatalogTests
{
    [Test]
    public static void Vehicles_match_veh_master_row_for_row()
    {
        var gsc = Gsc.VehicleRows();
        Check.True(gsc.Count > 50, $"veh_master parse found only {gsc.Count} rows");
        var p = new Problems();
        for (var i = 0; i < Math.Max(gsc.Count, Catalog.Vehicles.Length); i++)
        {
            var g = i < gsc.Count ? gsc[i] : ("(none)", -1);
            var c = i < Catalog.Vehicles.Length ? Catalog.Vehicles[i] : null;
            if (c == null) { p.Add($"row {i}: GSC \"{g.Item1}\" has no Catalog.Vehicles row"); continue; }
            if (c.Index != i) p.Add($"row {i}: Catalog.Vehicles index {c.Index}");
            if (c.Label != g.Item1 || c.Kind != g.Item2) p.Add($"row {i}: panel \"{c.Label}\" kind {c.Kind}, GSC \"{g.Item1}\" kind {g.Item2}");
        }
        p.ThrowIfAny("vehspawn index table");
    }

    [Test]
    public static void Fun_grenade_picks_match_fun_nade_pick()
    {
        var gsc = Gsc.NumberedCases("fun_nade_pick").Select(c => Regex.Match(c, @"s\.label\s*=\s*""([^""]*)""").Groups[1].Value).ToList();
        CheckPicks(Catalog.FunNades, gsc, (panel, g) => panel.StartsWith(g, StringComparison.OrdinalIgnoreCase), "fun_nade_pick");
    }

    [Test]
    public static void Fun_cannon_picks_match_fun_cannon_pick()
    {
        var gsc = Gsc.NumberedCases("fun_cannon_pick").Select(c => Regex.Match(c, @"s\.label\s*=\s*""([^""]*)""").Groups[1].Value).ToList();
        CheckPicks(Catalog.FunCannonModels, gsc, (panel, g) => string.Equals(panel, g, StringComparison.OrdinalIgnoreCase), "fun_cannon_pick");
    }

    [Test]
    public static void Fun_disguise_picks_match_fun_disg_pick()
    {
        var gsc = Gsc.NumberedCases("fun_disg_pick").Select(c => Regex.Match(c, @"return\s+""([^""]*)""").Groups[1].Value).ToList();
        // the GSC returns the model: "Oil drum" must name p9_rus_oil_drum_01, "Dog tags" p9_dogtags_...
        CheckPicks(Catalog.FunDisguises, gsc, (panel, model) =>
        {
            var w = panel.ToLowerInvariant();
            return model.Contains(w.Replace(' ', '_'), StringComparison.Ordinal) || model.Contains(w.Replace(" ", ""), StringComparison.Ordinal);
        }, "fun_disg_pick");
    }

    private static void CheckPicks(Named[] panel, List<string> gsc, Func<string, string, bool> same, string fn)
    {
        var p = new Problems();
        if (panel.Length != gsc.Count) p.Add($"panel has {panel.Length} rows, {fn}() has {gsc.Count} cases");
        for (var i = 0; i < Math.Min(panel.Length, gsc.Count); i++)
        {
            if (panel[i].Value != i.ToString()) p.Add($"row {i}: panel sends index {panel[i].Value}");
            if (!same(panel[i].Label, gsc[i])) p.Add($"row {i}: panel \"{panel[i].Label}\", {fn} case {i} \"{gsc[i]}\"");
        }
        p.ThrowIfAny(fn);
    }
}
