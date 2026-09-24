using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>One spawned entity in the ENTITIES tab.</summary>
public sealed class EntityRowVM
{
    private readonly EntitiesVM _vm;
    public GfEntity E { get; }
    public string Icon => E.Icon;
    public string Label => E.Label;
    public string KindText => E.KindText;
    public string Owner => E.OwnerText;
    public string Dist => E.DistText;
    public int EntNum => E.EntNum;
    public string Status => E.Status;
    public bool Occupied => E.Occupied;
    public string Where => $"{E.X}, {E.Y}, {E.Z}";
    public EntityRowVM(EntitiesVM vm, GfEntity e) { _vm = vm; E = e; }
    public RelayCommand Delete => new(() => _vm.DeleteOne(this));
}

/// <summary>klaze 2026-09-23: "app needs an asset/prop/vehicle list viewer so i can delete spawned entities in lobby.
/// also add buttons to delete all." The GFENTS channel (gunfight_menu.gsc ents_publish): every prop, explosive barrel
/// and vehicle the mod spawned that is still in the level, with who placed it and how far it is from the host.
/// Delete = entdel &lt;entnum&gt; (the GSC re-checks it is one of ours and never deletes an occupied vehicle);
/// delete-all = entclear props | vehicles | all.</summary>
public sealed class EntitiesVM : ObservableObject
{
    private readonly MainViewModel _m;
    private List<EntityRowVM> _all = new();
    public ObservableCollection<EntityRowVM> Rows { get; } = new();

    public EntitiesVM(MainViewModel m)
    {
        _m = m;
        _m.Link.EntitiesReceived += OnEntities;
    }

    private bool _active;
    /// <summary>The ENTITIES tab is showing: the link collects the list whenever the game republishes it.</summary>
    public bool IsActive
    {
        get => _active;
        set
        {
            if (!Set(ref _active, value)) return;
            _m.Link.WantEntities = value;
            if (value) _m.Link.RequestEntities();
        }
    }

    private string _filter = "all";
    public bool ShowAll { get => _filter == "all"; set { if (value) SetFilter("all"); } }
    public bool ShowProps { get => _filter == "props"; set { if (value) SetFilter("props"); } }
    public bool ShowVehicles { get => _filter == "vehicles"; set { if (value) SetFilter("vehicles"); } }
    private void SetFilter(string f)
    {
        _filter = f;
        OnPropertyChanged(nameof(ShowAll)); OnPropertyChanged(nameof(ShowProps)); OnPropertyChanged(nameof(ShowVehicles));
        Rebuild();
    }

    private string _summary = "Open this tab while a match runs - the list comes from the game (needs the 2026-09-23 build or newer).";
    public string Summary { get => _summary; set => Set(ref _summary, value); }
    private string _updated = "";
    public string Updated { get => _updated; set => Set(ref _updated, value); }
    public bool Any => Rows.Count > 0;

    private void OnEntities(long stamp, List<GfEntity> items)
    {
        _all = items.OrderBy(e => e.IsVehicle ? 0 : 1).ThenBy(e => e.Dist < 0 ? int.MaxValue : e.Dist).Select(e => new EntityRowVM(this, e)).ToList();
        Updated = "updated " + DateTime.Now.ToString("HH:mm:ss");
        Rebuild();
    }

    /// <summary>--dry --fake only.</summary>
    public void LoadFake(List<GfEntity> items) => OnEntities(0, items);

    public void Clear()
    {
        _all.Clear();
        Updated = "";
        Rebuild();
    }

    private void Rebuild()
    {
        Rows.Clear();
        foreach (var r in _all.Where(r => _filter == "all" || (_filter == "props" ? r.E.IsProp : r.E.IsVehicle))) Rows.Add(r);
        var props = _all.Count(r => r.E.IsProp);
        var vehs = _all.Count(r => r.E.IsVehicle);
        Summary = _all.Count == 0 ? "Nothing spawned right now." : $"{_all.Count} spawned · {props} prop{(props == 1 ? "" : "s")} / barrel{(props == 1 ? "" : "s")} · {vehs} vehicle{(vehs == 1 ? "" : "s")}";
        OnPropertyChanged(nameof(Any));
    }

    public void DeleteOne(EntityRowVM row)
    {
        if (row.Occupied) { _m.Toasts.Show($"{row.Label} is occupied - it is never deleted with someone inside", LogLevel.Warn); return; }
        _m.Link.Send($"Delete {row.Label} (#{row.EntNum})", Commands.Action("entdel", row.EntNum.ToString()));
        _all.Remove(row);           // optimistic; the next list from the game is the truth
        Rebuild();
    }

    public RelayCommand Refresh => new(() => { _m.Link.RequestEntities(); _m.Toasts.Show("Reading the entity list from the game", LogLevel.Info); });
    public RelayCommand DeleteAllProps => new(() =>
    {
        if (_m.Confirm("Delete ALL props and barrels?\n\nThe saved forge layout for this map goes too, so they do not come back next round."))
            _m.Link.Send("Delete all props", Commands.Action("entclear", "props"));
    });
    public RelayCommand DeleteAllVehicles => new(() =>
    {
        if (_m.Confirm("Delete ALL spawned vehicles?\n\nEvery empty vehicle the menu / app / vehicle mode spawned. An occupied one is kept."))
            _m.Link.Send("Delete all vehicles", Commands.Action("entclear", "vehicles"));
    });
    public RelayCommand DeleteEverything => new(() =>
    {
        if (_m.Confirm("Delete EVERYTHING spawned?\n\nAll props + barrels (and the saved layout) and every empty spawned vehicle."))
            _m.Link.Send("Delete all spawned entities", Commands.Action("entclear", "all"));
    });
}
