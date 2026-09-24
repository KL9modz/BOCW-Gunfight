using System.IO;
using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>The saved race tracks (docs/notes/racing.md §11): race-tracks.json in the panel's data folder, one entry per
/// map + name (TrackLibrary). The tracks.json kept until 2026-09-24 is read into it once and left alone (an older panel
/// still reads that). A saved track goes into the game as racetrack &lt;map&gt; then one racegate per gate, 0.5 s apart
/// (the GSC consumes one command per 0.25 s poll) - ~32 s for a 64-gate track.</summary>
public sealed class TracksService
{
    private readonly GameLink _link;
    private static string PathNew => Path.Combine(App.DataDir, "race-tracks.json");
    private static string PathOld => Path.Combine(App.DataDir, "tracks.json");
    private readonly List<SavedTrack> _tracks = new();
    public IReadOnlyList<SavedTrack> Tracks => _tracks;
    public event Action? Changed;

    public TracksService(GameLink link)
    {
        _link = link;
        try
        {
            if (File.Exists(PathNew))
            {
                if (TrackLibrary.FromJson(File.ReadAllText(PathNew)) is { } f) _tracks.AddRange(f.Tracks);
            }
            else if (File.Exists(PathOld))
            {
                _tracks.AddRange(TrackLibrary.FromLegacy(File.ReadAllText(PathOld)));
                if (_tracks.Count > 0) Save();
            }
        }
        catch { /* a bad file must not stop the panel; the next save rewrites it */ }
    }

    private void Save()
    {
        try
        {
            var tmp = PathNew + ".tmp";
            File.WriteAllText(tmp, TrackLibrary.ToJson(new TrackLibrary.LibraryFile { Tracks = _tracks }));
            File.Move(tmp, PathNew, true);
        }
        catch (Exception e) { _link.Log("could not save race-tracks.json: " + e.Message, LogLevel.Err); }
        Changed?.Invoke();
    }

    private static bool Same(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public SavedTrack? Find(string map, string name) => _tracks.FirstOrDefault(t => Same(t.Map, map) && Same(t.Name, name));

    /// <summary>A name not yet used on <paramref name="map"/>: the name itself, else "name (2)", "name (3)"...</summary>
    public string FreeName(string map, string name)
    {
        name = string.IsNullOrWhiteSpace(name) ? "track" : name.Trim();
        if (Find(map, name) == null) return name;
        for (var i = 2; ; i++) if (Find(map, $"{name} ({i})") == null) return $"{name} ({i})";
    }

    /// <summary>File the game's track under a name - replacing a saved one of the same map + name.</summary>
    public SavedTrack Put(RaceTrack track, string name, bool sprint, int laps)
    {
        name = string.IsNullOrWhiteSpace(name) ? "track" : name.Trim();
        var t = Find(track.Map, name);
        if (t == null) { t = new SavedTrack { Map = track.Map, Name = name }; _tracks.Add(t); }
        t.Gates = track.Gates.Select(g => g.Text).ToList();
        t.Sprint = sprint;
        t.Laps = laps;
        t.Saved = DateTime.Now;
        Save();
        _link.Log($"saved '{name}' - {t.Gates.Count} gates on {track.Map}{(sprint ? ", A to B" : $", {laps} lap(s)")}", LogLevel.Ok);
        return t;
    }

    public void Delete(SavedTrack t) { _tracks.Remove(t); Save(); }

    public bool Rename(SavedTrack t, string name)
    {
        name = name.Trim();
        if (name.Length == 0 || (Find(t.Map, name) is { } other && !ReferenceEquals(other, t))) return false;
        t.Name = name;
        Save();
        return true;
    }

    public SavedTrack Duplicate(SavedTrack t)
    {
        var copy = new SavedTrack { Map = t.Map, Name = FreeName(t.Map, t.Name + " copy"), Gates = t.Gates.ToList(), Sprint = t.Sprint, Laps = t.Laps, Saved = DateTime.Now };
        _tracks.Add(copy);
        Save();
        return copy;
    }

    public void Export(SavedTrack t, string path) => File.WriteAllText(path, TrackLibrary.Export(t));

    /// <summary>A shared track file into the library (renamed when its map already has one of that name).</summary>
    public SavedTrack? Import(string path, out string why)
    {
        var t = TrackLibrary.Import(File.ReadAllText(path), out why);
        if (t == null) return null;
        t.Name = FreeName(t.Map, t.Name);
        if (t.Saved == default) t.Saved = DateTime.Now;
        _tracks.Add(t);
        Save();
        return t;
    }

    private CancellationTokenSource? _loading;
    public bool Loading => _loading != null;
    public void CancelLoad() => _loading?.Cancel();

    /// <summary>Send a saved track to the game: racetrack &lt;map&gt; (the game clears its own track only when the map
    /// matches, and refuses the gates otherwise), then one racegate per gate. <paramref name="progress"/>(i, n) after each.</summary>
    public async Task<bool> LoadIntoGame(SavedTrack t, Action<int, int>? progress)
    {
        _loading?.Cancel();
        var cts = new CancellationTokenSource();
        _loading = cts;
        var gates = t.GateList;
        _link.Log($"loading '{t.Name}' ({gates.Count} gates) into the game on {t.Map} - a gate every 0.5 s, ~{gates.Count / 2 + 1} s", LogLevel.Info);
        _link.Send("racetrack " + t.Map, Commands.Action("racetrack", t.Map));
        try
        {
            for (var i = 0; i < gates.Count; i++)
            {
                await Task.Delay(500, cts.Token);
                _link.Send($"racegate {i + 1}/{gates.Count}", Commands.Action("racegate", RaceArgs.Gate(gates[i])));
                progress?.Invoke(i + 1, gates.Count);
            }
            return true;
        }
        catch (TaskCanceledException) { _link.Log($"loading '{t.Name}' cancelled - the game holds the gates sent so far", LogLevel.Warn); return false; }
        finally { if (ReferenceEquals(_loading, cts)) _loading = null; }
    }
}
