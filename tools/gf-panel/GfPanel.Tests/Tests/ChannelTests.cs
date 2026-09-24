using System.Text;
using GfPanel.Game;
using GfPanel.Native;

namespace GfPanel.Tests;

/// <summary>The read channel below the parsers: a marked line in the game's string pool (MemoryScanner.Parse), and
/// the chunked / windowed channels built from every copy of a line still in memory (GFENTS, GFLOG, GFSPAWNED), plus
/// the lobby payload's GFLOBBY.</summary>
public static class ChannelTests
{
    private static MemoryScanner.Hit? Scan(string text) => MemoryScanner.Parse(Encoding.ASCII.GetBytes(text), "GFSTATE", 0x1000);

    [Test]
    public static void Scanner_takes_a_whole_line()
    {
        var h = Check.NotNull(Scan("GFSTATE|123456|v=2|map=mp_moscow|say=hi|END\0junk after"), "whole line");
        Check.Equal(("GFSTATE", 123456L, "v=2|map=mp_moscow|say=hi", 0x1000L), (h.Marker, h.Tick, h.Body, h.Addr), "hit");
        Check.Equal("", Check.NotNull(Scan("GFSTATE|77|END"), "tick-only line").Body, "tick-only body");
    }

    /// <summary>The measured 2026-09-20 bug: a stale, partly reused slot has no |END of its own, and scanning past its
    /// NUL to another line's |END turned kilobytes of dead memory into "say" text.</summary>
    [Test]
    public static void Scanner_refuses_a_stale_slot_whose_end_marker_is_past_its_nul()
    {
        Check.Null(Scan("GFSTATE|123|v=2|map=mp_mos\0cow|say=old junk|END"), "|END after the NUL");
        Check.Null(Scan("GFSTATE|123|v=2|map=mp_moscow"), "no |END at all");
        Check.Null(Scan("GFSTATE|123|v=2|map=mp\u0001moscow|END"), "a control byte inside the line");
        Check.Null(Scan("GFSTATE|12x|v=2|END"), "a tick that is not a number");
        Check.Null(Scan("GFSTATE|END"), "no tick");
    }

    private static MemoryScanner.Hit H(string marker, long tick, string body) => new(marker, tick, body, 0);

    [Test]
    public static void Entity_list_takes_the_newest_complete_publish()
    {
        // ents_publish: GFENTS|<stamp>|<i>|<n>|<rec;rec...>|END, rec = kind,entnum,label,owner,dist,x,y,z,flags
        var hits = new[]
        {
            H("GFENTS", 100, "0|2|p,40,crate,KL9,50,1,2,3,"),
            H("GFENTS", 100, "1|2|v,41,Hind gunship,-,400,10,20,30,om"),
            H("GFENTS", 200, "0|2|p,40,crate,KL9,50,1,2,3,"),   // newer, but its chunk 1 is not in memory yet
        };
        var (stamp, items) = Check.HasValue(EntityList.FromHits(hits), "FromHits");
        Check.Equal(100L, stamp, "an incomplete newer stamp loses to a complete older one");
        Check.Equal(2, items.Count, "entities");
        var hind = items[1];
        Check.True(hind.IsVehicle && hind.Occupied && hind.VehicleMode && hind.Owner == "-" && hind.Dist == 400, "vehicle row + flags o m");
        Check.Equal("—", hind.OwnerText, "no owner shows as a dash");

        Check.Equal(0, EntityList.FromHits(new[] { H("GFENTS", 300, "0|1|") })!.Value.Items.Count, "an empty level publishes one empty chunk");
        Check.True(EntityList.FromHits(new[] { H("GFENTS", 300, "5|2|p,1,a,b,0,0,0,0,") }) == null, "an out-of-range chunk index is ignored");
    }

    [Test]
    public static void Menu_log_unions_every_copy_and_keeps_the_filled_in_result()
    {
        // gflog_publish: GFLOG|<tick>|<mid>|<seq,ms,ent,who,page,item,result;...>|END - each copy a window of the newest records
        var hits = new[]
        {
            H("GFLOG", 10, "555|1,1000,0,KL9,Vehicles,Hind,;2,1500,0,KL9,Fun,Disco on,disco ON"),
            H("GFLOG", 11, "555|1,1000,0,KL9,Vehicles,Hind,vehicle spawned ahead;3,2000,3,Joiner,Tools,God,"),
            H("GFLOG", 12, "444|9,100,0,Old,Page,Item,done"),
        };
        var (match, actions) = Check.HasValue(MenuLog.FromHits(hits, 0), "FromHits");
        Check.Equal(555L, match, "the newest match id wins when none is asked for");
        Check.Sequence(new[] { 1L, 2L, 3L }, actions.Select(a => a.Seq).ToList(), "records by seq, across copies");
        Check.Equal("vehicle spawned ahead", actions[0].Result, "a copy with the result beats one taken before it was filled");
        Check.True(!actions[2].HasResult, "the newest record can still be open (the level died inside it)");
        Check.Equal("Joiner › Tools › God → (never finished)", actions[2].Describe(finished: false), "Describe");
        Check.Equal(1, MenuLog.FromHits(hits, 444)!.Value.Actions.Count, "an explicit match id picks that match");
        Check.Equal(0, MenuLog.ParseBody("555|1,2,3|x,1,0,a,b,c,").Count, "malformed records are skipped");
    }

    [Test]
    public static void Spawn_events_parse_for_the_map_asked()
    {
        // spawnev_build: GFSPAWNED|<stamp>|<map>|<c>|<n>|V,<match>,<ver>;E,<rp>,<order>,<ent>,<tm>,<x>,<y>,<z>,<yaw>,<how>,<slot>,<bot>,<name>|END
        var hits = new[]
        {
            H("GFSPAWNED", 50, "mp_moscow|0|1|V,9001,4;E,0,1,3,1,100,-200,32,90,a,2/4,0,KL9;E,0,2,5,2,-10,20,0,-45,e,-,1,Bot"),
            H("GFSPAWNED", 60, "mp_miami|0|1|V,9002,1;E,1,1,3,1,0,0,0,0,s,-,0,Other"),
        };
        var (match, ver, events) = Check.HasValue(SpawnEvents.FromHits(hits, "mp_moscow"), "FromHits");
        Check.Equal((9001L, 4L, 2), (match, ver, events.Count), "match / version / events");
        var e = events[0];
        Check.Equal((1, 3, 1, 100.0, -200.0, 32.0, 90, 'a', "2/4", false, "KL9"), (e.Order, e.Ent, e.Team, e.X, e.Y, e.Z, e.Yaw, e.How, e.Slot, e.Bot, e.Name), "first event");
        Check.Equal("the mod's anchors, slot 2/4", e.HowText, "HowText");
        Check.True(events[1].Bot && events[1].How == 'e', "second event");
        Check.True(SpawnEvents.FromHits(hits, "mp_nuketown6") == null, "another map's events are not this map's");
    }

    [Test]
    public static void Lobby_line_reads_what_the_lobby_payload_writes()
    {
        // gunfight_lobby.gsc: v=1|t=|mp=|as=|want=|spec=|wm=|ws=|h=|n=|gt=
        var l = Check.NotNull(GfLobby.Parse(1, "v=1|t=12|mp=12|as=1|want=12|spec=1|wm=2|ws=4|h=1|n=3|gt=gunfight"), "GfLobby.Parse");
        Check.Equal(("12", "1", 12, 1, 2, 4, true, "3", "gunfight"), (l.MaxPlayers, l.AllowSpec, l.Want, l.Spec, l.WriteMax, l.WriteSpec, l.Host, l.Clients, l.Gametype), "fields");
        Check.True(l.Ok && !l.Warn, "12 asked, 12 held, host");
        var notHost = Check.NotNull(GfLobby.Parse(1, "v=1|mp=8|as=1|want=12|spec=1|wm=5|ws=5|h=0|n=2|gt=gunfight"), "not the host");
        Check.True(!notHost.Ok && notHost.Warn, "not the host yet: nothing written, warned");
        Check.Null(GfLobby.Parse(1, "mp=12|as=1"), "no v= key");

        var keys = GscSource.StringLiterals(GscSource.Lobby.AllCode)
            .SelectMany(s => System.Text.RegularExpressions.Regex.Matches(s, @"(?:^|\|)([a-z]+)=").Select(m => m.Groups[1].Value)).ToHashSet();
        foreach (var k in new[] { "v", "t", "mp", "as", "want", "spec", "wm", "ws", "h", "n", "gt" })
            Check.True(keys.Contains(k), $"gunfight_lobby.gsc no longer writes '{k}=' - GfLobby.Parse reads it");
    }
}
