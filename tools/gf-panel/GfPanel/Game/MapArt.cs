using System.Security.Cryptography;
using System.Text;

namespace GfPanel.Game;

/// <summary>One picture of a map: the in-game tactical map as the Call of Duty wiki hosts it
/// ("&lt;Map&gt; MiniMap BOCW.png", 3840x2160 full-screen captures of the in-game map, every Cold War map,
/// Strike and 12v12 layouts separately), or a file the user picked (Custom).</summary>
public sealed record MapArtDef(string File, string Label, string? Custom = null)
{
    public override string ToString() => Label;
}

public static class MapArt
{
    // map -> its pictures, the one the map loads under GUNFIGHT first (Armada / Collateral load their Strike
    // layout under gunfight, Crossroads the full map - map-audit-facts). Every file below exists on the wiki
    // (File: search 2026-09-22: 66 hits, all 36 MP maps + the 5 Fireteam maps).
    private static readonly Dictionary<string, MapArtDef[]> Table = new(StringComparer.OrdinalIgnoreCase)
    {
        ["mp_amerika"] = One("Amerika"),
        ["mp_apocalypse"] = One("Apocalypse"),
        ["mp_black_sea"] = new[] { Def("ArmadaStrike", "Armada Strike (6v6 layout)"), Def("Armada", "Armada (12v12 layout)") },
        ["mp_cartel"] = One("Cartel"),
        ["mp_cliffhanger"] = One("Yamantau"),
        ["mp_drivein_rm"] = One("DriveIn", "Drive-In"),
        ["mp_dune"] = new[] { Def("CollateralStrike", "Collateral Strike (6v6 layout)"), Def("Collateral", "Collateral (12v12 layout)") },
        ["mp_echelon"] = One("Echelon"),
        ["mp_express_rm"] = One("Express"),
        ["mp_firebase"] = One("Deprogram"),
        ["mp_hijacked_rm"] = One("Hijacked"),
        ["mp_jungle_rm"] = One("Jungle"),
        ["mp_kgb"] = One("Checkmate"),
        ["mp_mall"] = One("ThePines", "The Pines"),
        ["mp_miami"] = One("Miami"),
        ["mp_miami_strike"] = One("MiamiStrike", "Miami Strike"),
        ["mp_moscow"] = new[] { Def("Moscow New", "Moscow (current)"), Def("Moscow Old", "Moscow (launch version)") },
        ["mp_nuketown6"] = One("Nuketown84", "Nuketown '84"),
        ["mp_paintball_rm"] = One("Rush"),
        ["mp_raid_rm"] = new[] { new MapArtDef("Raid Minimap BOCW.png", "Raid") },
        ["mp_russianbase_rm"] = One("WMD"),
        ["mp_satellite"] = One("Satellite"),
        ["mp_slums_rm"] = One("Slums"),
        ["mp_tank"] = One("Garrison"),
        ["mp_tundra"] = new[] { Def("Crossroads", "Crossroads (full map)"), Def("CrossroadsStrike", "Crossroads Strike") },
        ["mp_village_rm"] = One("Standoff"),
        ["mp_zoo_rm"] = One("Zoo"),
        ["mp_sm_amsterdam"] = One("Amsterdam"),
        ["mp_sm_berlin_tunnel"] = One("UBahn", "U-Bahn"),
        ["mp_sm_central"] = One("ICBM"),
        ["mp_sm_deptstore"] = One("Showroom"),
        ["mp_sm_finance"] = One("KGB"),
        ["mp_sm_game_show"] = One("GameShow", "Game Show"),
        ["mp_sm_gas_station"] = One("Diesel"),
        ["mp_sm_market"] = One("Mansion"),
        ["mp_sm_vault"] = One("Gluboko"),
        ["wz_ski_slopes"] = One("Alpine"),
        ["wz_duga"] = One("Duga"),
        ["wz_golova"] = One("Golova"),
        ["wz_forest"] = One("Ruka"),
        ["wz_sanatorium"] = One("Sanatorium"),
    };

    private static MapArtDef Def(string stem, string label) => new(stem + " MiniMap BOCW.png", label);
    private static MapArtDef[] One(string stem, string? label = null) => new[] { Def(stem, label ?? stem) };

    /// <summary>The known pictures of a map (empty for an unknown map); the gunfight layout first.</summary>
    public static IReadOnlyList<MapArtDef> For(string map) => Table.TryGetValue(map, out var d) ? d : Array.Empty<MapArtDef>();

    /// <summary>The wiki CDN address: MediaWiki's hashed upload path (md5 of the file name, spaces as
    /// underscores), scaled server-side, PNG (format=original - the default serves WebP, which WPF cannot decode).</summary>
    public static string Url(string file, int width)
    {
        var name = file.Replace(' ', '_');
        var h = Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(name))).ToLowerInvariant();
        return $"https://static.wikia.nocookie.net/callofduty/images/{h[0]}/{h[..2]}/{Uri.EscapeDataString(name)}/revision/latest/scale-to-width-down/{width}?format=original";
    }
}
