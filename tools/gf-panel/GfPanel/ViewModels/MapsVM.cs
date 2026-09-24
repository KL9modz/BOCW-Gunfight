using System.Collections.ObjectModel;
using GfPanel.Game;
using GfPanel.Services;

namespace GfPanel.ViewModels;

public sealed class MapTileVM : ObservableObject
{
    public MapDef Def { get; }
    public string Name => Def.Name;
    public string Id => Def.Id;
    public string Group => Def.Group;
    public string Note => Def.Note;
    private bool _live;
    public bool IsLive { get => _live; set => Set(ref _live, value); }
    private bool _staged;
    public bool IsStaged { get => _staged; set => Set(ref _staged, value); }
    private bool _selected;
    public bool IsSelected { get => _selected; set => Set(ref _selected, value); }
    public MapTileVM(MapDef d) { Def = d; }
}

public sealed class PlaylistRowVM : ObservableObject
{
    public PlaylistEntry Entry { get; }
    public string Map => Catalog.MapName(Entry.Map) + "  [" + Entry.Map + "]";
    public string Gametype => Entry.Gametype;
    private bool _next;
    public bool IsNext { get => _next; set => Set(ref _next, value); }
    public PlaylistRowVM(PlaylistEntry e) { Entry = e; }
}

/// <summary>The MAPS tab: the session switch (Stage for lobby / Switch NOW) and the private-match rotation
/// (a playlist the panel stages at every match end - the rcon MAP ROTATION, done app-side).</summary>
public sealed class MapsVM : ObservableObject
{
    private readonly MainViewModel _m;
    public ObservableCollection<MapTileVM> Tiles { get; } = new();
    public IEnumerable<MapTileVM> Maps6v6 => Tiles.Where(t => t.Group == "6v6");
    public IEnumerable<MapTileVM> MapsGf => Tiles.Where(t => t.Group == "Gunfight");
    public IEnumerable<MapTileVM> Maps12 => Tiles.Where(t => t.Group == "12v12");
    public IEnumerable<MapTileVM> MapsFt => Tiles.Where(t => t.Group == "Fireteam");
    public Named[] Gametypes => Catalog.Gametypes;
    private Named _gt;
    public Named Gametype { get => _gt; set => Set(ref _gt, value); }
    private MapTileVM? _sel;
    public MapTileVM? Selected
    {
        get => _sel;
        set
        {
            if (_sel != null) _sel.IsSelected = false;
            Set(ref _sel, value);
            if (_sel != null) { _sel.IsSelected = true; if (_sel.Def.Gametype != null) Gametype = Gametypes.First(g => g.Value == _sel.Def.Gametype); }
            OnPropertyChanged(nameof(SelectionText));
        }
    }
    public string SelectionText => Selected == null ? "(keep the current map)" : Selected.Def.Label;
    public ObservableCollection<PlaylistRowVM> Playlist { get; } = new();
    private bool _plEnabled;
    public bool PlaylistEnabled { get => _plEnabled; set { if (Set(ref _plEnabled, value)) { _m.Prefs.PlaylistEnabled = value; _m.Prefs.Save(); MarkNext(); } } }
    private string _plStatus = "";
    public string PlaylistStatus { get => _plStatus; set => Set(ref _plStatus, value); }
    public string StagedText => _m.Link.State is { StagedMap.Length: > 0 } s ? $"staged: {Catalog.MapName(s.StagedMap)} / {s.StagedGametype}" : "";

    public MapsVM(MainViewModel m)
    {
        _m = m;
        _gt = Gametypes[0];
        foreach (var d in Catalog.Maps) Tiles.Add(new MapTileVM(d));
        foreach (var e in m.Prefs.Playlist) Playlist.Add(new PlaylistRowVM(e));
        _plEnabled = m.Prefs.PlaylistEnabled;
        MarkNext();
    }

    public void OnState(GfState? s)
    {
        foreach (var t in Tiles)
        {
            t.IsLive = s != null && t.Id == s.Map && t.Def.Gametype == null;
            t.IsStaged = s != null && s.StagedMap.Length > 0 && t.Id == s.StagedMap && t.Def.Gametype == null;
        }
        OnPropertyChanged(nameof(StagedText));
    }

    public RelayCommand Select => new(p => { if (p is MapTileVM t) Selected = t == Selected ? null : t; });
    public RelayCommand ClearSelection => new(() => Selected = null);
    public RelayCommand Stage => new(() => Switch(true));
    public RelayCommand SwitchNow => new(() => { if (_m.Confirm($"Switch NOW to {SelectionText} / {Gametype.Value}?\n\nThis is an in-match session switch - the running match ends.")) Switch(false); });
    private void Switch(bool stage)
    {
        var map = Selected?.Id;
        var gt = Gametype.Value;
        // Switch NOW: the target map's spawn pick goes in first, so its first round already uses it (a Stage
        // waits - the running match still needs its own pick; SpawnsVM pushes the staged map's at match end)
        if (!stage && map != null) _m.Spawns.PrePush(map);
        _m.Link.Send((stage ? "Stage " : "Switch NOW ") + (map ?? "(current map)") + " / " + gt, Commands.Switch(map, gt, stage));
        if (stage) _m.Toasts.Show("Staging - do not end the match until the game says STAGE READY", LogLevel.Info);
    }
    public RelayCommand RestartMatch => new(() => _m.RestartMatch());

    // ── playlist ──
    public RelayCommand AddToPlaylist => new(() =>
    {
        if (Selected == null) { _m.Toasts.Show("Pick a map on the grid first", LogLevel.Warn); return; }
        Playlist.Add(new PlaylistRowVM(new PlaylistEntry { Map = Selected.Id, Gametype = Selected.Def.Gametype ?? Gametype.Value }));
        PersistPlaylist();
    });
    public RelayCommand Remove => new(p => { if (p is PlaylistRowVM r) { Playlist.Remove(r); PersistPlaylist(); } });
    public RelayCommand MoveUp => new(p => Move(p, -1));
    public RelayCommand MoveDown => new(p => Move(p, 1));
    public RelayCommand SetNext => new(p => { if (p is PlaylistRowVM r) { _m.Prefs.PlaylistIndex = Playlist.IndexOf(r); _m.Prefs.Save(); MarkNext(); } });
    public RelayCommand StageNextNow => new(() => StageNext("manual"));
    public RelayCommand ClearPlaylist => new(() => { Playlist.Clear(); PersistPlaylist(); });
    private void Move(object? p, int d)
    {
        if (p is not PlaylistRowVM r) return;
        var i = Playlist.IndexOf(r); var j = i + d;
        if (j < 0 || j >= Playlist.Count) return;
        Playlist.Move(i, j); PersistPlaylist();
    }
    private void PersistPlaylist()
    {
        _m.Prefs.Playlist = Playlist.Select(r => r.Entry).ToList();
        if (_m.Prefs.PlaylistIndex >= Playlist.Count) _m.Prefs.PlaylistIndex = 0;
        _m.Prefs.Save();
        MarkNext();
    }
    private void MarkNext()
    {
        for (var i = 0; i < Playlist.Count; i++) Playlist[i].IsNext = PlaylistEnabled && i == _m.Prefs.PlaylistIndex;
        PlaylistStatus = Playlist.Count == 0 ? "empty" : PlaylistEnabled
            ? $"{Playlist.Count} maps · next: {Playlist[Math.Min(_m.Prefs.PlaylistIndex, Playlist.Count - 1)].Map}"
            : $"{Playlist.Count} maps · rotation off";
    }

    private string? _stagedForMatch;
    /// <summary>Stage the next playlist entry (once per match). Called when the match reaches its end phase.</summary>
    public void StageNext(string why)
    {
        if (Playlist.Count == 0) return;
        var i = Math.Min(_m.Prefs.PlaylistIndex, Playlist.Count - 1);
        var e = Playlist[i].Entry;
        var key = (_m.Link.State?.Map ?? "") + "#" + (_m.Link.State?.Round ?? 0) + "#" + i;
        if (why != "manual" && _stagedForMatch == key) return;
        _stagedForMatch = key;
        _m.Link.Send($"rotation: stage {Catalog.MapName(e.Map)} / {e.Gametype}", Commands.Switch(e.Map, e.Gametype, true));
        _m.Link.Log($"rotation ({why}): staged {e.Map} / {e.Gametype} as the next map", LogLevel.Ok);
        _m.Prefs.PlaylistIndex = (i + 1) % Playlist.Count;
        _m.Prefs.Save();
        MarkNext();
    }
}
