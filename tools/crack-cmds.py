#!/usr/bin/env python3
"""Recover console-command NAMES from `acts dcfuncscw`'s hashed output.

    acts dcfuncscw                      # on the test box, game running, in the lobby
    python3 tools/crack-cmds.py cfuncs_cw.csv
    python3 tools/crack-cmds.py cfuncs_cw.csv --words=setlobbymap,uisetmap
    python3 tools/crack-cmds.py --hash map_restart          # forward direction

WHY THIS EXISTS. `acts dcfuncscw` walks the game's console-command linked list
(`cmd_function_t` from a hardcoded base) and writes location,name,func - but the
NAME column is a hash. That list is the definitive answer to "is there a command
that sets the lobby's map", which is the one thing standing between us and a
one-line DLL for Gunfight-on-any-map. See docs/notes/lobby-map-dll.md.

SAME ALGORITHM as tools/crack-hash.py - FNV1a64, lowercased, & MASK63. This tool
adds a COMMAND-SHAPED vocabulary instead of a gametype-settings one, because
that is the whole game: the names that crack are the ones you can guess, and
console commands are named nothing like gametype settings.

⚠ It also tries the UNMASKED 64-bit form. tools/crack-hash.py does not, because
  every hash it targets came out of GSC where the mask is certain. Here the hash
  comes from an engine struct read out of process memory, and unlock-dlls.md
  already records one place the two forms differ:
      acts h64 loot_fakeall  -> 60cdc482a7d159f8   (masked)
      raw FNV-1a 64          -> e0cdc482a7d159f8
  Guessing wrong about the mask would read as "the wordlist was wrong", which is
  the one failure mode this project keeps having to walk back.

⚠ A MISS MEANS THE WORDLIST WAS WRONG. It does not mean the command is absent -
  report it as "not found with N candidates" and add guesses with --words.
"""
import csv, itertools, os, sys

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK63 = 0x7FFFFFFFFFFFFFFF
FNV1A_PRIME = 0xcbf29ce484222325
IV_DEFAULT = 0x100000001b3


def fnv(s):
    h = FNV1A_PRIME
    for c in s.lower():
        h = ((h ^ ord(c)) * IV_DEFAULT) & MASK64
    return h


# Console commands, not gametype settings. Quake-lineage verbs plus the
# BOCW-specific lobby vocabulary that cwpatch already proves exists
# (lobbylaunchgame, killserver, fast_restart, full_restart are all real).
KNOWN = [
    # confirmed real in this game, from unlock-dlls.md - CONTROLS for the run.
    # If none of these five crack, the hash form is wrong, not the wordlist.
    "lobbylaunchgame", "killserver", "fast_restart", "full_restart", "map_restart",
    # ── every resolved T8 (BO4) console command, from ate47's docs/notes/cfuncs.csv ──
    # BO4 and BOCW share the engine lineage. lobbylaunchgame is on this list and
    # cwpatch proved it real in CW, so these are the strongest candidates available
    # short of dumping CW itself. Of particular interest for the lobby:
    #   gametype_setting  gametype  map  customgames_save  customgames_load
    #   lobbyrunplaylistsettings  lobby_reload  sendinvite  joinplayersessionbyxuid
    "addthumbnail", "allscenescaptured", "answertotp", "applyconversion",
    "awardplatformachievement", "bancheck", "banclient", "banuser", "bbdisable", "bbenable",
    "bbsend", "bgcacheprintitems", "bind", "bind2", "bindaxis", "bindlist",
    "builditemlistforgroup", "builditemlistforgroupforweapontable",
    "builditemlistforgroupname", "builditemlistforslotname",
    "builditemlistforslotnameandgroup", "callvote", "camerashake", "canceldemonwareconnect",
    "capturegfxframe", "cg_shellshock", "cg_toggleinventory", "cg_togglemap",
    "cg_togglescores", "cgprintentities", "chatmodelast", "chatmodeparty", "chatmodepublic",
    "chatmodeteam", "checkclanname", "checkdlcownership", "checkpoint_restart",
    "checkprestigefeatureban", "chooseclass_hotkey", "clear", "clearallitemsnew",
    "clearallloadoutslots", "clearallloadoutslotsmpcustom", "clearallloadoutslotsmpoffline",
    "clearallloadoutslotsmppublic", "clearallloadoutslotszmoffline",
    "clearallloadoutslotszmonline", "clearcustomleaderboards", "clearitemnew",
    "clearkeystates", "clearloadoutslot", "clearloadoutslotmpcustom",
    "clearloadoutslotmpoffline", "clearloadoutslotmppublic", "clearloadoutslotzmoffline",
    "clearloadoutslotzmonline", "clearpsdata", "clearrecentplayers", "clientinfo",
    "clientkick", "clientkick_for_reason", "cmd", "con_hidelabel", "con_labellist",
    "con_showlabel", "configstrings", "consumable_dec", "consumable_get", "consumable_inc",
    "consumable_set", "copybubblegumpack", "copyclass", "csv_start", "csv_stop",
    "csvdumpassets", "csvdumpstats", "customgames_count", "customgames_load",
    "customgames_save", "defaultbindings", "demo_abortfilesharedownload",
    "demo_activatefreecameralockon", "demo_adddollycammarker", "demo_addlightmanmarker",
    "demo_applynewdollycammarkerposition", "demo_applynewlightmanmarkerposition", "demo_back",
    "demo_cancelhighlightreelcreation", "demo_cancelpreview", "demo_capturesegmentthumbnail",
    "demo_clearrenderflag", "demo_deactivatefreecameralockon", "demo_deleteclip",
    "demo_deletesegment", "demo_editdollycammarker", "demo_editlightmanmarker", "demo_forward",
    "demo_getfreecameraparams", "demo_hidegamehud", "demo_jumptostart", "demo_keyboard",
    "demo_mergesegments", "demo_movesegment", "demo_pause", "demo_pausecliprecord",
    "demo_play", "demo_previewclip", "demo_previewsegment",
    "demo_rebuildhighlightreeltimeline", "demo_regeneratehighlightreel",
    "demo_removedollycammarker", "demo_removelightmanmarker", "demo_repositiondollycammarker",
    "demo_repositionlightmanmarker", "demo_saveanduploadclip", "demo_savescreenshot",
    "demo_savesegment", "demo_screenshot", "demo_setfreecameraparams", "demo_setlagflag",
    "demo_startautodollycam", "demo_startcliprecord", "demo_stop", "demo_stopautodollycam",
    "demo_switchcamera", "demo_switchcontrols", "demo_switchdollycammarker",
    "demo_switchlightmanmarker", "demo_switchplayer", "demo_switchtransition",
    "demo_timescale", "demo_toggledemohud", "demo_togglegamehud",
    "demo_updatedollycammarkerparameters", "demo_updatelightmanmarkerparameters",
    "demo_updatesavepopupuimodels", "demoupdatelobbyinformation", "devmap",
    "disableallbutprimaryclients", "disableallclients", "disconnect", "dobjdump",
    "dobjdumpbonecounts", "downloaddemofile", "dumpallspecialitemskus", "dumpdir", "dumpents",
    "dumpimages", "dumplivegroups", "dumpmateriallist", "dumpmodels", "dumpqos", "dumpuser",
    "dvaraddconfigflag", "dwprintaddrs", "dwtesthash", "emblembackgroundflushresults",
    "emblemflushresults", "emblemmovedownrepeatenabled", "emblemmoveleftrepeatenabled",
    "emblemmoverightrepeatenabled", "emblemmoveuprepeatenabled", "emblemrepeatbttnsloosefocus",
    "emblemrotateleftrepeatenabled", "emblemrotaterightrepeatenabled",
    "emblemscaledownrepeatenabled", "emblemscaleuprepeatenabled", "emblemsetposition",
    "equipclass", "equipdefaultclass", "equipdefaultclasstoprofile",
    "equipdefaultcustommatchclass", "equipdefaultitemtoslot", "equiploadoutslot",
    "equiploadoutslotmpcustom", "equiploadoutslotmpoffline", "equiploadoutslotmppublic",
    "equiploadoutslotzmoffline", "equiploadoutslotzmonline", "equiploadoutweaponslot",
    "equiploadoutweaponslotmpcustom", "equiploadoutweaponslotmpoffline",
    "equiploadoutweaponslotmppublic", "equiploadoutweaponslotzmoffline",
    "equiploadoutweaponslotzmonline", "exec", "execcontrollerbindings", "execlua",
    "fakedwdisconnect", "fakewhitelist", "fast_restart", "featurechecksum", "fetchproducts",
    "fileshareabortsummary", "filesharedirty", "filesharegetpopularfiles",
    "filesharegetslotdata", "filesharegetsummary", "filesharegetusersummaryfile",
    "filesharegetvotestats", "filesharereset", "fileshareresetsummaryfiles",
    "filesharesetready", "filesharestartup", "filesharesubmitdownload", "filesharesubmitview",
    "fileshareupdatemetadata", "flushkvs", "flushpaintjobcache", "follownext", "followprev",
    "forcesynctime", "freedemomemory", "fshsearchclear", "fshsearchrecentgames",
    "fshsearchtest", "full_restart", "fullpath", "gamesettings_clearuploadinfo",
    "gamesettings_download", "gamesettings_upload", "gametype", "gametype_setting",
    "getprofile", "getuserobjectcounts", "getxp", "gpadmapany", "gpadupdate", "gts",
    "havok_mem", "heartbeat", "hostmigration_start", "if_mp", "in_restart",
    "initiatedemonwareconnect", "invalidaterenders", "isbadword", "join", "joinlivegroup",
    "joinplayersessionbyxuid", "kick", "killserver", "leaderboards_finalize", "leavelivegroup",
    "listallassets", "listassetpool", "listdefaultassets", "livedelayedcomerror",
    "livephrasetest", "loadbinds", "loadcommonff", "loadcrmmessages", "loadside", "loadzone",
    "lobby_errorshutdown", "lobby_reload", "lobby_test", "lobbylaunchdemo", "lobbylaunchgame",
    "lobbyloadspecificdemo", "lobbyrunplaylistsettings", "lobbystopdemo", "logglytest", "logo",
    "luicollectgarbage", "luidebugreload", "luidebugrestart", "luimemoryreport",
    "luiprintelementtree", "luirefcountreport", "map", "map_rotate",
    "marketing_markmessageasviewed", "mission_restart", "mr", "mrp", "msload", "mspreload",
    "mychanges_restart", "net_dumpprofile", "net_restart", "netchandump", "netqueue",
    "netstatsdump", "netstatsupdate", "notifystatschanged", "ntpsync", "onlykick", "path",
    "pcacherank", "playrumble", "preservethumbnails", "printlivememusage", "pubsemaphorefetch",
    "purchaseitem", "quit", "r_printalloc", "reconnect", "refetchbalances", "refetchinventory",
    "refreshlastinput", "reinit_restart", "reportuser", "reset", "resetbubblegumpackoffline",
    "resetbubblegumpackonline", "resetclasssetnamempcustom", "resetclasssetnamemppublic",
    "resetclasssetslotmpcustom", "resetclasssetslotmppublic",
    "resetcurrentclasssetindexmpcustom", "resetcurrentclasssetindexmppublic",
    "resetleaderboard", "resetleaderboards", "resetloadoutmpcustom", "resetloadoutmpoffline",
    "resetloadoutmppublic", "resetloadoutzmoffline", "resetloadoutzmonline",
    "resetmpcharacterloadout", "resetmpshowcaseweaponattribute",
    "resetmpshowcaseweaponattributearray", "resetmpshowcaseweaponvariantname",
    "resetprofilecommon", "resetthumbnailviewer", "restrict_attachment", "restrict_item",
    "runluapostdeploymentfunction", "savebinds", "saveclasssets", "savegamecreate",
    "savegamerestore", "saveloadout", "savestats", "say", "say_team", "screenshot",
    "screenshotjpeg", "screenshotpng", "screenshotviewerabortdownload",
    "screenshotviewerdownload", "scriptthreadusage", "selectbindings",
    "selectstringtableentryindvar", "sendinstantmessage", "sendinvite", "serverinfo", "set",
    "setcca", "setclanname", "setclientbeingused", "setclientbeingusedandactive",
    "setclientbeingusedandprimary", "setclientbeingusedandprimaryandactive",
    "setclientnotbeingused", "setclientprimary", "setdvartotime", "setenv",
    "setfocusscoreboard", "setmotdviewed", "setperk", "setprofile", "setstat", "setstatcfg",
    "setstatfromlocstring", "setupthumbnailforfilesharesave", "setupthumbnailformarketing",
    "setupthumbnailsformanagesegments", "setupviewport", "setupweapondefs",
    "shoutcastaddlistenin", "shoutcaster_thirdperson", "shoutcastremovelistenin",
    "shoutcastresetlistenin", "shoutcastsetlistenin", "shoutcastsetlisteninteam", "showip",
    "skilltest", "snd_playlocal", "snd_restart", "spawndebug_user_badspawn",
    "spawnsystem_devgui", "startgfxcapture", "startwzmatch", "stataddbyname",
    "statgetbynameindvar", "statreadddl", "statreadddlext", "statsetbyname", "status",
    "statwriteddl", "statwritemode", "stopgfxcapture", "storageclear", "storageclearall",
    "storagewriteddl", "stringusage", "switchmaps", "systeminfo", "tcc", "teamstatus",
    "tempbanclient", "tempbanuser", "testpreload", "timewarpadd", "timewarpreset",
    "timewarpset", "toggle", "togglebandwidthprofile", "togglemenu", "togglep", "touchfile",
    "ugcload", "ui_browser_new", "ui_keyboard_cancel", "ui_keyboard_complete",
    "ui_keyboard_new", "uiequipdefaultclass", "unbind", "unbind2", "unbindall",
    "unbindallaxis", "updatecards", "updatedifficultyfromprofile", "updategamerprofile",
    "updateinfoforingamelist", "updatelivegroup", "updatemusthavebindings",
    "updatevehiclebindings", "uploadprofile", "uploadstats", "vid_restart", "viewpos",
    "voicechat", "voiceteamchat", "vote", "vote_gethistory", "vote_submitdislike",
    "vote_submitlike", "wait", "weapnext", "weapprev", "where", "writedefaults",
    "xpartystopdemo", "xshowgamercard", "xsignin", "xsigninguest", "xsigninlive",
    # quake lineage
    # harvested from the dump as command-shaped strings - the only two that were
    "party_autoteams", "matchmaking",
    # CoD-lineage party / matchmaking spellings, single tokens the generator
    # cannot compose because they are not head+stem+tail shaped
    "xpartyjoin", "xpartyleave", "xpartykick", "xpartyinvite", "xpartycreate",
    "xpartygo", "xpartyreadyup", "partygo", "partyready", "partybackout",
    "matchmake", "startmatchmaking", "stopmatchmaking", "cancelmatchmaking",
    "findgame", "searchforgame", "cancelsearch", "quicksearch", "quickmatch",
    "joinsession", "leavesession", "joinlobby", "leavelobby", "joinparty",
    "leaveparty", "lobbyjoin", "lobbyleave", "lobbycreate", "lobbyready",
    "invitefriend", "acceptinvite", "declineinvite", "joinfriend", "join_friend",
    "map", "devmap", "connect", "disconnect", "reconnect", "quit", "exec",
    "bind", "unbind", "set", "seta", "sets", "setu", "toggle", "vstr", "wait",
    "cmdlist", "dvarlist", "screenshot", "clear", "echo", "kick", "banclient",
    "status", "serverinfo", "systeminfo", "spdevmap", "loadgame", "savegame",
    "restart", "vid_restart", "snd_restart", "reset", "resetdvars",
]

# ⚠ D10 has a SECOND question since 2026-09-09: klaze ruled the glitch's aborted
# matchmaking search acceptable, so if party join / leave and the search itself are
# console commands, the glitch could become one button from the DLL slot. The
# dump cannot seed this - scripts never exec() console strings, and its party /
# lobby hits are scene-animation names (lobby_pose, lobbyinspection) - so the
# vocabulary below is CoD-lineage console knowledge, and a miss here means the
# names were spelled differently, not that the operations are absent.
HEADS = ["", "set", "get", "ui", "lobby", "host", "party", "match", "game",
         "sv", "cl", "mp", "dev", "start", "launch", "change", "select", "force",
         "xparty", "live", "xblive", "mm", "session", "invite", "join", "leave",
         "cancel", "stop", "find", "search"]
STEMS = ["map", "maps", "gametype", "gametypes", "mode", "playlist", "lobby",
         "match", "game", "round", "team", "teams", "player", "players", "bot",
         "bots", "client", "clients", "spectator", "caster", "rotation", "level",
         "party", "session", "matchmaking", "matchmake", "search", "invite",
         "invites", "friend", "friends", "host", "member", "members", "leader",
         "squad", "fill", "queue"]
VERBS = ["set", "get", "change", "select", "load", "start", "launch", "join",
         "leave", "create", "cancel", "find", "pick", "choose", "vote"]
TAILS = ["", "name", "list", "index", "select", "set", "load", "start", "launch",
         "next", "restart", "change", "override", "count", "size", "join", "leave",
         "kick", "invite", "accept", "decline", "cancel", "stop", "begin", "end",
         "create", "destroy", "migrate", "autoteams", "teams", "ready", "toggle"]


def candidates(extra):
    seen = set()
    for w in KNOWN:
        if w not in seen:
            seen.add(w)
            yield w
    for h, s, t, sep in itertools.product(HEADS, STEMS, TAILS, ["", "_"]):
        w = (h + sep if h else "") + s + (sep + t if t else "")
        if w and w not in seen:
            seen.add(w)
            yield w
    # head + TWO stems, because the shape we most want is compound:
    # setlobbymap, changegamemap, uiplaylistmap. The single-stem pass above
    # cannot reach those, and the self-test proved it by missing setlobbymap.
    for h, s1, s2, sep in itertools.product(HEADS, STEMS, STEMS, ["", "_"]):
        if s1 == s2:
            continue
        w = (h + sep if h else "") + s1 + sep + s2
        if w not in seen:
            seen.add(w)
            yield w
    # head + VERB + stem: lobby_set_map, party_join_session, ui_select_playlist.
    # The self-test on 2026-09-09 missed lobby_set_map because "set" is a head,
    # not a stem, so no pass above could put it in the middle. A miss on exactly
    # the shape D10 most wants is the kind of gap that reads as "the command does
    # not exist" if nobody checks the generator - so this pass exists, and the
    # test file keeps lobby_set_map in it.
    for h, v, st, sep in itertools.product(HEADS, VERBS, STEMS, ["", "_"]):
        if not h or v == h or st == v:
            continue
        w = h + sep + v + sep + st
        if w not in seen:
            seen.add(w)
            yield w
    for w in extra:
        w = w.strip()
        if w and w not in seen:
            seen.add(w)
            yield w


# Anything whose name contains one of these is worth a human look even if the
# rest of the dump is noise - these are the shapes that could set a lobby's map.
INTERESTING = ("map", "gametype", "playlist", "lobby", "launch", "mode",
               "party", "match", "search", "session", "invite", "join")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    extra, forward = [], False
    for a in sys.argv[1:]:
        if a.startswith("--words="):
            extra = a.split("=", 1)[1].split(",")
        elif a == "--hash":
            forward = True

    if forward:
        for name in args:
            print("%-28s masked %016x   raw %016x"
                  % (name, fnv(name) & MASK63, fnv(name)))
        return 0

    if not args:
        print(__doc__)
        return 2

    path = args[0]
    if not os.path.isfile(path):
        print("no such file: %s\n\nRun `acts dcfuncscw` on the test box first, with the\n"
              "game RUNNING and sitting in the lobby you care about." % path)
        return 2

    # Build both tables once; a command list is thousands of rows and the
    # candidate set is ~30k, so hashing per row would be quadratic for nothing.
    cands = list(candidates(extra))
    masked = {}
    raw = {}
    for w in cands:
        h = fnv(w)
        masked.setdefault(h & MASK63, w)
        raw.setdefault(h, w)

    rows, hits, controls = 0, [], 0
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            val = (row.get("name") or "").strip()
            if not val:
                continue
            try:
                h = int(val, 16) if not val.isdigit() else int(val)
            except ValueError:
                continue
            rows += 1
            name = masked.get(h & MASK63) or raw.get(h)
            if name:
                hits.append((name, row.get("func", ""), row.get("location", "")))
                if name in KNOWN[:5]:
                    controls += 1

    print("commands in file: %d      candidates tried: %d      resolved: %d"
          % (rows, len(cands), len(hits)))
    print()
    if controls == 0:
        print("⚠⚠ NONE of the five known-real controls resolved "
              "(lobbylaunchgame, killserver,")
        print("   fast_restart, full_restart, map_restart). Do NOT read anything into the")
        print("   rest of this output - the hash form or the CSV column is wrong, not the")
        print("   wordlist. Check tools/crack-cmds.py --hash map_restart against a value")
        print("   you can see in the file.")
        print()
    else:
        print("✅ %d of 5 controls resolved - the hash form is right.\n" % controls)

    interesting = [h for h in hits if any(k in h[0] for k in INTERESTING)]
    print("=== map / gametype / lobby shaped (%d) ===" % len(interesting))
    for name, func, loc in sorted(interesting):
        print("  %-30s func %s" % (name, func))
    print()
    print("=== everything else resolved (%d) ===" % (len(hits) - len(interesting)))
    for name, func, loc in sorted(h for h in hits if h not in interesting):
        print("  %s" % name)
    print()
    print("⚠ %d of %d commands did NOT resolve. That is the wordlist being wrong,"
          % (rows - len(hits), rows))
    print("  not the commands being absent. Add guesses with --words=a,b,c.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
