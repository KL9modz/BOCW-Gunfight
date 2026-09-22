using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The prop browser (docs/notes/prop-catalog.md): the WHOLE catalog lives here - 546 universal props by
/// index plus the current map's own list by name - with explosive-barrel spawns and the favourites the in-game
/// menu's Props page shows.</summary>
public sealed class PropsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public PropCatalog Catalog { get; } = new();
    public ObservableCollection<PropEntry> Results { get; } = new();
    public ObservableCollection<PropEntry> Favorites { get; } = new();
    public string LoadNote => Catalog.LoadNote;

    private bool _universal = true;
    public bool ShowUniversal { get => _universal; set { if (Set(ref _universal, value)) { OnPropertyChanged(nameof(ShowMap)); Refilter(); } } }
    public bool ShowMap { get => !_universal; set => ShowUniversal = !value; }
    private bool _barrelsOnly;
    public bool BarrelsOnly { get => _barrelsOnly; set { if (Set(ref _barrelsOnly, value)) Refilter(); } }
    private string _search = "";
    public string Search { get => _search; set { if (Set(ref _search, value)) Refilter(); } }
    private PropEntry? _selected;
    public PropEntry? Selected { get => _selected; set { if (Set(ref _selected, value)) OnPropertyChanged(nameof(SelectedIsFav)); } }
    private int _scale = 100;
    // no clamp in the setter: the box updates per keystroke, and a clamp there rewrites "1" of "150" to "10"
    // under the cursor (klaze: "prop scale input is glitchy"); the range applies when the value is used
    public int Scale { get => _scale; set => Set(ref _scale, value); }
    public int ScaleClamped => Math.Clamp(Scale, 10, 1000);
    private string _mapLabel = "";
    public string MapLabel { get => _mapLabel; set => Set(ref _mapLabel, value); }
    private string _countText = "";
    public string CountText { get => _countText; set => Set(ref _countText, value); }
    public bool SelectedIsFav => Selected is { IsUniversal: true } s && _m.Prefs.PropFavorites.Contains(s.Index);
    public int MaxResults { get; } = 400;

    public PropsVM(MainViewModel m)
    {
        _m = m;
        MigrateFavorites();
        RebuildFavorites();
        Refilter();
    }

    /// <summary>Favourites survive a catalog renumbering: names are the truth, indices are derived.</summary>
    private void MigrateFavorites()
    {
        var p = _m.Prefs;
        var byModel = new Dictionary<string, int>();
        foreach (var u in Catalog.Universal) byModel.TryAdd(u.Model, u.Index);
        // prefs written before this field existed carry indices against the 546-entry catalog of 2026-09-20
        if (p.PropCatalogCount == 0 && p.PropFavoriteModels.Count == 0 && p.PropFavorites.Count > 0) p.PropCatalogCount = 546;
        if (p.PropFavoriteModels.Count == 0 && p.PropFavorites.Count > 0 && p.PropCatalogCount == Catalog.Universal.Count)
            p.PropFavoriteModels = p.PropFavorites.Select(i => Catalog.Universal.FirstOrDefault(u => u.Index == i)?.Model).Where(m => m != null).Select(m => m!).ToList();
        if (p.PropFavoriteModels.Count > 0)
        {
            var before = p.PropFavorites.Count;
            p.PropFavorites = p.PropFavoriteModels.Where(byModel.ContainsKey).Select(m => byModel[m]).Distinct().ToList();
            if (p.PropCatalogCount != 0 && p.PropCatalogCount != Catalog.Universal.Count)
                _m.Link.Log($"prop catalog changed ({p.PropCatalogCount} -> {Catalog.Universal.Count} universal): {p.PropFavorites.Count}/{before} favourites re-resolved by model name", LogLevel.Warn);
        }
        else if (p.PropCatalogCount != 0 && p.PropCatalogCount != Catalog.Universal.Count && p.PropFavorites.Count > 0)
        {
            _m.Link.Log("prop catalog renumbered and the favourites had no model names - cleared, re-pick them", LogLevel.Warn);
            p.PropFavorites.Clear();
        }
        p.PropCatalogCount = Catalog.Universal.Count;
        p.Save();
    }

    private void SyncFavoriteModels()
    {
        _m.Prefs.PropFavoriteModels = _m.Prefs.PropFavorites.Select(i => Catalog.Universal.FirstOrDefault(u => u.Index == i)?.Model).Where(m => m != null).Select(m => m!).ToList();
    }

    private string CurrentMap => _m.Link.State?.Map ?? "";

    public void OnState() { var lbl = CurrentMap.Length > 0 ? Game.Catalog.MapName(CurrentMap) : "(no match)"; if (lbl != MapLabel) { MapLabel = lbl; if (!ShowUniversal) Refilter(); } }

    private void Refilter()
    {
        Results.Clear();
        IEnumerable<PropEntry> src = ShowUniversal ? Catalog.Universal : (Catalog.Maps.TryGetValue(CurrentMap, out var l) ? l : Enumerable.Empty<PropEntry>());
        var total = src.Count();
        if (BarrelsOnly) src = src.Where(p => p.Barrel);
        var terms = Search.Trim().ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (terms.Length > 0) src = src.Where(p => terms.All(t => p.Model.Contains(t) || p.Label.ToLowerInvariant().Contains(t)));
        var list = src.Take(MaxResults).ToList();
        foreach (var p in list) Results.Add(p);
        CountText = ShowUniversal ? $"{list.Count} of {total} universal" : CurrentMap.Length == 0 ? "no match running - the per-map list needs the live map" : $"{list.Count} of {total} on {MapLabel}";
        if (Selected == null || !Results.Contains(Selected)) Selected = Results.FirstOrDefault();
    }

    private void RebuildFavorites()
    {
        Favorites.Clear();
        foreach (var i in _m.Prefs.PropFavorites.Distinct().OrderBy(i => i))
        {
            var e = Catalog.Universal.FirstOrDefault(u => u.Index == i);
            if (e != null) Favorites.Add(e);
        }
        OnPropertyChanged(nameof(SelectedIsFav));
        OnPropertyChanged(nameof(FavText));
    }
    public string FavText => $"{Favorites.Count} favourite(s) · pushed as gf_prop_favs (fits ~14 indices)";

    public RelayCommand SpawnProp => new(() => Spawn(false));
    public RelayCommand SpawnBarrel => new(() => Spawn(true));
    private void Spawn(bool barrel)
    {
        var p = Selected;
        if (p == null) { _m.Toasts.Show("Pick a prop first", LogLevel.Warn); return; }
        var verb = barrel ? "barrel" : "prop";
        if (p.IsUniversal)
            _m.Link.Send($"{verb} {p.Label} (#{p.Index})", Commands.Action(barrel ? "barrelidx" : "propidx", p.Index.ToString()));
        else
        {
            var lines = PropCatalog.ByNameLines(p.Model, ScaleClamped, barrel);
            if (lines == null) { _m.Toasts.Show("Model name too long for the bridge (max 108 chars)", LogLevel.Err); return; }
            _m.Link.Send($"{verb} {p.Label} x{ScaleClamped / 100.0:0.##}", lines);
        }
    }
    public RelayCommand Undo => new(() => _m.Link.Send("Remove last prop", Commands.Action("propundo")));
    public RelayCommand Clear => new(() => _m.Link.Send("Remove all props", Commands.Action("propclear")));
    public RelayCommand ToggleFav => new(() =>
    {
        if (Selected is not { IsUniversal: true } s) { _m.Toasts.Show("Only universal props (present on every map) can be menu favourites", LogLevel.Warn); return; }
        if (_m.Prefs.PropFavorites.Contains(s.Index)) _m.Prefs.PropFavorites.Remove(s.Index); else _m.Prefs.PropFavorites.Add(s.Index);
        SyncFavoriteModels(); _m.Prefs.Save(); RebuildFavorites();
    });
    public RelayCommand RemoveFav => new(p => { if (p is PropEntry e) { _m.Prefs.PropFavorites.Remove(e.Index); SyncFavoriteModels(); _m.Prefs.Save(); RebuildFavorites(); } });
    public RelayCommand PushFavs => new(() =>
    {
        var (lines, dropped) = PropCatalog.FavLines(_m.Prefs.PropFavorites);
        lines.AddRange(Commands.Action("propfavs"));
        _m.Link.Send($"push {Favorites.Count - dropped.Count} prop favourites to the menu", lines);
        if (dropped.Count > 0) _m.Toasts.Show($"{dropped.Count} favourite(s) did not fit the two favs dvars and were left out: #{string.Join(" #", dropped)}", LogLevel.Warn);
    });
    public RelayCommand SpawnFav => new(p => { if (p is PropEntry e) { Selected = e; Spawn(e.Barrel); } });
}
