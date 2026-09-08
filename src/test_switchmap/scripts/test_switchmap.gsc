// ─────────────────────────────────────────────────────────────────────────────
// TEST C6 — does switchmap_load reconfigure the session, or only the map?
//
// docs/notes/test-queue.md C6 · docs/notes/atian-menu-source.md
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// ⚠⚠ START IN A PRIVATE **TDM** LOBBY, NOT GUNFIGHT. The whole test is whether a
//    12-slot lobby KEEPS its 12 slots after the gametype is switched to Gunfight
//    in place. Starting in Gunfight makes the reading meaningless.
//
// WHY. com_maxclients is fixed at lobby creation by the playlist and script only
// ever reads it. The map carry (map()) is a load-time override that leaves the
// session alone - which is why the scoreboard still names the old map, and why it
// can never move the slot count.
//
// switchmap_load is a DIFFERENT builtin that takes a gametype and runs a
// preload -> load -> switch sequence. Whether that reaches the playlist layer is
// unknown, and it is the layer com_maxclients is fixed at.
//
// func_set_gametype() in the Atian Menu's Cold War source does exactly this and is
// dead code - written, present, never wired into the menu. This is that function,
// extracted, with instrumentation.
//
// ⚠ The gametype argument is OPTIONAL per the function table (switchmap_load is
//   1-2 args). That the 2-arg form EXISTS does not prove the CW build honours the
//   second argument. If probe 2 never reads 1, that is the finding: record it.
//
// ⚠ ate47 on the sequence: "the wait is important, I don't know why."
//   Empirical, not understood. Do not remove the wait.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// This script emits on EVERY on_start_gametype - so you get one reading before
// the switch and another after. That is the measurement.
//
//   1xxxxx  com_maxclients
//   2xxxxx  is the live gametype our target?  1/0
//
// Expected sequence:
//   BEFORE   100012 / 200000     TDM lobby, 12 slots, not yet Gunfight
//   AFTER    100012 / 200001     <- THE WIN. Gunfight running in a 12-slot lobby
//        or  100008 / 200001     <- switchmap re-derived the lobby from the
//                                   gametype, same as the map carry. No win.
//        or  1xxxxx / 200000     <- the gametype argument was ignored entirely
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_switchmap;

function private autoexec __init__system__()
{
    system::register( #"test_switchmap", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread run();
}

function private run()
{
    // ── config. Plain locals, not preprocessor macros - see test_addclients.gsc.

    // ✅ CONFIRMED against ate47/bocw-source (PRIMARY dump) 2026-09-08:
    //      player_record.gsc:589            case #"gunfight_3v3":
    //      hashed/script/script_74453936abc39adf.gsc:68   case #"gunfight_3v3":
    //
    // ⚠ A retraction of this was briefly written and is itself WRONG. The alternate
    //   dump (shiversoftdev/t9-src) leaves that name as an unresolved hash, so a grep
    //   for the literal found nothing - absence in the alternate dump is not absence
    //   in the game. See docs/notes/dump-cross-check.md.
    //
    //   If lobby_probe's bitmask turns up another variant, try that here.
    target = "gunfight_3v3";

    // ⚠ RUN WITH THIS AT 1 FIRST. It reports the lobby state and switches nothing,
    //   which confirms you are in the right lobby before spending a session reload.
    read_only = 1;

    wait( 10 );

    live = getdvarstring( #"g_gametype", "" );

    is_target = 0;
    if ( live == target )
    {
        is_target = 1;
    }

    emit( 1, getdvarint( #"com_maxclients", 0 ) );
    emit( 2, is_target );

    if ( read_only )
    {
        return;
    }

    // Already there - switching again would prove nothing and costs a reload.
    if ( is_target )
    {
        return;
    }

    // ── The switch. This is func_set_gametype() from the Atian Menu CW source. ──
    switchmap_load( util::get_map_name(), target );
    wait( 1 );                  // load-bearing per ate47; reason unknown
    switchmap_switch();

    // Nothing after this line is guaranteed to run - the session is reloading.
    // The post-switch reading comes from this script's NEXT on_start, not here.
}

function private emit( id, value )
{
    v = 99999;
    if ( isdefined( value ) )
    {
        v = value;
    }

    tagged = id * 100000 + v;

    foreach ( player in getplayers() )
    {
        player iprintlnbold( tagged );
    }

    wait( 5 );
}
