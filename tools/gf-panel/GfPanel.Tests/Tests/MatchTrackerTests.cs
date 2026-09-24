using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.Tests;

/// <summary>Services/MatchTracker - how the saved log says each match ended. Fed the way GameLink feeds it: each new
/// state line, a tick per sweep, the last gasp when the feed goes quiet, the game closing.</summary>
public static class MatchTrackerTests
{
    private sealed class Rig
    {
        public readonly List<(DateTime At, string Text, LogLevel Level)> Log = new();
        public readonly List<string> Detail = new();
        public readonly List<GfPlayer> Roster = new() { new GfPlayer(0, "KL9", "allies", "host", "1", true, 0, 0, 0, "") };
        public readonly MatchTracker T;
        public DateTime Now = new(2026, 9, 24, 20, 0, 0);
        private long _tick = 1_000_000;

        public Rig() => T = new MatchTracker((at, text, level) => Log.Add((at, text, level)), d => Detail.Add(d), () => Roster);

        public void State(string phase, long mid = 900, int round = 1, bool over = false)
        {
            var s = GfState.Parse(_tick, $"v=2|map=mp_moscow|gt=gunfight|rnd={round}|ph={phase}|tp=30000|mid={mid}|mo={(over ? 1 : 0)}|say=")!;
            T.OnState(s, "GFSTATE raw " + _tick, Now, Roster);
        }

        /// <summary>Let wall time (and the game clock) run, with a sweep tick at the end.</summary>
        public void Wait(TimeSpan t)
        {
            Now += t;
            _tick += (long)t.TotalMilliseconds;
            T.OnTick(Now, gameRunning: true);
        }

        /// <summary>The feed went quiet and the last-gasp sweep found nothing newer.</summary>
        public void GaspNothing()
        {
            Check.True(T.WantLastGasp, "the tracker should have asked for a last gasp");
            T.OnLastGasp(null, null, null, Now);
        }

        public bool Said(string fragment) => Log.Any(l => l.Text.Contains(fragment, StringComparison.Ordinal));

        public string All => string.Join("\n", Log.Select(l => $"[{l.Level}] {l.Text}"));
    }

    [Test]
    public static void Match_over_then_quiet_is_a_normal_end()
    {
        var r = new Rig();
        r.State("playing");
        r.Wait(TimeSpan.FromSeconds(1));
        r.State("ended", over: true);
        r.Wait(MatchTracker.OverGap + TimeSpan.FromSeconds(1));
        r.GaspNothing();
        Check.True(r.Said("match over → lobby") && !r.Said("DROPPED"), "log:\n" + r.All);
    }

    [Test]
    public static void Quiet_mid_round_is_a_dropped_match()
    {
        var r = new Rig();
        r.State("playing");
        r.Wait(MatchTracker.PlayGap + TimeSpan.FromSeconds(1));
        r.GaspNothing();
        Check.True(r.Said("MATCH DROPPED mid-round"), "log:\n" + r.All);
        Check.True(r.Detail.Any(d => d.StartsWith("last state line", StringComparison.Ordinal)) && r.Detail.Any(d => d.StartsWith("roster: KL9", StringComparison.Ordinal)),
                   "a drop writes the last state line and the roster to the file");
    }

    [Test]
    public static void A_round_end_with_no_next_round_is_a_drop()
    {
        var r = new Rig();
        r.State("ended", round: 2);
        r.Wait(TimeSpan.FromSeconds(30));
        Check.True(!r.T.WantLastGasp, "30 s on a round's end screen is still inside the round gap");
        r.Wait(MatchTracker.RoundGap);
        r.GaspNothing();
        Check.True(r.Said("the next round never started"), "log:\n" + r.All);
    }

    [Test]
    public static void Quiet_after_a_panel_restart_is_the_panels_doing()
    {
        var r = new Rig();
        r.State("playing");
        r.T.NoteLevelVerb("restart", r.Now);
        r.Wait(MatchTracker.PlayGap + TimeSpan.FromSeconds(1));
        r.GaspNothing();
        Check.True(r.Said("after the panel's 'restart'") && !r.Said("DROPPED"), "log:\n" + r.All);
    }

    [Test]
    public static void The_same_match_coming_back_was_a_stall()
    {
        var r = new Rig();
        r.State("playing");
        r.Wait(MatchTracker.PlayGap + TimeSpan.FromSeconds(1));
        r.GaspNothing();
        r.Wait(TimeSpan.FromSeconds(5));
        r.State("playing");
        Check.True(r.Said("it stalled, it did not end"), "log:\n" + r.All);
    }

    [Test]
    public static void A_last_gasp_that_finds_a_newer_line_keeps_the_match_alive()
    {
        var r = new Rig();
        r.State("playing");
        r.Wait(MatchTracker.PlayGap + TimeSpan.FromSeconds(1));
        Check.True(r.T.WantLastGasp, "asked for a last gasp");
        // the sweep had just missed it: a line stamped a moment ago
        var newer = GfState.Parse(1_000_000 + 12_500, "v=2|map=mp_moscow|gt=gunfight|rnd=1|ph=playing|mid=900|say=")!;
        r.T.OnLastGasp(newer, "GFSTATE newer", null, r.Now);
        Check.True(!r.Said("DROPPED") && !r.T.WantLastGasp, "log:\n" + r.All);
    }

    [Test]
    public static void The_game_closing_mid_match_is_reported()
    {
        var r = new Rig();
        r.State("playing");
        r.T.OnGameClosed(r.Now);
        Check.True(r.Said("the game closed while the match was playing"), "log:\n" + r.All);
    }

    [Test]
    public static void A_new_match_id_closes_the_previous_match()
    {
        var r = new Rig();
        r.State("playing", mid: 900);
        r.Wait(TimeSpan.FromSeconds(2));
        r.State("playing", mid: 901);
        Check.True(r.Said("a new match loaded while this one was still playing"), "log:\n" + r.All);
        Check.Equal(2, r.Log.Count(l => l.Text.StartsWith("▶ match", StringComparison.Ordinal)), "two match starts");
    }

    [Test]
    public static void Menu_actions_are_logged_in_order_once_answered_or_timed_out()
    {
        var r = new Rig();
        r.State("playing", mid: 900);
        MenuAction A(long seq, string result) => new(900, seq, 1_000_000, 0, "KL9", "Tools", "Item " + seq, result);
        var batch = new List<MenuAction> { A(1, "ok 1"), A(2, ""), A(3, "ok 3") };

        r.T.OnMenuActions(900, batch, r.Now, final: false);
        var menu = r.Log.Where(l => l.Level == LogLevel.Menu).Select(l => l.Text).ToList();
        Check.Sequence(new[] { "menu · KL9 › Tools › Item 1 → ok 1" }, menu, "seq 2 has no result yet and holds seq 3 behind it");

        r.Now += TimeSpan.FromSeconds(4);
        r.T.OnMenuActions(900, batch, r.Now, final: false);
        menu = r.Log.Where(l => l.Level == LogLevel.Menu).Select(l => l.Text).ToList();
        Check.Sequence(new[] { "menu · KL9 › Tools › Item 1 → ok 1", "menu · KL9 › Tools › Item 2", "menu · KL9 › Tools › Item 3 → ok 3" },
                       menu, "after 4 s the unanswered one is logged as it is, then the rest in order");
        Check.Equal(3L, r.T.LoggedSeq, "LoggedSeq");
    }

    [Test]
    public static void A_drop_right_after_an_unanswered_menu_action_names_it()
    {
        var r = new Rig();
        r.State("playing", mid: 900);
        r.T.OnMenuActions(900, new List<MenuAction> { new(900, 1, 1_000_000, 0, "KL9", "Vehicles", "Hind", "") }, r.Now, final: true);
        r.Wait(MatchTracker.PlayGap + TimeSpan.FromSeconds(1));
        r.GaspNothing();
        Check.True(r.Said("the last menu action before the stop printed no confirmation: KL9 › Vehicles › Hind"), "log:\n" + r.All);
    }
}
