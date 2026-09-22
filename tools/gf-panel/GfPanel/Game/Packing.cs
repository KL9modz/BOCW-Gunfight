namespace GfPanel.Game;

/// <summary>
/// The packed config store. 52 int settings ride in NINE chunk dvars gf_c0..gf_c8 (6 per chunk, SORTED
/// key order) because the game's dvar pool is 4096 and heavy maps nearly fill it (memory dvar-pool-crash).
/// The GSC (gunfight_menu.gsc cfg_spec) sorts the SAME 52 keys the SAME way - an app write and an in-game
/// menu pick land in the same cells. The 15 bot knobs ride in gf_bot (0-7) + gf_bot2 (8-14): ONE
/// dvar would be ~54 bytes and the bridge slot takes 47.
/// ⚠ Order is load-bearing: adding a key to the GSC spec means adding it HERE at the same position.
/// </summary>
public static class Packing
{
    public static readonly string[] Packed =
    {
        "gf_autoswitch", "gf_bot_diff_allies", "gf_bot_diff_axis", "gf_bot_passive", "gf_camo", "gf_camo_pool",
        "gf_camo_split", "gf_caster_probe", "gf_census", "gf_customcac", "gf_dbg_assets", "gf_dbg_families",
        "gf_dbg_flags", "gf_dbg_match", "gf_dbg_spawn", "gf_dbg_structs", "gf_falldamage", "gf_feed_lines",
        "gf_fly_fast", "gf_fly_speed", "gf_gravity", "gf_jump", "gf_jump_boost", "gf_loadout",
        "gf_map_method", "gf_menu_hspan", "gf_menu_lines", "gf_menu_region", "gf_prematch", "gf_preround",
        "gf_profile", "gf_roundlimit", "gf_rounds_loadout", "gf_roundwinlimit", "gf_spawn_autospread", "gf_spawn_diag",
        "gf_spawn_family", "gf_spawn_gap", "gf_spawn_guard", "gf_spawn_pick", "gf_spec_slots", "gf_speed",
        "gf_spyplane", "gf_strike", "gf_switch_sides", "gf_switch_wait", "gf_team_size", "gf_timer_seconds",
        "gf_zone", "gf_zone_capture", "gf_zone_overtime", "gf_zone_radius",
    };
    public const int ChunkSize = 6;
    public static int ChunkCount => (Packed.Length + ChunkSize - 1) / ChunkSize;   // 9

    public static readonly string[] BotPack =
    {
        "gf_bot_hit", "gf_bot_head", "gf_bot_react", "gf_bot_fire", "gf_bot_hip", "gf_bot_far", "gf_bot_semi", "gf_bot_burst",
        "gf_bot_moveshoot", "gf_bot_fastaim", "gf_bot_sprint", "gf_bot_melee", "gf_bot_prone", "gf_bot_slide", "gf_bot_crouch",
    };

    /// <summary>The plain dvars the GFCFG extras carry, in the order the GSC writes them.</summary>
    public static readonly string[] RaceOrder =
    {
        "gf_race_laps", "gf_race_grace", "gf_race_width", "gf_race_combat", "gf_race_markers", "gf_race_end", "gf_race_corridor",
        "gf_race_posts", "gf_race_grid", "gf_race_vehicle", "gf_race_grid_gap", "gf_race_score", "gf_race_oobhud", "gf_race_reset", "gf_race_sprint",
    };
    public static readonly string[] DbgOrder = { "gf_dbg_race", "gf_dbg_veh", "gf_dbg_barrier", "gf_mapscan" };
    public static readonly string[] MiscOrder = { "gf_spawn_antistack", "gf_hint_lines", "gf_respawns", "gf_hint_others_on", "gf_hint_glyphs", "gf_forge_pin", "gf_forge_movestep", "gf_forge_rotstep", "gf_forge_scalestep", "gf_forge_zstep", "gf_hint_self_on", "gf_menu_repaint", "gf_rounds_sides", "gf_friendlyfire", "gf_latejoin", "gf_teamchange", "gf_place_dist", "gf_grab_dist", "gf_ahint" };   // append-only (the GSC misc= list)
    public static readonly string[] VehOrder = { "gf_vehmode", "gf_veh_lock", "gf_veh_hp", "gf_veh_alt" };

    private static readonly Dictionary<string, int> Index = Packed.Select((k, i) => (k, i)).ToDictionary(x => x.k, x => x.i);
    private static readonly Dictionary<string, int> BotIndex = BotPack.Select((k, i) => (k, i)).ToDictionary(x => x.k, x => x.i);

    public static int PackedIndex(string dvar) => Index.TryGetValue(dvar, out var i) ? i : -1;
    public static int BotIndexOf(string dvar) => BotIndex.TryGetValue(dvar, out var i) ? i : -1;
    public static int ChunkOf(string dvar) => PackedIndex(dvar) / ChunkSize;

    /// <summary>`set gf_cN v,v,v,v,v,v` for one chunk from a full value map.</summary>
    public static string ChunkLine(int chunk, IReadOnlyDictionary<string, int> values)
    {
        var cells = Enumerable.Range(chunk * ChunkSize, ChunkSize)
            .Where(i => i < Packed.Length)
            .Select(i => values.TryGetValue(Packed[i], out var v) ? v : Schema.ByDvar[Packed[i]].Default);
        return $"set gf_c{chunk} {string.Join(",", cells)}";
    }

    public static IEnumerable<string> BotLines(IReadOnlyDictionary<string, int> values)
    {
        int V(string k) => values.TryGetValue(k, out var v) ? v : Schema.ByDvar[k].Default;
        yield return "set gf_bot " + string.Join(",", BotPack.Take(8).Select(V));
        yield return "set gf_bot2 " + string.Join(",", BotPack.Skip(8).Select(V));
    }

    /// <summary>Split a raw chunk cell list back into keys; an empty cell resolves to the GSC default.</summary>
    public static void UnpackChunk(int chunk, string raw, IDictionary<string, int> into)
    {
        var cells = raw.Split(',');
        for (var pos = 0; pos < ChunkSize; pos++)
        {
            var i = chunk * ChunkSize + pos;
            if (i >= Packed.Length) break;
            var key = Packed[i];
            var cell = pos < cells.Length ? cells[pos] : "";
            into[key] = int.TryParse(cell, out var v) ? v : Schema.ByDvar[key].Default;
        }
    }

    public static void UnpackList(string[] keys, string raw, IDictionary<string, int> into)
    {
        var cells = raw.Split(',');
        for (var i = 0; i < keys.Length; i++)
        {
            var cell = i < cells.Length ? cells[i] : "";
            into[keys[i]] = int.TryParse(cell, out var v) ? v : (Schema.ByDvar.TryGetValue(keys[i], out var d) ? d.Default : 0);
        }
    }
}
