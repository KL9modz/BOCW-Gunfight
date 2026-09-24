using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>GFSTATE - gunfight_menu.gsc state_build / state_publish → GfState.Parse.</summary>
public static class StateTests
{
    // Shaped exactly like state_build's output: its key order, `say` last (a menu_say text may itself hold '|').
    private const string Full =
        "v=2|map=mp_moscow|gt=gunfight|rnd=3|sa=2|sx=1|aa=2|ax=1|na=3|nx=3|ba=1|bx=2|sp=1|tl=60000|tp=12345|ph=playing" +
        "|ot=1|pz=0|frz=0|stm=mp_miami|stg=gunfight|mc=12|ts=6|tmr=60|ack=41|drk=0|inv=1|god=1|tp3=0|prk=2|ban=1|stgd=4" +
        "|host=KL9|spn=pick e|spv=1727170000.7|mid=1727170000|mo=0|ents=812|lg=17|ev=99|say=^2app: fill | done";

    [Test]
    public static void Parses_a_full_state_line()
    {
        var s = Check.NotNull(GfState.Parse(5000, Full), "GfState.Parse");
        Check.Equal(5000L, s.Tick, "tick");
        Check.Equal("mp_moscow", s.Map, "map");
        Check.Equal("gunfight", s.Gametype, "gt");
        Check.Equal(3, s.Round, "rnd");
        Check.Equal((2, 1), (s.ScoreA, s.ScoreX), "sa / sx");
        Check.Equal((2, 1, 3, 3, 1, 2, 1), (s.AliveA, s.AliveX, s.PlayersA, s.PlayersX, s.BotsA, s.BotsX, s.Spectators), "aa ax na nx ba bx sp");
        Check.Equal((60000, 12345, 47655), (s.TimeLimitMs, s.TimePassedMs, s.TimeLeftMs), "tl / tp / time left");
        Check.Equal("playing", s.Phase, "ph");
        Check.True(s.Overtime && !s.Paused && !s.FrozenAll, "ot=1 pz=0 frz=0");
        Check.Equal(("mp_miami", "gunfight"), (s.StagedMap, s.StagedGametype), "stm / stg");
        Check.Equal((12, 6, 60), (s.MaxClients, s.TeamSize, s.TimerSeconds), "mc / ts / tmr");
        Check.Equal(41L, s.AckSeq, "ack");
        Check.True(!s.Drunk && s.InvisibleAll && s.GodAll && !s.ThirdPersonAll, "drk inv god tp3");
        Check.Equal((2, 1, 4), (s.PerksAll, s.Bans, s.Staged), "prk / ban / stgd");
        Check.Equal("KL9", s.Host, "host");
        Check.Equal(("pick e", "1727170000.7"), (s.SpawnNote, s.SpawnEvVersion), "spn / spv");
        Check.Equal((1727170000L, false, 812, 17L, 99L), (s.MatchId, s.MatchOver, s.Entities, s.LogSeq, s.EntVersion), "mid mo ents lg ev");
        Check.Equal("app: fill | done", s.Say, "say keeps its '|' and loses the colour code");
        Check.True(!s.IsFallback, "a full line is not the fallback");
    }

    [Test]
    public static void Reads_the_fallback_line_state_publish_writes_when_state_build_dies()
    {
        // state_publish: "v=2|ph=" + state_phase() + "|err=" + n + "|st=" + stage + "|host=|say="
        var s = Check.NotNull(GfState.Parse(1, "v=2|ph=playing|err=3|st=7|host=|say="), "fallback line");
        Check.True(s.IsFallback, "IsFallback");
        Check.Equal((3, 7), (s.Err, s.Stage), "err / st");
    }

    [Test]
    public static void Rejects_a_line_without_the_version_key()
    {
        Check.Null(GfState.Parse(1, "map=mp_moscow|gt=gunfight|say="), "no v= key");
    }

    [Test]
    public static void Older_payload_defaults_hold()
    {
        var s = Check.NotNull(GfState.Parse(1, "v=2|map=mp_moscow|gt=gunfight|say="), "minimal line");
        Check.Equal(1, s.Round, "rnd defaults to 1");
        Check.Equal(-1, s.Entities, "ents defaults to -1 (not published)");
        Check.Equal(-1, s.TimeLeftMs, "no time limit = -1");
        Check.Equal(0L, s.MatchId, "no mid = 0");
    }

    /// <summary>The contract, both ways: each key state_build publishes changes some GfState field, and each
    /// GfState field is fed by some published key (a typo on either side shows up here, not as a zero in game).</summary>
    [Test]
    public static void Every_published_key_lands_in_a_field_and_every_field_has_a_key()
    {
        var keys = Gsc.StateKeys();
        Check.True(keys.Contains("v") && keys.Contains("say") && keys.Count > 30, $"state_build keys look wrong: {string.Join(",", keys)}");
        string Line(string? on) => string.Join("|", keys.Where(k => k != "say").Select(k => k + "=" + (k == on ? "1" : "0"))) + "|say=" + (on == "say" ? "1" : "");

        var props = typeof(GfState).GetProperties().Where(p => p.GetIndexParameters().Length == 0).ToArray();
        var derived = new HashSet<string> { nameof(GfState.Tick), nameof(GfState.TimeLeftMs), nameof(GfState.IsFallback) };
        var baseline = Check.NotNull(GfState.Parse(1, Line(null)), "baseline line");
        var fed = new HashSet<string>();
        var problems = new Problems();
        foreach (var k in keys.Where(k => k != "v"))
        {
            var s = Check.NotNull(GfState.Parse(1, Line(k)), $"line with {k}=1");
            var changed = props.Where(p => !derived.Contains(p.Name) && !Equals(p.GetValue(s), p.GetValue(baseline))).Select(p => p.Name).ToList();
            if (changed.Count == 0) problems.Add($"'{k}=' is published by state_build / state_publish but no GfState field reads it");
            fed.UnionWith(changed);
        }
        foreach (var p in props.Where(p => !derived.Contains(p.Name) && !fed.Contains(p.Name)))
            problems.Add($"GfState.{p.Name} is fed by no key the GSC publishes - a misspelt key in GfState.Parse?");
        problems.ThrowIfAny("GFSTATE contract");
    }
}
