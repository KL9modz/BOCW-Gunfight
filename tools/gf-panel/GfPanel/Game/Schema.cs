namespace GfPanel.Game;

public enum SettingKind { Toggle, Choice, Int }

/// <summary>When a write takes hold (the rcon behaviour pills).</summary>
public enum Eff { Live, NextRound, Restart }

public sealed record Choice(string Label, int Value) { public override string ToString() => Label; }

/// <summary>One host setting = one gf_* dvar the mod reads (cfg_* in gunfight_menu.gsc).</summary>
public sealed class SettingDef
{
    public required string Dvar { get; init; }
    public required string Label { get; init; }
    public required SettingKind Kind { get; init; }
    public required int Default { get; init; }
    public Choice[]? Choices { get; init; }
    public int Min { get; init; }
    public int Max { get; init; }
    public int Step { get; init; } = 1;
    public string Tip { get; init; } = "";
    /// <summary>Live subsystem cmd_apply_live re-asserts for this field (move / bots / periods / timer / veh), or null = lands next round.</summary>
    public string? Scope { get; init; }
    /// <summary>The engine can only apply it by reloading the match (team size, limits): "Next round" refuses these.</summary>
    public bool RestartRequired { get; init; }
    /// <summary>A sub-group header rendered before this row.</summary>
    public string? Group { get; init; }
    /// <summary>Read live by the GSC when used (race start / next spawn) rather than at round start.</summary>
    public Eff Eff { get; init; } = Eff.NextRound;

    public string EffLabel => Eff switch { Eff.Live => "LIVE", Eff.Restart => "RESTART", _ => "NEXT" };
    public bool IsPacked => Packing.PackedIndex(Dvar) >= 0;
}

public sealed class SectionDef
{
    public required string Title { get; init; }
    public required string Tab { get; init; }        // "dashboard" | "advanced" | "tools" | "spawns" (the SPAWNS tab's side panel)
    public string Note { get; init; } = "";
    public required SettingDef[] Rows { get; init; }
}

/// <summary>The complete host-setting surface of gunfight_menu.gsc (every cfg_* reader), grouped like the
/// rcon tool's blocks. Defaults are the GSC's own (cfg_spec / cfg_* fallbacks) - the app resolves an
/// empty packed cell to them exactly as cfg_load does. Tips carry the reference detail.</summary>
public static class Schema
{
    private static Choice[] C(params (string, int)[] xs) => xs.Select(x => new Choice(x.Item1, x.Item2)).ToArray();
    private static Choice[] OnOff(string on = "On", string off = "Off") => C((off, 0), (on, 1));
    private static Choice[] Nums(params int[] xs) => xs.Select(x => new Choice(x.ToString(), x)).ToArray();

    public static readonly SectionDef[] Sections =
    {
        new()
        {
            Title = "GUNFIGHT MATCH", Tab = "dashboard",
            Note = "The match rules. Team size and the limits reload the match (RESTART); the rest lands next round.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_team_size", Label = "Team size", Kind = SettingKind.Choice, Default = 6, RestartRequired = true, Eff = Eff.Restart,
                        Choices = C(("2v2", 2), ("3v3", 3), ("4v4", 4), ("5v5", 5), ("6v6", 6)),
                        Tip = "gf_team_size (default 6v6, klaze 2026-09-24)\nPer side. Written to the in-match maxplayers setting (team size x 2 + spectator slots, capped at the session's com_maxclients). The mod reads it clamped to com_maxclients / 2, so an 8-slot Gunfight lobby plays 4v4 until the lobby itself is bigger - that is 'Lobby max players' below (the lobby payload)." },
                new() { Dvar = "gf_spec_slots", Label = "Spectator slots", Kind = SettingKind.Choice, Default = 2, RestartRequired = true, Eff = Eff.Restart,
                        Choices = C(("0", 0), ("2", 2), ("4", 4)),
                        Tip = "gf_spec_slots\nSlots ADDED to the maxplayers write on top of team size x 2, so a spectator / caster does not eat a player slot at bot fill or join time (4v4 + 1 spectator was filling 3v4)." },
                new() { Dvar = "gf_lobby_maxp", Label = "Lobby max players", Kind = SettingKind.Choice, Default = 12, Eff = Eff.Live,
                        Choices = C(("Off (stock)", 0), ("8 = 4v4", 8), ("10 = 5v5", 10), ("12 = 6v6", 12), ("14 (no lobby bots)", 14), ("16 (no lobby bots)", 16)),
                        Tip = "gf_lobby_maxp - the LOBBY's slot count (needs the lobby payload, injected by Set up all / Inject lobby payload; SETUP shows its GFLOBBY readback).\nThe pregame lobby holds maxPlayers + 4 caster slots and the match launches with that many clients (lobby UI code + engine, read 2026-09-24). Gunfight's preset is 4 -> 8 clients; 12 -> 16 = 6v6 + spectators.\n⚠ The lobby recounts its slots only on a UI settings event: in the lobby open Custom Game Rules, change any row, back out and answer YES on 'Leave Custom Game Rules'. The player count then reads N/16. Picking a mode resets it (the payload rewrites maxplayers within 2 s; redo the Rules step).\nAbove 12 the lobby greys out Add Bot and removes bots on a mode change. Untested in game." },
                new() { Dvar = "gf_lobby_spec", Label = "Lobby spectator slots", Kind = SettingKind.Toggle, Default = 1, Eff = Eff.Live,
                        Tip = "gf_lobby_spec - keeps the lobby's Allow Spectating on, which is what adds the +4 CoD Caster slots to the lobby count (the lobby shows 2 caster seats). Off = the payload leaves that rules row alone." },
                new() { Dvar = "gf_latejoin", Label = "Late joiners", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("Always place them (fewer humans > losing side > auto)", 1), ("Stock (spectator)", 0)),
                        Tip = "gf_latejoin\nklaze 2026-09-23 'always auto-place': a human who joins mid-match with no lobby side gets the side with fewer humans, then the losing side, and on a full tie fewer players overall / opposite the host - nobody is benched any more. Free-for-all joiners get the emptiest team. A safety net places anyone who never had a team and still spectates 8 s after connecting (two tries; someone who played and then chose to spectate is left alone). One bot leaves the joined side if it became the bigger one. Host feed / ACTIVITY line per join: JOIN <name> lobby=<side> ... -> <pick> (<reason>)." },
                new() { Dvar = "gf_teamchange", Label = "Pause-menu CHANGE TEAM", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("On for everyone", 1), ("Off", 0)),
                        Tip = "gf_teamchange\n1 = writes the hidden allowingameteamchange gametype setting + level.allow_teamchange so the pause menu's CHANGE TEAM works for everyone; 0 = writes it off (the stock default - the lobby UI never exposes this setting). Read at each connect / round. Late joiners no longer depend on it (they are always placed)." },
                new() { Dvar = "gf_timer_seconds", Label = "Round timer (s)", Kind = SettingKind.Choice, Default = 60, Scope = "timer", Eff = Eff.Live,
                        Choices = C(("20 s", 20), ("30 s", 30), ("40 s", 40), ("60 s", 60), ("90 s", 90), ("120 s", 120), ("180 s", 180), ("300 s", 300), ("Unlimited", 0)),
                        Tip = "gf_timer_seconds\nRound length. 0 = no timer: rounds end by elimination only. Apply now = this round (the mod caches the limit per round so a lower value never ends the running round early); Next round = from the next round." },
                new() { Dvar = "gf_roundwinlimit", Label = "First to N rounds", Kind = SettingKind.Choice, Default = -1, RestartRequired = true, Eff = Eff.Restart,
                        Choices = C(("Lobby's value", -1), ("2", 2), ("3", 3), ("4", 4), ("5", 5), ("6", 6), ("8", 8), ("10", 10), ("15", 15)),
                        Tip = "gf_roundwinlimit\nRound wins needed to win the match (the roundwinlimit gametype setting). -1 leaves the lobby's value. Changing it below the rounds already won ends the match - hence RESTART." },
                new() { Dvar = "gf_roundlimit", Label = "Round cap", Kind = SettingKind.Choice, Default = -1, RestartRequired = true, Eff = Eff.Restart,
                        Choices = C(("Lobby's value", -1), ("4", 4), ("6", 6), ("8", 8), ("10", 10), ("12", 12), ("20", 20)),
                        Tip = "gf_roundlimit\nHard cap on rounds played regardless of score. -1 leaves the lobby's value." },
                new() { Dvar = "gf_friendlyfire", Label = "Friendly fire", Kind = SettingKind.Choice, Default = -1, Scope = "ff", Eff = Eff.Live,
                        Choices = C(("Lobby's value", -1), ("Off", 0), ("On", 1), ("Reflect", 2), ("Shared", 3)),
                        Tip = "gf_friendlyfire\nThe rules menu's Friendly Fire row (the friendlyfiretype gametype setting). LIVE: the engine's serversettings loop re-reads it every 5 s, so a change lands within 5 s; re-asserted every round start. Lobby's value = don't touch. Untested in-game." },
                new() { Dvar = "gf_respawns", Label = "Respawns", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Lobby's value", 0), ("On - unlimited lives", 1), ("Off - one life (stock Gunfight)", 2)),
                        Tip = "gf_respawns\nThe rules menu's player-lives row (the playernumlives gametype setting): On = 0 lives = unlimited respawns, so no 'team dead' event fires and the round runs to the timer (overtime zone / HP tiebreak); Off = one life per round. Lands next round. A written value persists in the session, so after On use Off (not Lobby's value) to get one life back. Untested in-game." },
                new() { Dvar = "gf_rounds_loadout", Label = "Loadout rotates every", Kind = SettingKind.Choice, Default = -1,
                        Choices = C(("Lobby's value (2)", -1), ("Never", 0), ("1 round", 1), ("2 rounds", 2), ("3 rounds", 3), ("4 rounds", 4)),
                        Tip = "gf_rounds_loadout\nRounds before the shared loadout rotates (the gunfightroundsperloadout setting). In stock this ONE setting also flips the sides; with Side switch = Mod-owned the mod runs the round end itself and the sides follow 'Sides switch every' instead. Never = 0. Lands at the next round end." },
                new() { Dvar = "gf_rounds_sides", Label = "Sides switch every", Kind = SettingKind.Choice, Default = -1,
                        Choices = C(("Same as the loadout", -1), ("Never", 0), ("1 round", 1), ("2 rounds", 2), ("3 rounds", 3), ("4 rounds", 4)),
                        Tip = "gf_rounds_sides\nThe side-switch cadence on its own (klaze 2026-09-21). Only honoured while Side switch = Mod-owned (the mod owns level.onendround and runs the loadout and side checks separately - gametype::on_round_switch every N rounds). Same as the loadout = stock's coupling. Untested in-game." },
                new() { Dvar = "gf_switch_sides", Label = "Side switch", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("Mod-owned - one flip", 1), ("Stock paths", 0)),
                        Tip = "gf_switch_sides\n1 = the mod OWNS the side swap: the bundle's switchsides gate is forced on and the generic roundswitch path is silenced, so only Gunfight's own coupled path flips the sides - once per rotation.\n0 = stock: both engine paths live; two flips on one boundary cancel out ('rotates the loadouts but does not switch sides')." },
                new() { Dvar = "gf_prematch", Label = "Pre-match countdown (s)", Kind = SettingKind.Choice, Default = 15, Scope = "periods", Group = "Countdowns",
                        Choices = C(("Lobby's value", -1), ("5", 5), ("10", 10), ("15", 15), ("20", 20), ("30", 30), ("45", 45), ("60", 60)),
                        Tip = "gf_prematch\n'Match starting in' before round 1. -1 = the lobby's own row. Lands on the NEXT countdown - the current one was read before the menu existed this round." },
                new() { Dvar = "gf_preround", Label = "Pre-round countdown (s)", Kind = SettingKind.Choice, Default = 7, Scope = "periods",
                        Choices = C(("Lobby's value", -1), ("Off", 0), ("3", 3), ("5", 5), ("7", 7), ("10", 10), ("15", 15), ("20", 20)),
                        Tip = "gf_preround\n'Round begins in' before every later round. 0 = no countdown, -1 = the lobby's own row." },
            },
        },
        new()
        {
            Title = "LOADOUT & CAMO", Tab = "dashboard",
            Note = "The shared loadout, the custom-classes gate, and the camo painted on every pool weapon at every spawn.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_loadout", Label = "Loadout set", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Default", 0), ("Snipers", 1), ("Blueprints", 2), ("Melee", 3)),
                        Tip = "gf_loadout\nThe gunfightloadoutindex gametype setting: which loadout pool the rotation draws from. Next round." },
                new() { Dvar = "gf_customcac", Label = "Custom classes", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Off - Gunfight loadouts", 0), ("On - player classes", 1)),
                        Tip = "gf_customcac\n0 = real Gunfight: fixed shared loadouts, class selection off. 1 = the rules-menu 'Custom Classes' row on purpose.\nGametype settings survive a session switch, so a Gunfight reached from TDM otherwise runs the custom-classes branch by accident; the mod asserts this at every Gunfight match start." },
                new() { Dvar = "gf_profile", Label = "Gunfight profile", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("On - real blob", 1), ("Off - raw hybrid", 0)),
                        Tip = "gf_profile\nWhen a Gunfight level runs on ANOTHER mode's settings blob (only an in-match Switch NOW from TDM does that), assert the real Gunfight blob: 1 life per round, no kill limit, fixed loadouts, no streaks. 0 = watch the raw hybrid on purpose." },
                new() { Dvar = "gf_spyplane", Label = "Gunfight spy plane (Gunfight rule)", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Off", 0), ("On", 1), ("Shared - hidden value", 3)),
                        Tip = "gf_spyplane\nGunfight's own gunfightspyplane rule (gunfight.gsc:112: a team spy plane at round start) - GUNFIGHT MATCHES ONLY, applied at the next match load. It does nothing in other modes. For a spy plane in any mode, live: TOOLS → RADAR & MARKERS. 3 = the value the rules menu hides (shared minimap)." },
                new() { Dvar = "gf_camo", Label = "Pool camo", Kind = SettingKind.Choice, Default = -2, Group = "Camo",
                        Choices = C(("Random each round", -2), ("Random per player", -3), ("Stock - pool's own look", -1),
                                    ("Gold", 61), ("Diamond", 62), ("DM Ultra", 63), ("Golden Viper (ZM)", 64), ("Plague Diamond (ZM)", 65), ("Dark Aether (ZM)", 66),
                                    ("Pack-a-Punch 1", 67), ("Pack-a-Punch 2", 68), ("Pack-a-Punch 3", 69),
                                    ("PaP Mauer der Toten 1", 116), ("PaP Mauer der Toten 2", 117), ("PaP Mauer der Toten 3", 118),
                                    ("PaP Forsaken 1", 119), ("PaP Forsaken 2", 120), ("PaP Forsaken 3", 121)),
                        Tip = "gf_camo\nsetcamo on every pool weapon, every player, every spawn. -2 one roll per weapon per round shared by everyone (default), -3 a roll per player-spawn, -1 the pool's own look. A pick repaints everyone NOW as well. Any id 1-121 via the Camo by ID box in Tools." },
                new() { Dvar = "gf_camo_pool", Label = "Random camo pool", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Mastery + Pack-a-Punch", 0), ("All 1-121", 1)),
                        Tip = "gf_camo_pool\nWhat the random modes draw from." },
                new() { Dvar = "gf_camo_split", Label = "Random rolls", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("Primary and secondary separately", 1), ("One camo for both", 0)),
                        Tip = "gf_camo_split" },
            },
        },
        new()
        {
            Title = "OVERTIME ZONE", Tab = "dashboard",
            Note = "The capture-zone overtime private matches never get (synthesized on Domination's B flag / a Hardpoint trigger). ON by default.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_zone", Label = "Overtime zone", Kind = SettingKind.Choice, Default = 1,
                        Choices = C(("On - from next round", 1), ("Off - HP tiebreak", 0)),
                        Tip = "gf_zone\n1 = build the overtime capture zone (docs/notes/overtime-zone.md). 0 = the health tiebreak only." },
                new() { Dvar = "gf_zone_overtime", Label = "Overtime (s)", Kind = SettingKind.Choice, Default = 20, Choices = Nums(10, 15, 20, 30, 45, 60),
                        Tip = "gf_zone_overtime\nSeconds of overtime once the round timer runs out." },
                new() { Dvar = "gf_zone_capture", Label = "Capture (s)", Kind = SettingKind.Choice, Default = 5, Choices = Nums(3, 5, 8, 10),
                        Tip = "gf_zone_capture\nSeconds standing in the zone to capture it." },
                new() { Dvar = "gf_zone_radius", Label = "Zone radius (u)", Kind = SettingKind.Int, Default = 128, Min = 32, Max = 512, Step = 16,
                        Tip = "gf_zone_radius\nTrigger radius when no map trigger can be reused. Stock ~128." },
            },
        },
        new()
        {
            Title = "BOTS", Tab = "dashboard",
            Note = "Difficulty is the stock bot_difficulty_<team> gametype setting; CUSTOM swaps in the mod's own struct built from the tuning below.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_bot_diff_allies", Label = "Difficulty: allies", Kind = SettingKind.Choice, Default = -1, Scope = "bots", Eff = Eff.Live,
                        Choices = C(("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2), ("Veteran", 3), ("CUSTOM", 4)),
                        Tip = "gf_bot_diff_allies\nbot_difficulty_allies, re-read by bot_difficulty::assign() when a bot joins the team; the mod re-assigns live bots on a change. -1 leaves the lobby's row alone." },
                new() { Dvar = "gf_bot_diff_axis", Label = "Difficulty: axis", Kind = SettingKind.Choice, Default = -1, Scope = "bots", Eff = Eff.Live,
                        Choices = C(("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2), ("Veteran", 3), ("CUSTOM", 4)),
                        Tip = "gf_bot_diff_axis\nSame for axis. Both CUSTOM = the tuning below on both sides." },
                new() { Dvar = "gf_bot_passive", Label = "Passive - bots ignore everyone", Kind = SettingKind.Toggle, Default = 0, Scope = "bots", Eff = Eff.Live,
                        Tip = "gf_bot_passive\n1 = every bot ignores everyone (stock .ignoreall, the dev-gui 'Ignore All' flag). Target dummies." },
            },
        },
        new()
        {
            Title = "CUSTOM BOT TUNING", Tab = "dashboard",
            Note = "Used when a side's difficulty is CUSTOM. Packed into gf_bot / gf_bot2. Hover a label for the stock recruit / regular / hardened / veteran values.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_bot_hit", Label = "Hit chance %", Kind = SettingKind.Int, Default = 100, Min = 0, Max = 100, Step = 5, Scope = "bots", Eff = Eff.Live, Tip = "Chance (%) a shot cycle is aimed on-target. Stock 40 / 50 / 60 / 90." },
                new() { Dvar = "gf_bot_head", Label = "Headshot %", Kind = SettingKind.Int, Default = 50, Min = 0, Max = 100, Step = 5, Scope = "bots", Eff = Eff.Live, Tip = "Chance (%) an on-target cycle aims at the head. Stock 0 / 3 / 10 / 20." },
                new() { Dvar = "gf_bot_react", Label = "Aim delay (ms)", Kind = SettingKind.Int, Default = 100, Min = 0, Max = 3000, Step = 50, Scope = "bots", Eff = Eff.Live, Tip = "ms of aim before each fire window. Stock 1400 / 1100 / 700 / 300." },
                new() { Dvar = "gf_bot_fire", Label = "Fire window (ms)", Kind = SettingKind.Int, Default = 1000, Min = 100, Max = 3000, Step = 100, Scope = "bots", Eff = Eff.Live, Tip = "ms the fire window lasts. Stock 300 / 400 / 500 / 700." },
                new() { Dvar = "gf_bot_hip", Label = "Hipfire %", Kind = SettingKind.Int, Default = 100, Min = 0, Max = 100, Step = 5, Scope = "bots", Eff = Eff.Live, Tip = "Hit-chance scale (%) when not ADS. Stock 50 / 50 / 60 / 70." },
                new() { Dvar = "gf_bot_far", Label = "Long-range %", Kind = SettingKind.Int, Default = 90, Min = 0, Max = 100, Step = 5, Scope = "bots", Eff = Eff.Live, Tip = "Hit-chance scale (%) at max range. Stock 100 / 80 / 66 / 50." },
                new() { Dvar = "gf_bot_semi", Label = "Semi tap (ms)", Kind = SettingKind.Int, Default = 100, Min = 0, Max = 2000, Step = 50, Scope = "bots", Eff = Eff.Live, Tip = "ms between semi-auto taps. Stock 800 / 600 / 400 / 150." },
                new() { Dvar = "gf_bot_burst", Label = "Burst delay (ms)", Kind = SettingKind.Int, Default = 100, Min = 0, Max = 2000, Step = 50, Scope = "bots", Eff = Eff.Live, Tip = "ms between bursts. Stock 1200 / 900 / 700 / 250." },
                new() { Dvar = "gf_bot_moveshoot", Label = "Move + shoot", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "1 keeps moving with a target in sight; 0 stops to shoot (stock recruit / regular)." },
                new() { Dvar = "gf_bot_fastaim", Label = "Look speed", Kind = SettingKind.Choice, Default = 1, Scope = "bots", Eff = Eff.Live, Choices = C(("Slow - recruit", 0), ("Fast - veteran", 1), ("Max", 2)), Tip = "Look / turn speed." },
                new() { Dvar = "gf_bot_sprint", Label = "Sprint", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "The bundle's allowSprint flag." },
                new() { Dvar = "gf_bot_melee", Label = "Melee", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "allowMelee." },
                new() { Dvar = "gf_bot_prone", Label = "Prone", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "allowProne." },
                new() { Dvar = "gf_bot_slide", Label = "Slide", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "allowSlide." },
                new() { Dvar = "gf_bot_crouch", Label = "Crouch", Kind = SettingKind.Toggle, Default = 1, Scope = "bots", Eff = Eff.Live, Tip = "allowCrouch (stock veteran is the only preset with all five on)." },
            },
        },
        new()
        {
            Title = "MOVEMENT", Tab = "dashboard",
            Note = "Everyone. Applies live (mod_movement) and again every round / spawn.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_gravity", Label = "Gravity", Kind = SettingKind.Choice, Default = 800, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Normal 800", 800), ("600", 600), ("Low 400", 400), ("Moon 200", 200), ("Floaty 100", 100), ("Space 40", 40), ("Heavy 1200", 1200), ("Heavy 1600", 1600)),
                        Tip = "gf_gravity\nbg_gravity. Stock 800; lower = floatier. Verified engine-consumed in MP." },
                new() { Dvar = "gf_jump_boost", Label = "Jump boost", Kind = SettingKind.Choice, Default = 0, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Off - stock jump", 0), ("Low ~100u apex", 150), ("Mid ~260u", 400), ("High ~700u", 800), ("Extreme ~1500u", 1300), ("Insane ~3000u", 1900)),
                        Tip = "gf_jump_boost\nExtra upward velocity (u/s) added at every takeoff (setvelocity, stock's own shape). Apex figures assume stock gravity." },
                new() { Dvar = "gf_jump", Label = "Builtin jump height", Kind = SettingKind.Choice, Default = -1, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Leave stock", -1), ("39 (stock)", 39), ("70", 70), ("120", 120), ("200", 200), ("500", 500), ("1000", 1000)),
                        Tip = "gf_jump\nsetjumpheight builtin. -1 = skip (cannot UNDO a prior high jump - set an explicit height). Stock CoD jump height is ~39." },
                new() { Dvar = "gf_speed", Label = "Move speed %", Kind = SettingKind.Choice, Default = 100, Scope = "move", Eff = Eff.Live,
                        Choices = C(("50%", 50), ("75%", 75), ("100% - stock", 100), ("125%", 125), ("150%", 150), ("200%", 200), ("300%", 300)),
                        Tip = "gf_speed\nsetmovespeedscale, the per-player scaler stock uses (Prop Hunt props, the Scream slasher, loadout modifiers) - re-applied after every loadout." },
                new() { Dvar = "gf_falldamage", Label = "Fall damage", Kind = SettingKind.Choice, Default = 0, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Off", 0), ("Stock", 1)),
                        Tip = "gf_falldamage\n0 = off, three layers: specialty_fallheight on every spawn (engine-native, joiner-safe), an onplayerdamage gate for MOD_FALLING, and the bg_falldamage* dvars pushed out of reach. MEASURED working." },
                new() { Dvar = "gf_oob", Label = "Out of bounds", Kind = SettingKind.Choice, Default = 1, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Off - no warning, no death", 1), ("Stock", 0)),
                        Tip = "gf_oob\n1 = nobody gets the restricted-area warning, countdown or death (stock's own per-player disable_oob switch, re-set every spawn)." },
                new() { Dvar = "gf_deathbarrier", Label = "Death barriers", Kind = SettingKind.Choice, Default = 1, Scope = "move", Eff = Eff.Live,
                        Choices = C(("Off - hurt volumes disabled", 1), ("Stock", 0), ("Off - hurt volumes deleted (this round)", 2), ("Off - hurt volumes sunk", 3)),
                        Tip = "gf_deathbarrier\nThe map's trigger_hurt kill volumes (the instant death off a ledge / in water / under the map) - NOT the restricted area, and god mode does not survive them. Disabled = triggerenable(0) (reversible) - measured working 2026-09-21, the default. Deleted = gone until the next round. Sunk = moved 40000u down; both fallbacks. The BARRIER debug line shows the census and the last death's cause." },
                new() { Dvar = "gf_parachute", Label = "Parachutes", Kind = SettingKind.Choice, Default = 0, Eff = Eff.Live, Group = "Air",
                        Choices = C(("Off - stock", 0), ("Everyone", 1), ("Host only", 2)),
                        Tip = "gf_parachute\nThe Fireteam free-fall + parachute on every map (klaze 2026-09-23): fall from height - a jump boost, a heli, flying - and deploy it. A Fireteam mode's hidden setting makes the spawn call two player builtins (globallogic_spawn.gsc:674); the mod calls that pair itself per player per spawn, so no match reload. Lands on everyone alive within a second. The height a free-fall starts at is the engine's - unmeasured." },
                new() { Dvar = "gf_fly_speed", Label = "Fly speed", Kind = SettingKind.Choice, Default = 20, Scope = "move", Eff = Eff.Live, Group = "Fly mode",
                        Choices = C(("10", 10), ("20", 20), ("40", 40), ("80", 80)),
                        Tip = "gf_fly_speed\nFly mode: units per server frame (Tools -> Fly). The Atian default is 20." },
                new() { Dvar = "gf_fly_fast", Label = "Fly sprint speed", Kind = SettingKind.Choice, Default = 60, Scope = "move", Eff = Eff.Live,
                        Choices = C(("30", 30), ("60", 60), ("120", 120), ("240", 240)),
                        Tip = "gf_fly_fast\nFly mode speed while sprint is held." },
            },
        },
        new()
        {
            Title = "SPAWN SETTINGS", Tab = "spawns",
            Note = "Every map · Gunfight only · a map's PICK wins",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_spawn_guard", Label = "Spawn guard", Kind = SettingKind.Choice, Default = 2,
                        Choices = C(("Auto - only bad maps", 2), ("Force - every map", 1), ("Off", 0)),
                        Tip = "gf_spawn_guard\nAuto = engine start spawns where the map has good ones, the guard's anchors where it has none (Crossroads under Gunfight). Force = anchors always. Off = stock." },
                new() { Dvar = "gf_spawn_family", Label = "Spawn family", Kind = SettingKind.Choice, Default = 8,
                        Choices = C(("AUTO - authored S&D starts, else TDM", 8), ("TDM markers (measured good)", 1), ("None - engine / geometric", 0), ("S&D markers", 2), ("Domination markers", 3), ("CTF markers", 4), ("Hardpoint markers", 5), ("Control markers", 6), ("FFA markers", 7)),
                        Tip = "gf_spawn_family\nWhich markers the guard builds the two sides from. Every spawn goes on them." },
                new() { Dvar = "gf_spawn_pick", Label = "Side pick", Kind = SettingKind.Choice, Default = 0,
                        Choices = C(("Near - gap based (closer up)", 0), ("Far ends - like TDM openings", 1)),
                        Tip = "gf_spawn_pick\nNear = two groups around the map centre at the gap (TDM's respawn zone). Far ends = the two outermost marker groups (TDM's opening spawns)." },
                new() { Dvar = "gf_spawn_gap", Label = "Guard gap (u)", Kind = SettingKind.Choice, Default = 1800, Choices = Nums(1200, 1800, 2400, 3200),
                        Tip = "gf_spawn_gap\nTarget distance between the two sides' centres." },
                new() { Dvar = "gf_spawn_autospread", Label = "AUTO trip distance (u)", Kind = SettingKind.Int, Default = 2500, Min = 0, Max = 8000, Step = 100,
                        Tip = "gf_spawn_autospread\nAUTO guards when the nearest start spawn is farther than the objective-cluster radius + this." },
                new() { Dvar = "gf_spawn_antistack", Label = "Anti-stack net", Kind = SettingKind.Choice, Default = 1, Choices = C(("On", 1), ("Off", 0)),
                        Tip = "gf_spawn_antistack\nOn every spawn, a player landing within 48u of another this round is relocated (setorigin + physics trace). Off = spawns exactly where the engine / guard put them (turn off to isolate a spawn-time crash)." },
                new() { Dvar = "gf_strike", Label = "Crossroads: Strike layout", Kind = SettingKind.Choice, Default = 0, Choices = C(("Off - full 12v12 map", 0), ("On", 1)),
                        Tip = "gf_strike\nCrossroads loads the full 12v12 map under Gunfight. On keeps the Strike clips server-side, but every client still draws the 12v12 minimap and bounds. No-op on other maps." },
                new() { Dvar = "gf_spawn_diag", Label = "Spawn diagnostics", Kind = SettingKind.Toggle, Default = 1,
                        Tip = "gf_spawn_diag\nRecord placements for the SPAWN debug line." },
            },
        },
        new()
        {
            Title = "PLACEMENT & PROMPTS", Tab = "advanced",
            Note = "Crosshair placement of props / vehicles and the map-prop grab (bocw-1c 2026-09-22). Plain dvars, read live.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_place_dist", Label = "Place reach (u)", Kind = SettingKind.Int, Default = 500, Min = 100, Max = 1500, Step = 50, Eff = Eff.Live,
                        Tip = "gf_place_dist\nHow far along the crosshair a prop / vehicle is placed (the forge preview and the vehicle spawn)." },
                new() { Dvar = "gf_grab_dist", Label = "Grab reach (u)", Kind = SettingKind.Int, Default = 200, Min = 60, Max = 400, Step = 20, Eff = Eff.Live,
                        Tip = "gf_grab_dist\nHow close a map prop must be to grab it. Default 200 (the GSC's, raised from 160 on 2026-09-22)." },
                new() { Dvar = "gf_ahint", Label = "Asset prompts", Kind = SettingKind.Toggle, Default = 1, Eff = Eff.Live,
                        Tip = "gf_ahint\nThe on-screen prompts on grabbable / usable assets: the forge-mode prop prompts (now with the viewer's own interact-button icon) and the 'Hold [use] to control / fly / enter' line on menu-spawned rides that have no enter prompt of their own (RC-XD, streak rides - bocw-84 2026-09-23). 0 = off." },
            },
        },
        new()
        {
            Title = "VEHICLE MODE", Tab = "advanced",
            Note = "Everyone spawns already riding this map's ride of the class. A class this map lacks = everyone on foot (the host feed says so).",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_vehmode", Label = "Everyone spawns riding", Kind = SettingKind.Choice, Default = 0, Scope = "veh", Eff = Eff.Live,
                        Choices = C(("Off", 0), ("Motorcycles", 1), ("Attack helicopters (Hind)", 2), ("Helicopters any map (care package heli)", 3), ("Snowmobiles", 4), ("Quads + buggies", 5), ("Tanks + APCs", 6), ("Cars + trucks", 7), ("Streak gunship heli (seat untested)", 8), ("AUTO - lightest ride, else care heli", 9)),
                        Tip = "gf_vehmode\nMotorcycles: Diesel / Cartel / Collateral / Fireteam maps. Hind: Collateral + Fireteam. Care package heli: every map (flies, unarmed). Snowmobiles: Crossroads / Alpine. Quads: Collateral / Fireteam. Tanks: Crossroads (APC on Diesel / Checkmate). Cars: Cartel / Fireteam. Apply now = everyone alive dismounts and remounts." },
                new() { Dvar = "gf_veh_lock", Label = "Locked in (cannot get off)", Kind = SettingKind.Toggle, Default = 1, Scope = "veh", Eff = Eff.Live,
                        Tip = "gf_veh_lock\nRiders cannot leave the seat (stock's disable_usability layer + a re-seat watcher)." },
                new() { Dvar = "gf_veh_hp", Label = "Vehicle HP %", Kind = SettingKind.Choice, Default = 100, Scope = "veh", Eff = Eff.Live, Choices = C(("25%", 25), ("50%", 50), ("100% - stock", 100), ("200%", 200), ("400%", 400)),
                        Tip = "gf_veh_hp\nPercent of the asset's default health. 25 makes a Hind killable by rifles; 400 makes bikes tanky. Next ride." },
                new() { Dvar = "gf_veh_alt", Label = "Heli spawn height (u)", Kind = SettingKind.Choice, Default = 300, Choices = Nums(150, 300, 600, 1000),
                        Tip = "gf_veh_alt\nAir rides spawn this high above the spawn point (ceiling-traced). Next ride." },
            },
        },
        new()
        {
            Title = "RACE SETTINGS", Tab = "advanced",
            Note = "Read when a race STARTS (Tools -> Race). Gates are placed where the host is, across his direction of travel.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_race_laps", Label = "Laps", Kind = SettingKind.Choice, Default = 1, Choices = Nums(1, 2, 3, 5), Eff = Eff.Live, Tip = "gf_race_laps\nLaps through the start/finish gate (gate 0)." },
                new() { Dvar = "gf_race_sprint", Label = "Course", Kind = SettingKind.Choice, Default = 0, Eff = Eff.Live, Choices = C(("Circuit - laps, start gate is the finish", 0), ("A to B - the LAST gate is the finish", 1)), Tip = "gf_race_sprint" },
                new() { Dvar = "gf_race_end", Label = "After the race", Kind = SettingKind.Choice, Default = 1, Eff = Eff.Live, Choices = C(("End the match - stock podium", 1), ("Keep playing - races add up", 0)), Tip = "gf_race_end\nEnd = the race ends the match and the stock FFA end screen shows the placement. Keep = points add up across races; 'End match' shows the podium with the totals." },
                new() { Dvar = "gf_race_grace", Label = "Finish timer (s after the first finish)", Kind = SettingKind.Choice, Default = 45, Eff = Eff.Live, Choices = Nums(30, 45, 60, 90), Tip = "gf_race_grace\nStarts when the FIRST racer finishes (shown on the stock match clock); the match ends when everyone has finished or it runs out." },
                new() { Dvar = "gf_race_width", Label = "Gate width (u)", Kind = SettingKind.Choice, Default = 600, Eff = Eff.Live, Choices = Nums(400, 600, 800, 1200), Tip = "gf_race_width\nWidth of the gates placed from now on. Existing gates keep theirs." },
                new() { Dvar = "gf_race_corridor", Label = "Track boundary width (u)", Kind = SettingKind.Choice, Default = 1600, Eff = Eff.Live, Choices = C(("Off", 0), ("800 tight", 800), ("1200", 1200), ("1600", 1600), ("2400 loose", 2400)), Tip = "gf_race_corridor\nA corridor this wide around the gate-to-gate line. Outside it: OFF TRACK, then the reset." },
                new() { Dvar = "gf_race_reset", Label = "Off track: reset after (s)", Kind = SettingKind.Choice, Default = 3, Eff = Eff.Live, Choices = C(("Warn only", 0), ("3 (= the overlay's countdown)", 3), ("5", 5), ("8", 8)), Tip = "gf_race_reset\nSeconds continuously off track before the racer is put back at the last gate passed." },
                new() { Dvar = "gf_race_oobhud", Label = "Off track look", Kind = SettingKind.Choice, Default = 1, Eff = Eff.Live, Choices = C(("Stock combat-area overlay", 1), ("Bold OFF TRACK prints", 0)), Tip = "gf_race_oobhud" },
                new() { Dvar = "gf_race_combat", Label = "Combat during the race", Kind = SettingKind.Toggle, Default = 0, Eff = Eff.Live, Tip = "gf_race_combat\nOff = nobody can damage anyone while the race runs." },
                new() { Dvar = "gf_race_grid", Label = "Start grid", Kind = SettingKind.Toggle, Default = 1, Eff = Eff.Live, Tip = "gf_race_grid\nAt START everyone lines up in rows behind the start gate, held until GO." },
                new() { Dvar = "gf_race_vehicle", Label = "Grid vehicle", Kind = SettingKind.Choice, Default = 9, Eff = Eff.Live, Choices = C(("AUTO - this map's lightest ride", 9), ("None - on foot / keep your ride", 0), ("Motorcycles", 1), ("Snowmobiles", 4), ("Quads + buggies", 5), ("Cars + trucks", 7), ("Tanks + APCs", 6), ("Care package heli", 3), ("Attack heli (Hind)", 2)), Tip = "gf_race_vehicle\nSpawned at each grid slot for racers on foot (bots stay on foot)." },
                new() { Dvar = "gf_race_grid_gap", Label = "Grid spacing (u)", Kind = SettingKind.Choice, Default = 220, Eff = Eff.Live, Choices = C(("160 tight", 160), ("220", 220), ("320 wide - tanks", 320)), Tip = "gf_race_grid_gap" },
                new() { Dvar = "gf_race_score", Label = "End-screen score", Kind = SettingKind.Choice, Default = 1, Eff = Eff.Live, Choices = C(("Track time in seconds", 1), ("Placement points", 0)), Tip = "gf_race_score" },
                new() { Dvar = "gf_race_posts", Label = "Gate posts (palm trees)", Kind = SettingKind.Toggle, Default = 1, Eff = Eff.Live, Tip = "gf_race_posts\nA palm tree (else the first resident fallback) at both ends of every gate with the markers." },
                new() { Dvar = "gf_race_markers", Label = "Markers at race start", Kind = SettingKind.Toggle, Default = 1, Eff = Eff.Live, Tip = "gf_race_markers\nAn objective icon on every gate when the race starts (the icon renders - measured)." },
            },
        },
        new()
        {
            Title = "SESSION / MAP", Tab = "advanced",
            Note = "How a map switch travels.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_map_method", Label = "Map switch method", Kind = SettingKind.Choice, Default = 1, Choices = C(("Session - lobby follows", 1), ("Carry - load-time", 0)),
                        Tip = "gf_map_method\nSession = switchmap_load, the lobby FOLLOWS (verified 2026-09-12). Carry = the Atian load-time override; the lobby stays stale." },
                new() { Dvar = "gf_autoswitch", Label = "Auto-Gunfight on inject", Kind = SettingKind.Toggle, Default = 0,
                        Tip = "gf_autoswitch\nOn = auto-switch back to Gunfight when a non-Gunfight gametype is injected / restarted." },
                new() { Dvar = "gf_switch_wait", Label = "Switch wait (s)", Kind = SettingKind.Choice, Default = 0, Choices = C(("None - cp form", 0), ("5", 5), ("25 - proven", 25)),
                        Tip = "gf_switch_wait\nHow long Switch NOW waits for switchmap_preload_finished before committing. 25 = stock ZM's cap and the measured-working form; 0 = stock campaign's immediate form." },
            },
        },
        new()
        {
            Title = "IN-GAME MENU DISPLAY", Tab = "advanced",
            Note = "The host's in-game panel (the compact menu stays available with the app up).",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_menu_region", Label = "Panel layout", Kind = SettingKind.Choice, Default = 2,
                        Choices = C(("Menu centre + info feed + hint", 2), ("Lower-left feed", 0), ("Centre", 1), ("Menu feed + status centre", 3), ("HINT panel (one line, not advised)", 4)),
                        Tip = "gf_menu_region\nWhere the in-game menu draws. 2 = the one-line centre carousel with the status block in the feed and an info line in the hint row (default)." },
                new() { Dvar = "gf_menu_lines", Label = "Menu rows", Kind = SettingKind.Int, Default = 3, Min = 1, Max = 12, Tip = "gf_menu_lines\nVisible item rows in the panel window (clamped 1-24 in the GSC)." },
                new() { Dvar = "gf_menu_hspan", Label = "Centre carousel width", Kind = SettingKind.Int, Default = 4, Min = 1, Max = 9, Tip = "gf_menu_hspan\nHow many menu items the centre carousel shows side by side." },
                new() { Dvar = "gf_feed_lines", Label = "Feed lines", Kind = SettingKind.Int, Default = 14, Min = 1, Max = 24, Tip = "gf_feed_lines\ncom_gameMsgWindow1LineCount the menu primes (latched at HUD build; ~4-5 visible)." },
                new() { Dvar = "gf_hint_lines", Label = "Hint rows (region 4)", Kind = SettingKind.Int, Default = 8, Min = 1, Max = 15, Tip = "gf_hint_lines\nRegion-4 rows per page (the HINT panel is one non-wrapping line on retail - kept for completeness)." },
                new() { Dvar = "gf_menu_repaint", Label = "Menu repaint (ms)", Kind = SettingKind.Int, Default = 3000, Min = 500, Max = 15000, Step = 250, Eff = Eff.Live,
                        Tip = "gf_menu_repaint\nHow often the open menu re-prints its feed lines and centre line while nothing changed. Every repaint re-scrolls the feed and re-fades the centre text (the flicker), so set it as high as the engine's hold time allows: run Tools -> Fade probe, time the two lines until they vanish, and set this just under the shorter one. Was a fixed 2000." },
                new() { Dvar = "gf_hint_others_on", Label = "Others-facing hint line", Kind = SettingKind.Toggle, Default = 1,
                        Tip = "gf_hint_others_on\nThe welcome / discord line other players see when they approach the host (a per-player hint trigger, host excluded); shown always (no automatic build warning - the line is yours to set). Created per host spawn - a change lands at the next spawn. Text: TOOLS -> FORGE & HINT BAR." },
                new() { Dvar = "gf_hint_self_on", Label = "Host's own hint bar", Kind = SettingKind.Toggle, Default = 1,
                        Tip = "gf_hint_self_on\nThe host's always-on hint bar: the menu controls while the menu is open, the forge controls while building, 'hold ADS + Melee to open' when idle. 0 = off." },
                new() { Dvar = "gf_hint_glyphs", Label = "Bind glyphs in hints", Kind = SettingKind.Toggle, Default = 1,
                        Tip = "gf_hint_glyphs\n1 (default) = hints carry [{+bind}] tokens the client renders as the right icon per device (R3, D-pad, RT, LT, Y / their keyboard binds). UNMEASURED on retail: if the bar shows literal '[{+melee}]' text, set 0 for the plain-text fallback." },
                new() { Dvar = "gf_caster_probe", Label = "Caster input probe", Kind = SettingKind.Toggle, Default = 1, Tip = "gf_caster_probe\nWhile the host is a CoD Caster, print a probe line listing every button pressed." },
            },
        },
        new()
        {
            Title = "DEBUG FEED", Tab = "advanced",
            Note = "Each tool prints ONE complete feed line every 3 s while on (klaze's convention). Persist across matches.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_census", Label = "Settings census", Kind = SettingKind.Choice, Default = 0, Choices = C(("Off", 0), ("As launched", 1), ("Live", 2)), Tip = "gf_census\nThe settings blob: 1 = the snapshot mod_apply takes before its own writes, 2 = the live values. Legend in docs/notes/mode-remnants.md." },
                new() { Dvar = "gf_dbg_match", Label = "Match info", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_match\nThe Show-match-info readout as one line." },
                new() { Dvar = "gf_dbg_spawn", Label = "Spawn placements", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_spawn\nThis round's engine / guard placements for every player (name:team:how:distance:PILE) + the guard state." },
                new() { Dvar = "gf_dbg_structs", Label = "Spawn structs + engine lists", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_structs" },
                new() { Dvar = "gf_dbg_families", Label = "Spawn families + guard", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_families\nSpawn-struct family counts, legacy detector numbers, what the guard built, strike state." },
                new() { Dvar = "gf_dbg_flags", Label = "Marker flags census", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_flags" },
                new() { Dvar = "gf_dbg_assets", Label = "Asset census (vehicles / props / destructibles)", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_dbg_assets\nVEHICLES / PROPS / DESTRUCT lines." },
                new() { Dvar = "gf_dbg_barrier", Label = "Death barriers (BARRIER)", Kind = SettingKind.Toggle, Default = 0, Scope = "move", Eff = Eff.Live, Tip = "gf_dbg_barrier\nThe trigger_hurt census, the host's state and the last death of any player." },
                new() { Dvar = "gf_dbg_veh", Label = "Vehicle mode (VEHMODE)", Kind = SettingKind.Toggle, Default = 0, Eff = Eff.Live, Tip = "gf_dbg_veh" },
                new() { Dvar = "gf_dbg_race", Label = "Race (RACE)", Kind = SettingKind.Toggle, Default = 0, Eff = Eff.Live, Tip = "gf_dbg_race\nRace state, gate count, settings, racers / finishers, the host's lap / gate / lateral numbers." },
                new() { Dvar = "gf_mapscan", Label = "Map census harvest (GFMAP*)", Kind = SettingKind.Toggle, Default = 0, Tip = "gf_mapscan\nPublish the per-map vehicle / prop / spawn / destructible census for the app's map database. OFF by default: its entity scan tripped the 0x91f84370 fatal on big maps before it was yield-guarded; opt in to document a map." },
            },
        },
        new()
        {
            Title = "FORGE CONTROLS", Tab = "tools",
            Note = "Place-mode feel (forge session, 2026-09-20). Read live every tick of the forge loop - a change applies while you build. Default = free-walk: you move normally (WASD / stick) and the prop rides your crosshair onto surfaces; D-pad / Action Slots 1-4 = distance up/down + rotate left/right, ADS + up/down = scale, weapon switch = cycle model, fire = place, frag = exit - the same on controller and keyboard.",
            Rows = new SettingDef[]
            {
                new() { Dvar = "gf_forge_pin", Label = "Pin the player while placing", Kind = SettingKind.Toggle, Default = 0, Eff = Eff.Live,
                        Tip = "gf_forge_pin\n0 (default - klaze: 'i need to be able to move while placing props') = free-walk: WASD / stick moves YOU, the prop rides the crosshair, adjustments on the D-pad / Action Slots. 1 = pinned in place with WASD driving the prop instead (the earlier scheme)." },
                new() { Dvar = "gf_forge_movestep", Label = "Distance step", Kind = SettingKind.Int, Default = 6, Min = 1, Max = 30, Step = 1, Eff = Eff.Live, Tip = "gf_forge_movestep\nFree-walk: units per D-pad / Action Slot press (x8 internally, x20 with sprint held). Pinned mode: units per tick of W/S." },
                new() { Dvar = "gf_forge_rotstep", Label = "Turn step", Kind = SettingKind.Int, Default = 3, Min = 1, Max = 30, Step = 1, Eff = Eff.Live, Tip = "gf_forge_rotstep\nFree-walk: degrees per D-pad / Action Slot press (x5; sprint held = a 45-degree snap). Pinned mode: degrees per tick of A/D." },
                new() { Dvar = "gf_forge_scalestep", Label = "Scale step (% per tick)", Kind = SettingKind.Int, Default = 2, Min = 1, Max = 20, Step = 1, Eff = Eff.Live, Tip = "gf_forge_scalestep\nADS + distance adjust = scale change per tick, in percent." },
                new() { Dvar = "gf_forge_zstep", Label = "Height step (u per tick)", Kind = SettingKind.Int, Default = 4, Min = 1, Max = 30, Step = 1, Eff = Eff.Live, Tip = "gf_forge_zstep\nHeight change per tick where the scheme offers a height adjust (pinned mode: jump / crouch)." },
            },
        },
    };

    public static readonly Dictionary<string, SettingDef> ByDvar = Sections.SelectMany(s => s.Rows).ToDictionary(r => r.Dvar);
    public static IEnumerable<SettingDef> All => Sections.SelectMany(s => s.Rows);
}
