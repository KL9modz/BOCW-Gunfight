using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>GFCFG and the packed settings store - gunfight_menu.gsc cfg_spec / cfg_load / config_publish → Packing,
/// GfConfig. Order is load-bearing on both sides: a key out of place writes one setting into another's cell.</summary>
public static class ConfigTests
{
    [Test]
    public static void Packed_keys_are_cfg_spec_in_the_same_order()
    {
        var spec = Gsc.CfgSpec();
        Check.True(spec.Count > 40, $"cfg_spec() parse found only {spec.Count} keys");
        Check.Sequence(spec.Select(s => s.Dvar).ToList(), Packing.Packed, "Packing.Packed vs cfg_spec()");
        Check.Equal((spec.Count + Packing.ChunkSize - 1) / Packing.ChunkSize, Packing.ChunkCount, "chunk count");
        Check.Equal(9, Packing.ChunkCount, "config_publish writes gf_c0..gf_c8 (its `c <= 8` loop)");
    }

    [Test]
    public static void Packed_keys_are_sorted_as_the_packing_note_says()
    {
        Check.Sequence(Packing.Packed.OrderBy(k => k, StringComparer.Ordinal).ToList(), Packing.Packed, "sorted order");
    }

    [Test]
    public static void Packed_defaults_match_cfg_spec()
    {
        var problems = new Problems();
        foreach (var (dvar, def) in Gsc.CfgSpec())
        {
            if (!Schema.ByDvar.TryGetValue(dvar, out var row)) problems.Add($"{dvar}: packed in the GSC, no Schema row");
            else if (row.Default != def) problems.Add($"{dvar}: Schema default {row.Default}, cfg_spec {def}");
        }
        problems.ThrowIfAny("packed defaults");
    }

    [Test]
    public static void Publish_extras_carry_the_dvars_in_the_panels_order()
    {
        Check.Sequence(Gsc.PublishList("misc"), Packing.MiscOrder, "misc= (append-only on both sides)");
        Check.Sequence(Gsc.PublishList("race"), Packing.RaceOrder, "race=");
        Check.Sequence(Gsc.PublishList("dbg"), Packing.DbgOrder, "dbg=");
        Check.Sequence(Gsc.PublishList("veh"), Packing.VehOrder, "veh=");
        Check.Sequence(Gsc.PublishList("oob"), new[] { "gf_oob" }, "oob=");
        Check.Sequence(Gsc.PublishList("bar"), new[] { "gf_deathbarrier" }, "bar=");
    }

    [Test]
    public static void Bot_knobs_are_in_the_gsc_writers_order_with_its_defaults()
    {
        var order = Gsc.BotOrder("gf_bot").Concat(Gsc.BotOrder("gf_bot2")).ToList();
        Check.Sequence(order, Packing.BotPack, "gf_bot + gf_bot2 order");
        var defaults = Gsc.BotDefaults("gf_bot").Concat(Gsc.BotDefaults("gf_bot2")).ToList();
        Check.Sequence(defaults, Packing.BotPack.Select(k => Schema.ByDvar[k].Default).ToList(), "bot defaults (the GSC's fallback strings) vs Schema");
    }

    [Test]
    public static void Parses_a_config_publish_line()
    {
        // config_publish: tick | gf_c0..gf_c8 | oob= | bar= | trk= | veh= | bot= | bot2= | race= | dbg= | misc=
        var chunks = new string[9];
        for (var c = 0; c < 9; c++) chunks[c] = Packing.ChunkLine(c, new Dictionary<string, int>())["set gf_cN ".Length..];
        chunks[8] = "";   // never written: every cell falls back to the default
        var body = string.Join("|", chunks) + "|oob=0|bar=2|trk=mp_moscow;2;1,2,3,90,600|veh=3,0,200,600|bot=90,40,300,700,80,70,200,300|bot2=0,2,1,1,0,1,1" +
                   "|race=3,60,800,1,0,0,1200,1,1,9,220,1,1,3,0|dbg=1,0,0,1|misc=" + string.Join(",", Packing.MiscOrder.Select((_, i) => 1000 + i));
        var cfg = Check.NotNull(GfConfig.Parse(7, body), "GfConfig.Parse");
        Check.Equal("mp_moscow;2;1,2,3,90,600", cfg.Track, "trk=");
        Check.Equal((0, 2), (cfg.Values["gf_oob"], cfg.Values["gf_deathbarrier"]), "oob= / bar=");
        Check.Equal((3, 0, 200, 600), (cfg.Values["gf_vehmode"], cfg.Values["gf_veh_lock"], cfg.Values["gf_veh_hp"], cfg.Values["gf_veh_alt"]), "veh=");
        Check.Equal((90, 300, 0, 2), (cfg.Values["gf_bot_hit"], cfg.Values["gf_bot_burst"], cfg.Values["gf_bot_moveshoot"], cfg.Values["gf_bot_fastaim"]), "bot= / bot2=");
        Check.Equal((3, 0), (cfg.Values["gf_race_laps"], cfg.Values["gf_race_sprint"]), "race= first / last");
        Check.Equal((1, 1), (cfg.Values["gf_dbg_race"], cfg.Values["gf_mapscan"]), "dbg= first / last");
        for (var i = 0; i < Packing.MiscOrder.Length; i++)
            Check.Equal(1000 + i, cfg.Values[Packing.MiscOrder[i]], "misc= cell " + Packing.MiscOrder[i]);
        foreach (var k in Packing.Packed.Skip(8 * Packing.ChunkSize))
            Check.Equal(Schema.ByDvar[k].Default, cfg.Values[k], $"{k} from an empty gf_c8 = its default");
        foreach (var k in Packing.Packed.Take(8 * Packing.ChunkSize))
            Check.Equal(Schema.ByDvar[k].Default, cfg.Values[k], $"{k} round-trips through its chunk");
    }

    [Test]
    public static void A_packed_write_rebuilds_its_chunk_from_the_live_values()
    {
        var live = Packing.Packed.Select((k, i) => (k, i)).ToDictionary(x => x.k, x => x.i + 1);
        var key = "gf_timer_seconds";
        live[key] = 90;
        var line = Packing.ChunkLine(Packing.ChunkOf(key), live);
        var cells = line.Split(' ')[2].Split(',').Select(int.Parse).ToList();
        var first = Packing.ChunkOf(key) * Packing.ChunkSize;
        for (var pos = 0; pos < cells.Count; pos++)
        {
            var k = Packing.Packed[first + pos];
            Check.Equal(live[k], cells[pos], $"cell {pos} ({k})");
        }
        Check.True(line.StartsWith($"set gf_c{Packing.ChunkOf(key)} ", StringComparison.Ordinal), "the chunk's own dvar");
    }
}
