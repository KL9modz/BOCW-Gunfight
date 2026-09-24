using System.Text;
using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>GFPLAYERS / GFROSTER - gunfight_menu.gsc players_build / roster_build → Roster.</summary>
public static class RosterTests
{
    /// <summary>One record exactly as players_build writes it: "|" + entnum;name;team;kind;xuid;alive;score;kills;deaths;flags.</summary>
    private static string Rec(int ent, string name, string team, string kind, string xuid, bool alive, int score, int kills, int deaths, string flags) =>
        $"|{ent};{name};{team};{kind};{xuid};{(alive ? 1 : 0)};{score};{kills};{deaths};{flags}";

    /// <summary>players_build's loop, mirrored: the count is getplayers().size, a record that would take the line past
    /// 940 chars is skipped (`if ( s.size + rec.size > 940 ) continue;`).</summary>
    private static string Build(IReadOnlyList<string> recs)
    {
        var s = new StringBuilder(recs.Count.ToString());
        foreach (var r in recs)
        {
            if (s.Length + r.Length > 940) continue;
            s.Append(r);
        }
        return s.ToString();
    }

    [Test]
    public static void Parses_a_players_line()
    {
        var body = Build(new[]
        {
            Rec(0, "KL9", "allies", "host", "76561190000000001", true, 1500, 12, 3, "gmF"),
            Rec(1, "Bot Gavrilov", "axis", "bot", "", false, 100, 1, 5, ""),
            Rec(2, "semi;colon", "spec", "human", "76561190000000002", true, 0, 0, 0, "z"),
        });
        var list = Check.NotNull(Roster.ParsePlayers(body, out var unlisted), "ParsePlayers");
        Check.Equal(0, unlisted, "unlisted");
        Check.Equal(3, list.Count, "records");
        var host = list[0];
        Check.Equal((0, "KL9", "allies", "76561190000000001", true, 1500, 12, 3), (host.EntNum, host.Name, host.Team, host.Xuid, host.Alive, host.Score, host.Kills, host.Deaths), "host row");
        Check.True(host.IsHost && host.God && host.HasMenu && host.ForgeMode && !host.Fly, "host flags g m F");
        Check.True(list[1].IsBot && !list[1].Alive && list[1].Key == "n:Bot Gavrilov", "bot row + its name key");
        Check.Equal("semi;colon", list[2].Name, "a name holding ';' survives");
        Check.True(list[2].Frozen, "z = frozen");
    }

    /// <summary>A full human lobby (16 clients = 6v6 + casters at Lobby max players 12) does not fit the 940-char cap.
    /// players_build lists who fits; the panel must take that list (it used to reject the whole line, freezing the
    /// roster in exactly the biggest lobbies).</summary>
    [Test]
    public static void A_full_human_lobby_line_cut_short_by_players_build_still_parses()
    {
        var recs = Enumerable.Range(0, 16)
            .Select(i => Rec(i, $"Player_Name_{i:00}", i % 2 == 0 ? "allies" : "axis", i == 0 ? "host" : "human",
                             $"7656119{i:0000000000}", true, 12345, 25, 10, "m"))
            .ToList();
        var body = Build(recs);
        var written = body.Split('|').Length - 1;
        Check.True(written < 16, $"sanity: 16 human records should overflow players_build's 940-char cap (fitted {written})");

        var list = Check.NotNull(Roster.ParsePlayers(body, out var unlisted), "a cut-short GFPLAYERS line");
        Check.Equal(written, list.Count, "listed");
        Check.Equal(16 - written, unlisted, "unlisted");
    }

    [Test]
    public static void Unlisted_players_keep_their_last_row_instead_of_leaving()
    {
        GfPlayer P(int ent, string xuid) => new(ent, "p" + ent, "allies", "human", xuid, true, 0, 0, 0, "");
        var before = new List<GfPlayer> { P(0, "1"), P(1, "2"), P(2, "3"), P(3, "4") };
        var nowListed = new List<GfPlayer> { P(0, "1"), P(1, "2") };

        var merged = Roster.KeepUnlisted(nowListed, before, unlisted: 2);
        Check.Sequence(new[] { "x:1", "x:2", "x:3", "x:4" }, merged.Select(p => p.Key).ToList(), "two unlisted keep their rows");

        var oneLeft = Roster.KeepUnlisted(nowListed, before, unlisted: 1);
        Check.Equal(3, oneLeft.Count, "only as many as the game says are unlisted");

        Check.True(ReferenceEquals(nowListed, Roster.KeepUnlisted(nowListed, before, 0)), "nothing unlisted: the list as parsed");
    }

    [Test]
    public static void More_records_than_players_is_not_a_players_line()
    {
        var body = "1" + Rec(0, "a", "allies", "human", "1", true, 0, 0, 0, "") + Rec(1, "b", "axis", "human", "2", true, 0, 0, 0, "");
        Check.Null(Roster.ParsePlayers(body), "2 records under a count of 1");
    }

    [Test]
    public static void A_record_missing_fields_rejects_the_line()
    {
        Check.Null(Roster.ParsePlayers("1|0;name;allies;human"), "4-field record in a GFPLAYERS line");
    }

    [Test]
    public static void Parses_the_older_roster_line()
    {
        // roster_build: count + "|" + name;team;kind;xuid per player
        var list = Check.NotNull(Roster.ParseRoster("2|KL9;allies;host;76561190000000001|Bot;axis;bot;"), "ParseRoster");
        Check.Equal(2, list.Count, "rows");
        Check.True(list[0].IsHost && list[1].IsBot && list[1].Xuid == "", "kinds + a bot's empty xuid");
    }
}
