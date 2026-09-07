// Cold War (T9, VM38) smoke-test script.
//   .\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc      (from the repo root)
//   acts injectcw gunfight_tweaks.gscc scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc
//
// Purpose: prove the inject pipeline works before changing any behaviour.
// If the connect message appears in-game, then injection, system::register,
// callback registration and level.* access are all working.

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace gftweaks;

// `private` matches all 859 stock __init__system__ instances. They are private
// specifically so identically-named autoexecs cannot collide; a non-private one
// would be the only such symbol in the process. See docs/notes/toolchain.md.
function private autoexec __init__system__()
{
    system::register( #"gftweaks", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start_gametype );
    callback::on_connect( &on_player_connect );
}

function on_start_gametype()
{
    // globallogic::init() reads these once from the gametype settings, so
    // overwriting the level vars here is what actually takes effect.
    // maxteamplayers is honoured only when teamcount == 0 or
    // com_maxclients == teamcount -- otherwise com_maxclients wins.
    // See .claude/team-sizes.md before trusting a result from this.
    level.maxteamplayers = 6;

    // Overriding teamcount here is NOT enough: init_teams() has already built
    // level.teams from it. Left in only to observe whether anything reacts.
    level.teamcount = 2;
}

function on_player_connect()
{
    self iprintln( "gftweaks loaded: maxteamplayers=" + level.maxteamplayers );
}
