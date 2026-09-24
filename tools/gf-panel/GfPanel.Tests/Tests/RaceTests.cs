using System.Text;
using System.Text.RegularExpressions;
using GfPanel.Game;
using GfPanel.Native;

namespace GfPanel.Tests;

/// <summary>The RACING page (2026-09-24): the gate geometry the map draws (it must match the game's race_gate_make /
/// race_grid_place), the GFTRACK / GFRACE parsers, the editor's bridge arguments, the library file - and the contract
/// with gunfight_menu.gsc's RACE block, read as text, so a change on either side that breaks the other fails here.</summary>
public static class RaceTests
{
    private static MemoryScanner.Hit H(string marker, long tick, string body) => new(marker, tick, body, 0);

    // ── geometry ──
    [Test]
    public static void Gate_text_round_trips_and_rejects_junk()
    {
        var g = Check.NotNull(RaceGate.Parse("-2720,1826,120,-90,600"), "gate");
        Check.Equal(new RaceGate(-2720, 1826, 120, -90, 600), g, "fields");
        Check.Equal("-2720,1826,120,-90,600", g.Text, "text");
        Check.Null(RaceGate.Parse("1,2,3,4"), "four fields");
        Check.Null(RaceGate.Parse("1,2,x,4,5"), "a field that is not a number");
    }

    /// <summary>race_gate_make: posts = centre ± right x w/2, right = anglestoright (facing +x, right is -y).</summary>
    [Test]
    public static void Posts_sit_across_the_travel_direction_like_the_game_puts_them()
    {
        var east = new RaceGate(0, 0, 0, 0, 600);
        Check.True(Near(east.PostB, (0, -300)) && Near(east.PostA, (0, 300)), $"yaw 0: posts {east.PostA} / {east.PostB}");
        var north = new RaceGate(100, 100, 0, 90, 400);
        Check.True(Near(north.PostB, (300, 100)) && Near(north.PostA, (-100, 100)), $"yaw 90: posts {north.PostA} / {north.PostB}");
    }

    [Test]
    public static void Dragging_a_post_back_onto_itself_changes_nothing()
    {
        foreach (var yaw in new[] { 0, 37, 90, 179, -45, -120 })
        {
            var g = new RaceGate(500, -800, 40, yaw, 700);
            var b = g.WithPost(true, g.PostB.X, g.PostB.Y);
            var a = g.WithPost(false, g.PostA.X, g.PostA.Y);
            Check.Equal((g.Yaw, g.W), (b.Yaw, b.W), $"post B at yaw {yaw}");
            Check.Equal((g.Yaw, g.W), (a.Yaw, a.W), $"post A at yaw {yaw}");
        }
        Check.Equal(RaceGate.MaxWidth, new RaceGate(0, 0, 0, 0, 600).WithPost(true, 0, -9000).W, "width clamp");
    }

    [Test]
    public static void Yaws_stay_in_the_games_range()
    {
        Check.Equal(180, RaceGate.NormYaw(180), "180");
        Check.Equal(-179, RaceGate.NormYaw(181), "181");
        Check.Equal(0, RaceGate.NormYaw(360), "360");
        Check.Equal(-90, new RaceGate(0, 0, 0, 90, 600).Turned(180).Yaw, "turned round");
        Check.Equal(90, RaceGate.YawTo(0, 0, 0, 50), "facing +y");
    }

    /// <summary>race_grid_place: cols = int((w - 100) / gap), slot i = centre - fwd x (200 + row x 300) + right x lateral.</summary>
    [Test]
    public static void Grid_slots_follow_the_games_formula()
    {
        var g = new RaceGate(0, 0, 0, 0, 600);                 // cols = (600 - 100) / 220 = 2
        var s = g.GridSlots(3, 220);
        Check.True(Near(s[0], (-200, 110)) && Near(s[1], (-200, -110)) && Near(s[2], (-500, 110)), "slots " + string.Join(" ", s));
        Check.Equal(1, new RaceGate(0, 0, 0, 0, 200).GridSlots(2, 220).Select(p => p.Y).Distinct().Count(), "a narrow gate is one column");
    }

    private static bool Near((double X, double Y) a, (double X, double Y) b) => Math.Abs(a.X - b.X) < 0.5 && Math.Abs(a.Y - b.Y) < 0.5;

    // ── the channels ──
    [Test]
    public static void Track_takes_the_newest_complete_publish()
    {
        var hits = new[]
        {
            H("GFTRACK", 100, "0|2|mp_moscow|3|0,0,0,0,600;100,0,0,0,600"),
            H("GFTRACK", 100, "1|2|mp_moscow|3|200,0,0,90,800"),
            H("GFTRACK", 200, "0|2|mp_moscow|4|0,0,0,0,600;100,0,0,0,600"),   // newer, but its chunk 1 is not in memory
        };
        var t = Check.NotNull(RaceTrack.FromHits(hits), "track");
        Check.Equal((100L, "mp_moscow", 3), (t.Ver, t.Map, t.Gates.Count), "the complete version");
        Check.Equal(new RaceGate(200, 0, 0, 90, 800), t.Gates[2], "gate 2");
    }

    [Test]
    public static void A_track_whose_gates_do_not_add_up_to_its_count_is_refused()
    {
        Check.Null(RaceTrack.FromHits(new[] { H("GFTRACK", 5, "0|1|mp_moscow|3|0,0,0,0,600;1,1,1,1,600") }), "2 gates, count 3");
        var empty = Check.NotNull(RaceTrack.FromHits(new[] { H("GFTRACK", 6, "0|1|mp_moscow|0|") }), "an empty track is news too");
        Check.Equal(0, empty.Gates.Count, "no gates");
    }

    [Test]
    public static void Parses_a_live_race_line()
    {
        var l = Check.NotNull(RaceLive.Parse(99, "2|3|0|12|555|41300|23|0:119/120|0,2500,700,110,hvr,1,2,0,0;3,-2400,-500,250,vrf,3,0,1,1023"), "line");
        Check.Equal((2, 3, false, 12, 555L, 41300, 23, "0:119/120"), (l.State, l.Laps, l.Sprint, l.GateCount, l.TrackVer, l.ElapsedMs, l.FinishLeft, l.StoreErr), "header");
        Check.Equal(2, l.Players.Count, "players");
        var host = l.Players[0];
        Check.True(host.IsHost && host.Riding && host.Racing && !host.Finished, "host flags " + host.Flags);
        var fin = l.Players[1];
        Check.Equal((3, 0, 1, 1023), (fin.Lap, fin.Next, fin.Place, fin.Tenths), "finisher");
        Check.Equal("1:42.3", RaceLive.Clock(fin.Tenths * 100), "clock");
        Check.Equal(0, Check.NotNull(RaceLive.Parse(1, "0|1|0|0|0|0|-1||"), "nobody").Players.Count, "no players");
        Check.Null(RaceLive.Parse(1, "0|1|0"), "short line");
    }

    // ── the bridge ──
    [Test]
    public static void Editor_arguments_fit_the_command_slot_at_their_widest()
    {
        var worst = new RaceGate(-45678, -45678, -1234, -179, RaceGate.MaxWidth);
        foreach (var (what, arg) in new[] { ("racegate", RaceArgs.Gate(worst)), ("racegset", RaceArgs.Edit(RaceTrack.MaxGates - 1, worst)), ("racegmov", RaceArgs.Move(63, 62)) })
            Check.True(arg.Length <= Commands.MaxArgChars, $"{what} '{arg}' is {arg.Length} chars > {Commands.MaxArgChars}");
    }

    // ── the library ──
    [Test]
    public static void The_old_tracks_file_carries_over()
    {
        var old = "{\"mp_moscow\":{\"loop\":[\"0,0,0,0,600\",\"100,0,0,0,600\"]},\"mp_cartel\":{\"a\":[\"1,2,3,4,500\"],\"b\":[]}}";
        var t = TrackLibrary.FromLegacy(old);
        Check.Equal(3, t.Count, "tracks");
        var loop = t.Single(x => x.Name == "loop");
        Check.Equal(("mp_moscow", 2), (loop.Map, loop.GateList.Count), "loop");
        Check.Equal(0, TrackLibrary.FromLegacy("not json").Count, "junk");
    }

    [Test]
    public static void A_shared_track_round_trips_and_a_bad_one_is_refused()
    {
        var t = new SavedTrack { Map = "mp_moscow", Name = "loop", Gates = { "0,0,0,0,600", "100,0,0,0,600" }, Sprint = true, Laps = 2 };
        var back = Check.NotNull(TrackLibrary.Import(TrackLibrary.Export(t), out _), "round trip");
        Check.Equal((t.Map, t.Name, t.Sprint, t.Laps), (back.Map, back.Name, back.Sprint, back.Laps), "fields");
        Check.Sequence(t.Gates, back.Gates, "gates");
        var tooMany = new SavedTrack { Map = "m", Name = "n", Gates = Enumerable.Repeat("0,0,0,0,600", RaceTrack.MaxGates + 1).ToList() };
        Check.Null(TrackLibrary.Import(TrackLibrary.Export(tooMany), out var why), "65 gates");
        Check.True(why.Contains("gates"), "why: " + why);
        Check.Null(TrackLibrary.Import("{\"Map\":\"m\",\"Name\":\"n\",\"Gates\":[\"1,2\"]}", out _), "a gate that is not x,y,z,yaw,w");
        Check.Null(TrackLibrary.Import("{}", out _), "no map or name");
    }

    // ── the contract with gunfight_menu.gsc ──
    private static int GscConst(string fn)
    {
        var (_, body) = GscSource.Menu.Function(fn);
        var m = Regex.Match(body, @"return\s+(\d+)\s*;");
        Check.True(m.Success, $"{fn}() does not return a number any more - update the check");
        return int.Parse(m.Groups[1].Value);
    }

    [Test]
    public static void The_gate_limit_and_the_packing_agree_with_the_game()
    {
        Check.Equal(RaceTrack.MaxGates, GscConst("race_max_gates"), "race_max_gates()");
        var pack = GscConst("race_pack");
        // the crash rules: never set dvars in bulk - the store stays within the 16 dvars the one-per-gate store used
        Check.True((RaceTrack.MaxGates + pack - 1) / pack <= 16, $"{RaceTrack.MaxGates} gates at {pack} a dvar is more than 16 dvars");
        var worst = new RaceGate(-45678, -45678, -1234, -179, RaceGate.MaxWidth).Text.Length;
        Check.True(pack * worst + pack - 1 <= 160, $"a packed dvar reaches {pack * worst + pack - 1} chars - keep it short (unmeasured ceiling)");
    }

    /// <summary>race_gate_text = x,y,z,yaw,w - the order RaceGate.Parse reads.</summary>
    [Test]
    public static void The_game_writes_gates_in_the_order_the_panel_reads()
    {
        var (_, body) = GscSource.Menu.Function("race_gate_text");
        var order = Regex.Matches(body, @"g\.c\[\s*(\d)\s*\]|g\.(yaw|w)\b").Select(m => m.Groups[1].Success ? "c" + m.Groups[1].Value : m.Groups[2].Value).ToList();
        Check.Sequence(new[] { "c0", "c1", "c2", "yaw", "w" }, order, "race_gate_text fields");
    }

    /// <summary>The field order of both lines, as race_track_build / race_live_line concatenate them.</summary>
    [Test]
    public static void The_track_and_live_lines_carry_the_fields_the_parsers_expect()
    {
        var (_, track) = GscSource.Menu.Function("race_track_build");
        var t = Regex.Match(track, @"""TRACK\|""\s*\+\s*ver\s*\+\s*""\|""\s*\+\s*i\s*\+\s*""\|""\s*\+\s*chunks\.size\s*\+\s*""\|""\s*\+\s*map\s*\+\s*""\|""\s*\+\s*gates\.size\s*\+\s*""\|""\s*\+\s*chunks\[\s*i\s*\]");
        Check.True(t.Success, "GFTRACK is no longer <ver>|<i>|<n>|<map>|<count>|<gates> - update RaceTrack.FromHits and this check");
        var cap = Regex.Match(track, @"cur\.size\s*\+\s*rec\.size\s*\+\s*1\s*>\s*(\d+)");
        Check.True(cap.Success && int.Parse(cap.Groups[1].Value) + 120 < 1024, "a GFTRACK chunk must stay well under the 1024-char fatal");

        var (_, live) = GscSource.Menu.Function("race_live_line");
        var fields = new[] { "getrealtime\\(\\)", "r\\.state", "cfg_race_laps\\(\\)", "cfg_race_sprint\\(\\)", "gates\\.size", "race_ver\\(\\)", "el", "ff", "se" };
        var pattern = @"""RACE\|""\s*\+\s*" + string.Join(@"\s*\+\s*""\|""\s*\+\s*", fields);
        Check.True(Regex.IsMatch(live, pattern), "GFRACE's header is no longer <tick>|st|laps|sprint|n|ver|el|ff|se - update RaceLive.Parse and this check");
        var lim = Regex.Match(live, @"s\.size\s*\+\s*rec\.size\s*\+\s*\d+\s*>\s*(\d+)");
        Check.True(lim.Success && int.Parse(lim.Groups[1].Value) < 1024, "the live line must be capped by length under 1024");

        var (_, rec) = GscSource.Menu.Function("race_live_rec");
        var ret = Regex.Match(rec, @"return\s+p\s+getentitynumber\(\)(.*?);", RegexOptions.Singleline);
        Check.True(ret.Success, "race_live_rec's record");
        Check.Equal(8, Regex.Matches(ret.Groups[1].Value, @"""\s*,\s*""").Count, "fields after the entnum (x,y,yaw,flags,lap,next,place,tenths)");
        foreach (var f in new[] { "h", "v", "d", "s", "r", "f", "o" })
            Check.True(rec.Contains($"fl += \"{f}\""), $"the flag '{f}' RacePlayer reads is not written any more");
    }

    [Test]
    public static void The_game_publishes_the_track_version_the_panel_watches()
    {
        var (_, state) = GscSource.Menu.Function("state_build");
        Check.True(state.Contains("\"|rtv=\" + race_ver()"), "GFSTATE rtv= (the track version) is gone");
        Check.True(GscSource.Menu.AllCode.Contains("level thread race_publish()"), "nothing starts race_publish - no GFTRACK / GFRACE");
        Check.True(Regex.IsMatch(GscSource.Menu.Function("race_publish_once").Body, @"getdvarint\(\s*#""gf_race_live"""), "the live line is no longer gated on gf_race_live (the panel's WantRace)");
    }
}
