using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>Every action page of the in-game menu (Player / Weapons / Camo / Operator / Outfit / Teleport /
/// Vehicles / Destructibles / Projectiles / Props / Race) plus the rcon-style everyone-state and fun toys
/// the GSC increment added. Each button = one acked bridge command.</summary>
public sealed class ToolsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public ToolsVM(MainViewModel m)
    {
        _m = m;
        WeaponGroups = Catalog.Weapons.Select(g => new WeaponGroupVM(g.Group, g.Items)).ToList();
        SelectedWeapon = WeaponList[0];
        SelectedProjectile = Catalog.Projectiles[0];
        SelectedProp = Catalog.Props[0];
        SelectedVehicle = Catalog.Vehicles.First(v => v.Index == 3);
        SelectedOtherVehicle = Catalog.Vehicles.First(v => v.Kind == 1);
        SelectedSound = Catalog.Sounds[0];
        SelectedVision = Catalog.Visions[0];
        SelectedPerk = Catalog.Perks[0];
        foreach (var p in Catalog.Perks) Perks.Add(new PerkRowVM(this, p));
    }

    private void Do(string label, string action, string? arg = null, string? target = null) => _m.Link.Send(label, Commands.Action(action, arg, target));

    // ── host tools ──
    public RelayCommand Fly => new(() => Do("Fly (host)", "fly"));
    public RelayCommand GodMode => new(() => Do("God mode (host)", "godmode"));
    public RelayCommand ThirdPerson => new(() => Do("Third person (host)", "thirdperson"));
    public RelayCommand MaxAmmo => new(() => Do("Max ammo (host)", "maxammo"));
    public RelayCommand DropWeapon => new(() => Do("Drop weapon", "dropweapon"));
    public RelayCommand UnlockAll => new(() => Do("Unlock all", "unlockall"));
    public RelayCommand FreezeToggle => new(() => Do("Freeze everyone (toggle)", "freeze"));

    // ── everyone-state (the rcon PLAYER STATE block) ──
    public RelayCommand GodAllOn => new(() => Do("God mode ALL on", "godall", "on"));
    public RelayCommand GodAllOff => new(() => Do("God mode ALL off", "godall", "off"));
    public RelayCommand AmmoAll => new(() => Do("Max ammo ALL", "ammoall"));
    public RelayCommand ThirdAllOn => new(() => Do("Third person ALL on", "thirdall", "on"));
    public RelayCommand ThirdAllOff => new(() => Do("Third person ALL off", "thirdall", "off"));
    public RelayCommand FreezeAllOn => new(() => Do("Freeze ALL", "freezeall", "on"));
    public RelayCommand FreezeAllOff => new(() => Do("Unfreeze ALL", "freezeall", "off"));
    public RelayCommand InvisOn => new(() => Do("Invisible players on", "invisall", "on"));
    public RelayCommand InvisOff => new(() => Do("Invisible players off", "invisall", "off"));
    public RelayCommand DrunkOn => new(() => Do("Drunk mode on", "drunk", "on"));
    public RelayCommand DrunkOff => new(() => Do("Drunk mode off", "drunk", "off"));
    public RelayCommand Quake => new(() => Do("Earthquake", "quake"));
    public RelayCommand PlaySound => new(() => Do("Sound " + SelectedSound.Label, "sound", SelectedSound.Value));
    public RelayCommand VisionApply => new(() => Do("Vision " + VisionName, "vision", VisionName));
    public RelayCommand VisionDefault => new(() => Do("Vision default", "vision", "default"));
    public RelayCommand PerksClear => new(() => { foreach (var p in Perks) p.SetSilently(false); Do("Perks ALL clear", "perkall", "clear"); });
    // ONE command (perkall all - GSC perk_keys()); 39 single toggles would take ~30 s through the paced bridge
    public RelayCommand PerksAll => new(() => { foreach (var p in Perks) p.SetSilently(true); Do("Perks ALL - every perk", "perkall", "all"); });
    public RelayCommand SlowmoApply => new(() => { var t = Math.Clamp(Timescale, 10, 300); Timescale = t; Do($"Timescale {t}%", "slowmo", t.ToString()); });
    public RelayCommand SlowmoReset => new(() => { Timescale = 100; Do("Timescale 100%", "slowmo", "100"); });

    private int _timescale = 100;
    public int Timescale { get => _timescale; set => Set(ref _timescale, value); }   // clamped where used (typing-safe)
    public Named SelectedSound { get; set; }
    public Named SelectedVision { get => _vision; set { _vision = value; VisionName = value.Value; OnPropertyChanged(); } }
    private Named _vision = Catalog.Visions[0];
    private string _visionName = "default";
    public string VisionName { get => _visionName; set => Set(ref _visionName, value); }
    public ObservableCollection<PerkRowVM> Perks { get; } = new();
    public PerkDef? SelectedPerk { get; set; }
    internal void PerkToggled(PerkRowVM p) => Do((p.IsOn ? "Perk ALL +" : "Perk ALL -") + p.Key, "perkall", (p.IsOn ? "" : "-") + p.Key);

    public Named[] VisionSets => Catalog.Visions;
    public Named[] SoundList => Catalog.Sounds;
    public Named[] ProjectileList => Catalog.Projectiles;
    public Named[] PropList => Catalog.Props;
    public int[] ProjMethods => new[] { 0, 1, 2, 3, 4, 5, 6 };   // 0 = AUTO (bocw-c7, the GSC default since 2026-09-20)
    private int _projMethod = 0;
    public int ProjMethod { get => _projMethod; set => Set(ref _projMethod, value); }
    public RelayCommand ProjMethodSet => new(() => Do($"Projectile method {ProjMethod}", "projmethod", ProjMethod.ToString()));
    public RelayCommand ProjDebug => new(() => Do("PROJ debug line", "projdbg"));

    // ── weapons ──
    public List<WeaponGroupVM> WeaponGroups { get; }
    /// <summary>Every weapon, flat, labelled "group › name" for one long picker.</summary>
    public Named[] WeaponList { get; } = Catalog.Weapons.SelectMany(g => g.Items.Select(i => new Named(g.Group + " › " + i.Label, i.Value, i.Note))).ToArray();
    private Named _weapon = null!;
    public Named SelectedWeapon { get => _weapon; set => Set(ref _weapon, value); }
    public RelayCommand GiveHost => new(() => Do("Give " + SelectedWeapon.Label, "giveweapon", SelectedWeapon.Value));
    public RelayCommand GiveAll => new(() => Do("Give ALL " + SelectedWeapon.Label, "giveall", SelectedWeapon.Value));
    public void GiveTo(string name) => Do("Give " + SelectedWeapon.Label, "giveone", SelectedWeapon.Value, name);

    // ── cosmetics ──
    private int _camo = 61, _op = 1, _outfit;
    public int CamoId { get => _camo; set => Set(ref _camo, value); }          // ranges applied on use, not per keystroke
    public int OperatorId { get => _op; set => Set(ref _op, value); }
    public int OutfitId { get => _outfit; set => Set(ref _outfit, value); }
    public Named[] CamoNames => Catalog.Camos;
    public string[] OperatorNames => Catalog.Operators;
    public Named? SelectedCamo { get => null; set { if (value != null) CamoId = int.Parse(value.Value); } }
    public string? SelectedOperator { get => null; set { if (value != null) OperatorId = Array.IndexOf(Catalog.Operators, value); } }
    public RelayCommand CamoHost => new(() => { CamoId = Math.Clamp(CamoId, 0, 149); Do("Camo " + CamoId, "camo", CamoId.ToString()); });
    public RelayCommand OperatorHost => new(() => { OperatorId = Math.Clamp(OperatorId, 0, 60); Do("Operator " + OperatorId, "operator", OperatorId.ToString()); });
    public RelayCommand OutfitHost => new(() => { OutfitId = Math.Clamp(OutfitId, 0, 60); Do("Outfit " + OutfitId, "outfit", OutfitId.ToString()); });

    // ── teleport hub ──
    public RelayCommand TpAllMe => new(() => Do("Everyone to me", "tpall", "me"));
    public RelayCommand TpAllAim => new(() => Do("Everyone to crosshair", "tpall", "aim"));
    public RelayCommand TpAllSaved => new(() => Do("Everyone to saved point", "tpall", "saved"));
    public RelayCommand TpAllCentre => new(() => Do("Everyone to map centre", "tpall", "centre"));
    public RelayCommand TpTeamMe => new(() => Do("My team to me", "tpteam", "me"));
    public RelayCommand TpTeamAim => new(() => Do("My team to crosshair", "tpteam", "aim"));
    public RelayCommand TpEnemyMe => new(() => Do("Other team to me", "tpenemy", "me"));
    public RelayCommand TpEnemyAim => new(() => Do("Other team to crosshair", "tpenemy", "aim"));
    public RelayCommand TpMeAim => new(() => Do("Me to crosshair", "tpme", "aim"));
    public RelayCommand TpMeSaved => new(() => Do("Me to saved point", "tpme", "saved"));
    public RelayCommand TpMeCentre => new(() => Do("Me to map centre", "tpme", "centre"));
    public RelayCommand TpSave => new(() => Do("Save point", "tpsave"));
    public RelayCommand TpGunHost => new(() => Do("Teleport gun (host)", "tpgun", "host"));
    public RelayCommand TpGunAll => new(() => Do("Teleport gun (everyone)", "tpgun", "all"));
    public RelayCommand TpNadeHost => new(() => Do("Teleport grenade (host)", "tpnade", "host"));
    public RelayCommand TpNadeAll => new(() => Do("Teleport grenade (everyone)", "tpnade", "all"));

    // ── vehicles ──
    public VehicleDef[] DrivableVehicles => Catalog.Vehicles.Where(v => v.Drivable).ToArray();
    public VehicleDef[] OtherVehicles => Catalog.Vehicles.Where(v => !v.Drivable).ToArray();
    private VehicleDef _veh = null!, _vehOther = null!;
    public VehicleDef SelectedVehicle { get => _veh; set => Set(ref _veh, value); }
    public VehicleDef SelectedOtherVehicle { get => _vehOther; set => Set(ref _vehOther, value); }
    public RelayCommand VehSpawn => new(() => Do("Spawn " + SelectedVehicle.Label, "vehspawn", SelectedVehicle.Index.ToString()));
    public RelayCommand VehSpawnOther => new(() => Do("Spawn " + SelectedOtherVehicle.Label, "vehspawn", SelectedOtherVehicle.Index.ToString()));
    public RelayCommand VehEnter => new(() => Do("Enter aimed vehicle", "vehenter"));
    public RelayCommand VehClear => new(() => Do("Remove spawned vehicles", "vehclear"));
    public string VehicleNote => _m.Link.State is { } s && _m.Link.MapVeh.TryGetValue(s.Map, out var d)
        ? "resident here: " + string.Join(", ", d.VehiclesDrive) : "spawns ahead of you (aircraft above); a class this map lacks just says so";

    // ── map toys ──
    public RelayCommand DestructAim => new(() => Do("Break aimed", "destruct", "aim"));
    public RelayCommand DestructNear => new(() => Do("Break near me", "destruct", "near"));
    public RelayCommand DestructAll => new(() => { if (_m.Confirm("Break EVERY destructible on the map?")) Do("Break ALL", "destruct", "all"); });
    public RelayCommand ExpNext => new(() => Do("Exploder next", "exploder", "next"));
    public RelayCommand ExpPrev => new(() => Do("Exploder previous", "exploder", "prev"));
    public RelayCommand ExpAgain => new(() => Do("Exploder again", "exploder", "again"));
    public RelayCommand ExpStop => new(() => Do("Exploder stop", "exploder", "stop"));
    public RelayCommand ExpAll => new(() => Do("Exploders ALL", "exploder", "all"));
    public RelayCommand ExpStopAll => new(() => Do("Exploder walk stop", "exploder", "stopall"));
    public RelayCommand ProjHost => new(() => Do("Projectiles: host", "proj", "host"));
    public RelayCommand ProjAll => new(() => Do("Projectiles: everyone", "proj", "all"));
    public RelayCommand ProjOff => new(() => Do("Projectiles off", "proj", "off"));
    public RelayCommand ProjHoming => new(() => Do("Projectiles homing", "projhoming"));
    public RelayCommand ProjTrail => new(() => Do("Projectiles trail FX", "projtrail"));
    private Named _proj = null!;
    public Named SelectedProjectile { get => _proj; set => Set(ref _proj, value); }
    public RelayCommand ProjWeapon => new(() => Do("Projectile " + SelectedProjectile.Label, "projweapon", SelectedProjectile.Value));
    public int[] ProjRates => new[] { 0, 150, 300, 600, 1000 };
    private int _projRate = 300;
    public int ProjRate { get => _projRate; set => Set(ref _projRate, value); }
    public RelayCommand ProjRateSet => new(() => Do($"Projectile rate {ProjRate} ms", "projrate", ProjRate.ToString()));
    private Named _prop = null!;
    public Named SelectedProp { get => _prop; set => Set(ref _prop, value); }
    public RelayCommand PropPlace => new(() => Do("Place " + SelectedProp.Label, "prop", "\"" + SelectedProp.Label + "\""));
    public RelayCommand PropUndo => new(() => Do("Remove last prop", "propundo"));
    public RelayCommand PropClear => new(() => Do("Remove all props", "propclear"));

    // ── race ──
    public RelayCommand RaceStart => new(() => Do("START RACE", "race", "start"));
    public RelayCommand RaceStop => new(() => Do("Stop race", "race", "stop"));
    public RelayCommand RaceGate => new(() => Do("Gate here", "race", "gate"));
    public RelayCommand RaceUndo => new(() => Do("Undo last gate", "race", "undo"));
    public RelayCommand RaceClear => new(() => Do("Clear track", "race", "clear"));
    public RelayCommand RaceLoad => new(() => Do("Load saved track (game)", "race", "load"));
    public RelayCommand RaceMarkers => new(() => Do("Gate markers show/hide", "race", "markers"));
    public RelayCommand RaceResetMe => new(() => Do("Reset me", "race", "resetme"));
    public RelayCommand RaceEndMatch => new(() => { if (_m.Confirm("End the match now with the race standings?")) Do("END MATCH (podium)", "race", "endmatch"); });
    public ObservableCollection<string> SavedTracks { get; } = new();
    private string _trackName = "track 1";
    public string TrackName { get => _trackName; set => Set(ref _trackName, value); }
    private string? _selectedTrack;
    public string? SelectedTrack { get => _selectedTrack; set => Set(ref _selectedTrack, value); }
    public RelayCommand TrackSave => new(() => _m.Tracks.SaveFromGame(TrackName));
    public RelayCommand TrackLoad => new(() => { if (SelectedTrack != null) _m.Tracks.LoadIntoGame(SelectedTrack); });
    public RelayCommand TrackDelete => new(() => { if (SelectedTrack != null) _m.Tracks.Delete(SelectedTrack); });
}

public sealed class WeaponGroupVM
{
    public string Group { get; }
    public Named[] Items { get; }
    public WeaponGroupVM(string g, Named[] items) { Group = g; Items = items; }
}

public sealed class PerkRowVM : ObservableObject
{
    private readonly ToolsVM _tools;
    public PerkDef Def { get; }
    public string Key => Def.Key;
    public string Label => Def.Label;
    public string Note => Def.Note;
    private bool _on;
    public bool IsOn { get => _on; set { if (Set(ref _on, value)) _tools.PerkToggled(this); } }
    public PerkRowVM(ToolsVM t, PerkDef d) { _tools = t; Def = d; }
    public void SetSilently(bool on) { _on = on; OnPropertyChanged(nameof(IsOn)); }
}
