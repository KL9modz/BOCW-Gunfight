namespace GfPanel.Game;

public sealed record MapDef(string Name, string Id, string Group, string? Gametype = null, string Note = "")
{
    public string Label => $"{Name}  [{Id}]";
}

public sealed record Named(string Label, string Value, string Note = "") { public override string ToString() => Label; }
/// <summary>A veh_master() row. Maps = the maps any of its copies loads on (docs/data/vehicle-assets.json, the zone
/// tables); null = every map (core_common / mp_common) or unknown - never hidden.</summary>
public sealed record VehicleDef(int Index, string Label, int Kind, string[]? Maps = null)
{
    public bool Drivable => Kind == 0;
    /// <summary>Loaded on this map? An empty map name (no match running) shows everything.</summary>
    public bool On(string map) => Maps == null || map.Length == 0 || Array.IndexOf(Maps, map) >= 0;
    public override string ToString() => Label;
}
public sealed record PerkDef(string Key, string Label, string Note = "") { public override string ToString() => Label; }
public sealed record ColorDef(string Code, string Name, string Hex);
public sealed record DurDef(string Label, int Value) { public override string ToString() => Label; }

/// <summary>Every static list the panel offers, extracted from gunfight_menu.gsc's pages (the menu is the
/// authority; docs/reference/bocw-maps.md / bocw-weapons.md carry the provenance). Labels marked ? are inferred.</summary>
public static class Catalog
{
    public static readonly MapDef[] Maps =
    {
        new("Amerika", "mp_amerika", "6v6"), new("Apocalypse", "mp_apocalypse", "6v6"),
        new("Armada Strike", "mp_black_sea", "6v6"), new("Cartel", "mp_cartel", "6v6"),
        new("Checkmate", "mp_kgb", "6v6"), new("Collateral Strike", "mp_dune", "6v6"),
        new("Crossroads (full 12v12 layout)", "mp_tundra", "6v6"), new("Deprogram", "mp_firebase", "6v6"),
        new("Diesel", "mp_sm_gas_station", "6v6"), new("Drive-In", "mp_drivein_rm", "6v6"),
        new("Echelon", "mp_echelon", "6v6"), new("Express", "mp_express_rm", "6v6"),
        new("Garrison", "mp_tank", "6v6"), new("Hijacked", "mp_hijacked_rm", "6v6"),
        new("Jungle", "mp_jungle_rm", "6v6"), new("Miami", "mp_miami", "6v6"),
        new("Miami Strike", "mp_miami_strike", "6v6"), new("Moscow", "mp_moscow", "6v6"),
        new("Nuketown '84", "mp_nuketown6", "6v6"), new("Raid", "mp_raid_rm", "6v6"),
        new("Rush", "mp_paintball_rm", "6v6"), new("Satellite", "mp_satellite", "6v6"),
        new("Slums", "mp_slums_rm", "6v6"), new("Standoff", "mp_village_rm", "6v6"),
        new("The Pines", "mp_mall", "6v6"), new("WMD", "mp_russianbase_rm", "6v6"),
        new("Yamantau", "mp_cliffhanger", "6v6"), new("Zoo", "mp_zoo_rm", "6v6"),
        new("Amsterdam", "mp_sm_amsterdam", "Gunfight"), new("Game Show", "mp_sm_game_show", "Gunfight"),
        new("Gluboko", "mp_sm_vault", "Gunfight"), new("ICBM", "mp_sm_central", "Gunfight"),
        new("KGB", "mp_sm_finance", "Gunfight"), new("Mansion", "mp_sm_market", "Gunfight"),
        new("Showroom", "mp_sm_deptstore", "Gunfight"), new("U-Bahn", "mp_sm_berlin_tunnel", "Gunfight"),
        new("Armada 12v12", "mp_black_sea", "12v12", "tdm10v10", "TDM 10v10 string opens the 12v12 boundary"),
        new("Collateral 12v12", "mp_dune", "12v12", "tdm10v10", "TDM 10v10 string opens the 12v12 boundary"),
        new("Crossroads 12v12", "mp_tundra", "12v12", "tdm10v10", "TDM 10v10 string opens the 12v12 boundary"),
        new("Alpine", "wz_ski_slopes", "Fireteam", null, "untested"), new("Duga", "wz_duga", "Fireteam", null, "untested"),
        new("Golova", "wz_golova", "Fireteam", null, "untested"), new("Ruka", "wz_forest", "Fireteam", null, "untested"),
        new("Sanatorium", "wz_sanatorium", "Fireteam", null, "untested"),
    };
    public static string MapName(string id) => Maps.FirstOrDefault(m => m.Id == id && m.Gametype == null)?.Name ?? id;

    public static readonly Named[] Gametypes =
    {
        new("Gunfight", "gunfight"), new("Gunfight 3v3", "gunfight_3v3"), new("Team Deathmatch", "tdm"), new("TDM 10v10", "tdm10v10"),
        new("Free-for-all", "dm"), new("Domination", "dom"), new("Hardpoint", "koth"), new("Search & Destroy", "sd"),
        new("Kill Confirmed", "conf"), new("Control", "control"), new("Capture the Flag", "ctf"), new("Demolition", "dem"),
        new("Infected", "infect"), new("Gun Game", "gun"), new("Prop Hunt", "prop"), new("Sticks and Stones", "sas"),
        new("One in the Chamber", "oic"), new("Dropkick", "dropkick"), new("VIP Escort", "vip"), new("Team War", "war"), new("Cranked", "cranked"),
    };

    public static readonly (string Group, Named[] Items)[] Weapons =
    {
        // ⚠ VERIFIED 2026-09-23 (bocw-84) against the CoD wiki's Black Ops Cold War internal names (each weapon page's
        // `console` field) - the older labels were inferred and 17 rows gave the wrong gun. Same table as build_tree.
        ("Assault rifles", new Named[] { new("XM4", "ar_standard_t9"), new("AK-47", "ar_damage_t9"), new("Krig 6", "ar_accurate_t9"), new("QBZ-83", "ar_mobility_t9"), new("FFAR 1", "ar_fastfire_t9"), new("Groza", "ar_fasthandling_t9"), new("FARA 83", "ar_slowhandling_t9"), new("C58", "ar_slowfire_t9"), new("EM2", "ar_british_t9"), new("Vargo 52", "ar_soviet_t9"), new("Grav", "ar_season6_t9") }),
        ("SMGs", new Named[] { new("MP5", "smg_standard_t9"), new("Milano 821", "smg_handling_t9"), new("AK-74u", "smg_heavy_t9"), new("KSP 45", "smg_burst_t9"), new("Bullfrog", "smg_capacity_t9"), new("MAC-10", "smg_fastfire_t9"), new("LC10", "smg_accurate_t9"), new("PPSh-41", "smg_spray_t9"), new("OTs 9", "smg_cqb_t9"), new("TEC-9", "smg_semiauto_t9"), new("LAPA", "smg_season6_t9"), new("UGR", "smg_flechette_t9") }),
        ("Tactical rifles", new Named[] { new("M16", "tr_longburst_t9"), new("AUG", "tr_powerburst_t9"), new("CARV.2", "tr_fastburst_t9"), new("DMR 14", "tr_precisionsemi_t9"), new("Type 63", "tr_damagesemi_t9") }),
        ("LMGs", new Named[] { new("Stoner 63", "lmg_accurate_t9"), new("RPD", "lmg_light_t9"), new("M60", "lmg_slowfire_t9"), new("MG 82", "lmg_fastfire_t9") }),
        ("Snipers", new Named[] { new("Pelington 703", "sniper_quickscope_t9"), new("LW3 Tundra", "sniper_standard_t9"), new("M82", "sniper_powersemi_t9"), new("ZRG 20mm", "sniper_cannon_t9"), new("Swiss K31", "sniper_accurate_t9") }),
        ("Shotguns", new Named[] { new("Hauer 77", "shotgun_pump_t9"), new("Gallo SA12", "shotgun_semiauto_t9"), new("Streetsweeper", "shotgun_fullauto_t9"), new(".410 Ironhide", "shotgun_leveraction_t9") }),
        ("Pistols", new Named[] { new("1911", "pistol_semiauto_t9"), new("Magnum", "pistol_revolver_t9"), new("Diamatti", "pistol_burst_t9"), new("AMP63", "pistol_fullauto_t9"), new("Marshal", "pistol_shotgun_t9"), new("1911 akimbo", "pistol_semiauto_t9_dw"), new("Magnum akimbo", "pistol_revolver_t9_dw"), new("Diamatti akimbo", "pistol_burst_t9_dw"), new("AMP63 akimbo", "pistol_fullauto_t9_dw"), new("Marshal akimbo", "pistol_shotgun_t9_dw") }),
        ("Launchers + special", new Named[] { new("Cigma 2", "launcher_standard_t9"), new("RPG-7", "launcher_freefire_t9"), new("M79", "special_grenadelauncher_t9"), new("R1 Shadowhunter", "special_crossbow_t9"), new("Nail Gun", "special_nailgun_t9"), new("Ballistic Knife", "special_ballisticknife_t9_dw") }),
        ("Melee", new Named[] { new("Knife", "knife_loadout"), new("Sledgehammer", "melee_sledgehammer_t9"), new("Wakizashi", "melee_wakizashi_t9"), new("Machete", "melee_machete_t9"), new("E-Tool", "melee_etool_t9"), new("Baseball Bat", "melee_baseballbat_t9"), new("Mace", "melee_mace_t9"), new("Sai", "melee_sai_t9_dw"), new("Cane", "melee_cane_t9"), new("Battle Axe", "melee_battleaxe_t9"), new("Hammer & Sickle", "melee_coldwar_t9_dw"), new("Scythe", "melee_scythe_t9"), new("Knife - Scream", "hash_28fdaa999c8aa3af"), new("Knife - Infected", "hash_3f47e8be065a0dc0") }),
        // Ray Gun out (2026-09-23): ray_gun sits in no MP / core zone table (only frontend + ZM), never givable here
        ("Scorestreak guns (BO4 leftovers, untested)", new Named[] { new("Flamethrower - Purifier", "hero_flamethrower"), new("Annihilator", "hero_annihilator"), new("War Machine", "hero_pineapplegun"), new("Death Machine", "sig_lmg"), new("Sparrow bow", "sig_bow_flame"), new("Turret gun", "ultimate_turret") }),
    };

    public static readonly Named[] Projectiles =
    {
        new("RPG rocket (free-fire launcher)", "launcher_freefire_t9"), new("Cigma missile (lock-on)", "launcher_standard_t9"),
        new("Crossbow bolt", "special_crossbow_t9"), new("M79 grenade", "special_grenadelauncher_t9"),
        new("Combat bow arrow (explosive)", "sig_bow_flame"), new("Strafe run rocket", "straferun_rockets"),
        new("Cruise missile bomblet", "remote_missile_bomblet"), new("Jet fighter missile", "jetfighter_missile"), new("Frag grenade", "frag_grenade"),
        // fun pack (PHA's bullet types) + fun pack 2 (the stun); the four streak/equipment ones spawn via magicmissile on AUTO
        new("War Machine grenade", "hero_pineapplegun"), new("Cruise missile", "remote_missile_missile"), new("Hand Cannon round", "hero_annihilator"),
        new("Death Machine round", "sig_lmg"), new("Ballistic knife", "special_ballisticknife_t9_dw"), new("Napalm bomb", "napalm_strike"),
        new("Artillery shell", "planemortar"), new("Stun grenade", "eq_slow_grenade"),
    };

    // The menu's prop_universal() list, by label (the GSC matches the label or the model; the 47-byte slot takes the label).
    public static readonly Named[] Props =
    {
        new("Park bench", "p9_usa_bench_01"), new("Bicycle", "p9_usa_bicycle_01"), new("Couch", "p9_usa_couch_04"), new("Dumpster", "p9_usa_dumpster_01_full"),
        new("Mailbox", "p9_usa_mailbox_01"), new("Street light", "p9_usa_street_light_01"), new("Soda machine", "p9_usa_vending_machine_soda_02"),
        new("Target dummy", "p9_usa_kgb_target_dummy_01"), new("Beach chair", "p9_usa_chair_beach"), new("Surfboard", "p9_usa_surf_longboard_01"),
        new("Arcade game", "p9_nt6_arcade_game"), new("Washing machine", "p9_nt6_machine_washing_dirty"), new("Vintage fridge", "p9_nt6_refrigerator_vintage_closed_02"),
        new("Wooden chair", "p9_nt6_chair_wood"), new("Tire barricade", "p9_nt6_barricade_tire_01"), new("Snowman", "p9_nt6x_win_snowman"),
        new("Arcade cabinet", "p9_mal_arcade_cabinet_08"), new("Kiddie rocket ride", "p9_mal_rocket_ride_01"), new("Scissor lift", "p9_mal_scissor_lift_01"),
        new("Bean bag", "p9_mal_bean_bag_chair_sml"), new("Phone booth", "p9_rus_amk_telephonebooth_01_closed_v2_wet"), new("Long park bench", "p9_rus_bench_park_long"),
        new("Oil drum", "p9_rus_oil_drum_01"), new("Computer server", "p9_rus_computer_server_02"), new("Concrete barrier 144", "p9_ger_kgb_mount_barrier_concrete_144"),
        new("Metal barrel", "p9_ger_tank_barrel_metal_01"), new("Gas pump", "p9_ger_tank_gas_pump_01"), new("Sandbag cover", "p9_lat_sandbag_cover_02_grime"),
        new("Czech hedgehog", "p9_lat_hedgehog_metal_snow"), new("Large ammo crate", "p9_usa_large_ammo_crate_01"), new("Hay bale", "p9_rm_zoo_hay_bale_sqr"),
        new("Wooden spool", "p9_rm_pai_wooden_spool"), new("Water cooler", "p9_rm_rai_water_cooler_metal_full"), new("Palm tree", "p9_foliage_tree_palm_coconut_lrg_01"),
        new("Pot of gold", "p9_pot_of_gold_pristine"), new("Dirty bomb", "p9_wz_dirty_bomb_01"), new("155mm artillery gun", "p9_m114_155mm_artillery_gun_01_pickup"),
        new("Rusted barrel (PH)", "p9_barrel_metal_rusted_01_prophunt"), new("Concrete K-rail (PH)", "p9_krail_concrete_worn_01_prophunt"),
        new("Vase (PH)", "p9_rm_rai_dub_vase_prophunt"), new("Satellite panel (PH)", "p9_ang_satellite_panel_02_prophunt"),
        new("Mattress (PH)", "p9_nt6_abandoned_mattress_01_prophunt"), new("Mannequin M1 (PH)", "p9_nt6_mannequin_clothes_male_01_dirty_full_prophunt"),
        new("Server rack (PH)", "p9_ger_tank_computer_server_diagnostic_01_silver_prophunt"), new("Tank tread rolls (PH)", "p9_ger_tank_tank_tread_rolls_01_prophunt"),
    };

    // veh_master() in gunfight_menu.gsc: the app names a vehicle by its INDEX (an asset name does not fit the slot).
    /// <summary>Mirror of the GSC veh_master() order (vehspawn is BY MASTER INDEX): regenerate from the .gsc whenever a row is added or removed (last sync 2026-09-25 11th pass, 43 rows + each row's maps from docs/data/vehicle-assets.json; null = every map), 51 rows + each row's maps from docs/data/vehicle-assets.json; null = every map).</summary>
    public static readonly VehicleDef[] Vehicles =
    {
        new(0, "Light Buggy (FAV)", 0, new[] { "mp_dune", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes", "wz_zoo" }),
        new(1, "Dirt Bike", 0, new[] { "mp_cartel", "mp_dune", "mp_sm_gas_station", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_zoo" }),
        new(2, "Dirt Bike (Slow)", 0, new[] { "mp_cartel" }),
        new(3, "Quad / ATV", 0, new[] { "mp_dune" }),
        new(4, "Snowmobile", 0, new[] { "mp_tundra", "wz_ski_slopes" }),
        new(5, "Sedan", 0, new[] { "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes", "wz_zoo" }),
        new(6, "Light Truck", 0, new[] { "mp_cartel", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes", "wz_zoo" }),
        new(7, "Cargo Truck", 0, new[] { "mp_dune", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes", "wz_zoo" }),
        new(8, "T-72 Tank", 0, new[] { "mp_tundra", "wz_duga", "wz_forest", "wz_golova", "wz_ski_slopes", "wz_zoo" }),
        new(9, "APC (Heavy)", 0, new[] { "mp_kgb", "mp_sm_gas_station" }),
        new(10, "APC (Heavy, Open Turret)", 0, new[] { "mp_kgb", "mp_sm_gas_station" }),
        new(11, "Mi-24 Hind", 0, new[] { "mp_dune", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes" }),
        new(12, "Wakerunner", 0, new[] { "mp_black_sea", "wz_sanatorium" }),
        new(13, "Tactical Raft", 0, new[] { "mp_black_sea", "mp_miami", "mp_tank", "wz_sanatorium" }),
        new(14, "PBR Gunboat", 0, new[] { "mp_black_sea", "wz_sanatorium" }),
        new(15, "Chopper Gunner", 1),
        new(16, "CH-47 Chinook", 0),
        new(17, "Transport Helicopter", 1),
        new(18, "RC-XD", 1),
        new(19, "RC-XD ALT", 1),
        new(20, "Little Bird Exfil", 1, new[] { "mp_black_sea", "mp_dune", "mp_tundra", "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes", "wz_zoo" }),
        new(21, "AC-130 Gunship", 1),
        new(22, "Attack Helicopter", 1),
        new(23, "Heavy Attack Chopper", 1),
        new(24, "VTOL Escort", 1),
        new(25, "Strafe Run", 1),
        new(26, "Cargo Plane", 1, new[] { "wz_duga", "wz_forest", "wz_golova", "wz_sanatorium", "wz_ski_slopes" }),
        new(27, "Mounted MG Tripod", 1, new[] { "mp_black_sea", "mp_cartel", "mp_tundra" }),
        new(28, "Express Train", 1, new[] { "mp_express_rm" }),
        new(29, "Buggy", 1, new[] { "mp_kgb", "mp_satellite" }),
        new(30, "M1A1 Abrams", 1, new[] { "mp_amerika", "mp_tank" }),
        new(31, "Van", 1, new[] { "mp_miami", "mp_moscow" }),
        new(32, "APC", 1, new[] { "mp_amerika", "mp_mall" }),
        new(33, "Gunship Helicopter", 1, new[] { "mp_cartel" }),
        new(34, "8x8 Truck", 1, new[] { "mp_dune" }),
        new(35, "ATVs", 1, new[] { "mp_dune" }),
        new(36, "ICBM Launcher", 1, new[] { "mp_tundra" }),
        new(37, "Convoy Vehicle", 1, new[] { "mp_tundra" }),
        new(38, "Light Truck, Snow", 1, new[] { "mp_tundra" }),
        new(39, "ICBM Launcher, Snow", 1, new[] { "mp_tundra" }),
        new(40, "Wraith", 1),
        new(41, "Camera Drone", 1),
        new(42, "Little Bird", 1, new[] { "mp_apocalypse", "mp_moscow", "wz_sanatorium" })
    };

    public static readonly Named[] Camos =
    {
        new("Gold", "61"), new("Diamond", "62"), new("DM Ultra", "63"), new("Golden Viper (ZM)", "64"), new("Plague Diamond (ZM)", "65"), new("Dark Aether (ZM)", "66"),
        new("Pack-a-Punch 1", "67"), new("Pack-a-Punch 2", "68"), new("Pack-a-Punch 3", "69"),
        new("PaP Mauer der Toten 1", "116"), new("PaP Mauer der Toten 2", "117"), new("PaP Mauer der Toten 3", "118"),
        new("PaP Forsaken 1", "119"), new("PaP Forsaken 2", "120"), new("PaP Forsaken 3", "121"),
    };

    // setspecialistindex ids: the array index IS the id. Id 0 ("Invisible") is removed from every picker (klaze
    // 2026-09-23 "remove the invisible option from the operators menu") - the entry stays so the ids keep their numbers.
    private static readonly string[] OperatorById =
    {
        "Invisible", "Adler", "Portnova", "Garcia", "Baker", "Sims", "Hunter", "Vargas", "Stone", "Song", "Powers", "Baker (2)", "Zeyna", "Wolf", "Beck", "Knight",
        "Antonov", "Park", "Stitch", "Bulldozer", "CDL 1", "CDL 2", "Woods", "Rivas", "Naga", "Maxis", "John Doe", "Jane Doe", "Base (M)", "Base (F)", "Wraith",
        "Baker (3)", "Park (2)", "Price", "John McClane", "Rambo", "Weaver", "Jackal", "Salah", "Kitsune", "Stryker", "Arthur Kingsley", "Hudson", "Mason", "Scream",
        "Fuze", "Zombie (F)", "Zombie (M)", "Lazar",
    };
    /// <summary>The operator picker: label + setspecialistindex id, id 0 left out.</summary>
    public static readonly Named[] Operators = OperatorById.Select((n, i) => new Named(n, i.ToString())).Skip(1).ToArray();

    // perk_hash() in the GSC: the short keys the panel may send. Effect in MP unmeasured per perk.
    public static readonly PerkDef[] Perks =
    {
        new("fastreload", "Fast reload"), new("fastads", "Fast ADS"), new("fastweaponswitch", "Fast weapon switch"), new("fastmantle", "Fast mantle"),
        new("fastmelee", "Fast melee recovery"), new("fasttoss", "Fast toss"), new("quieter", "Quieter (Ninja)"), new("gpsjammer", "GPS jammer (Ghost)"),
        new("flakjacket", "Flak jacket"), new("stunprotection", "Stun protection"), new("flashprotection", "Flash protection"),
        new("unlimitedsprint", "Unlimited sprint"), new("longersprint", "Longer sprint"), new("movefaster", "Move faster (Lightweight)"),
        new("scavenger", "Scavenger"), new("tracker", "Tracker"), new("bulletflinch", "Less flinch"), new("detectnearby", "Detect nearby enemies"),
        new("showequipment", "Show enemy equipment"), new("immunecuav", "Immune to counter-UAV"), new("fallheight", "No fall damage"),
        new("holdbreath", "Hold breath"), new("twogrenades", "Two grenades"), new("extraammo", "Extra ammo"), new("armorvest", "Armor vest"),
        new("healthregen", "Health regen"), new("sprintfire", "Sprint fire"), new("sprintreload", "Sprint reload"), new("marksman", "Marksman"),
        new("deadshot", "Deadshot"), new("bulletdamage", "Bullet damage"), new("penetration", "Bullet penetration"), new("rof", "Rate of fire"),
        new("lowgravity", "Low gravity (BO3 leftover)", "untested"), new("doublejump", "Double jump (BO3 leftover)", "untested"),
        new("wallrun", "Wallrun (BO3 leftover)", "untested"), new("jetpack", "Jetpack (BO3 leftover)", "untested"),
        new("phdflopper", "PhD Flopper (slide chain 5%)", "the slide-code perk branch, docs/notes/slide.md"), new("staminup", "Stamin-Up (ZM)", "untested"),
    };

    // sound aliases the stock MP scripts play by STRING (the form playsoundtoplayer accepts)
    /// <summary>`streak &lt;kstype&gt;` = killstreaks::give, the full stock set (bocw-1c streak_master, 2026-09-22).</summary>
    public static readonly Named[] Streaks =
    {
        new("RC-XD", "recon_car"), new("UAV", "uav"), new("Counter UAV", "counteruav"), new("H.A.R.P.", "recon_plane"),
        new("Care Package", "supply_drop"), new("Armor", "weapon_armor"), new("Sentry Turret", "ultimate_turret"), new("Missile Turret", "missile_turret"),
        new("Napalm Strike", "napalm_strike"), new("Artillery", "planemortar"), new("Cruise Missile", "remote_missile"), new("Air Patrol", "jetfighter"),
        new("Strafe Run", "straferun"), new("Attack Helicopter", "helicopter_comlink"), new("VTOL Escort", "hoverjet"), new("Chopper Gunner", "chopper_gunner"),
        new("Gunship", "ac130"), new("War Machine", "hero_pineapplegun"), new("Hand Cannon", "hero_annihilator"), new("Death Machine", "sig_lmg"),
        new("Flamethrower", "hero_flamethrower"), new("Sparrow (bow)", "sig_bow_flame"), new("Nuke", "nuke"),   // ray_gun: killstreaks::give refused it (removed 2026-09-22)
    };

    // The fun pack's picks travel as INDICES (`fun nadeswapw 3`): a model or weapon name would overflow the 47-byte
    // bridge slot. Order = gunfight_menu.gsc fun_nade_pick / fun_cannon_pick / fun_disg_pick - GfPanel.Tests checks it.
    public static readonly Named[] FunNades =
    {
        new("Molotov", "0"), new("Semtex", "1"), new("Frag", "2"), new("C4", "3"), new("Stun", "4"), new("Flash", "5"),
        new("Smoke", "6"), new("Hatchet", "7"), new("M79 grenade", "8"), new("War Machine grenade", "9"), new("Monkey bomb (Zombies item - may do nothing)", "10"),
    };

    public static readonly Named[] FunCannonModels =
    {
        new("Your forge pick", "0"), new("Chickens", "1"), new("Oil drums", "2"), new("Couches", "3"), new("Mannequins", "4"), new("Energy portals", "5"),
    };

    public static readonly Named[] FunDisguises =
    {
        new("Chicken", "0"), new("Mannequin", "1"), new("Couch", "2"), new("Oil drum", "3"), new("Dog tags", "4"), new("Energy portal", "5"),
    };

    public static readonly Named[] Sounds =
    {
        new("Timer beep", "uin_timer_5"), new("Action denied", "uin_default_action_denied"), new("Kill confirmed tags", "mpl_killconfirm_tags_pickup"),
        new("Flash grenade", "wpn_flash_grenade_explode"), new("Bomb defused", "mpl_sd_bomb_defuse"), new("Zone contested", "mpl_control_capture_contested"),
        new("Annihilation", "evt_annihilation_plr"), new("Turret alert", "mpl_turret_alert"), new("Prop Hunt whistle", "mpl_phunt_char_whistle"),
        new("Hardpoint contested", "mpl_zone_contested"), new("Prop Hunt ready", "uin_ph_ready"), new("Killstreak generic", "uin_kls_generic"),
        new("Bomb raise", "fly_bomb_raise_plr"),
    };

    public static readonly Named[] Visions =
    {
        new("Default (map's own)", "default"), new("MP outro (stock end-of-match look)", "mpOutro"),
    };

    public static readonly ColorDef[] Colors =
    {
        new("^0", "black", "#0a0a0a"), new("^1", "red", "#ff3b3b"), new("^2", "green", "#46d246"), new("^3", "yellow", "#ffd21e"), new("^4", "blue", "#5478ff"),
        new("^5", "cyan", "#46d2ff"), new("^6", "magenta", "#ff5cff"), new("^7", "white", "#ffffff"), new("^8", "grey (team)", "#9a9a9a"), new("^9", "grey", "#7a7a7a"),
    };

    // the built-in composer presets: each fits ONE say line (Commands.MaxSayChars, 30) - a longer one was cut mid-sentence in game
    public static readonly Named[] MessagePresets =
    {
        new("Welcome - custom Gunfight", "Welcome to custom Gunfight!"), new("Starting soon", "Starting soon - get ready"),
        new("Map switch next round", "Map switch next round - stay!"), new("Sides switch next round", "Sides switch next round"),
        new("Bots joining", "Bots joining to fill the teams"), new("Custom rules on", "Custom rules ON - ask the host"),
        new("Do not leave", "Do not leave - wait for host"), new("GG - lobby after this", "GG! Lobby after this one"),
        new("One more round", "One more round!"), new("gunfight.us", "Visit us at ^5gunfight.us"), new("Discord", "Join ^5discord.gg/blackops"),
    };
}
