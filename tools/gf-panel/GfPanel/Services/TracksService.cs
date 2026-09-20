using System.IO;
using System.Text.Json;
using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>Saved race tracks (docs/notes/racing.md): the game publishes its gates in GFCFG (trk=map;n;x,y,z,yaw,w;...),
/// we file them per map + name in tracks.json, and load them back as `racetrack &lt;map&gt;` then one `racegate` per gate,
/// paced past the GSC's 0.25 s command poll.</summary>
public sealed class TracksService
{
    private readonly GameLink _link;
    private static string Path => System.IO.Path.Combine(App.DataDir, "tracks.json");
    public Dictionary<string, Dictionary<string, List<string>>> Tracks { get; private set; } = new();   // map -> name -> gates
    public event Action? Changed;

    public TracksService(GameLink link)
    {
        _link = link;
        try { if (File.Exists(Path)) Tracks = JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, List<string>>>>(File.ReadAllText(Path)) ?? new(); }
        catch { Tracks = new(); }
    }

    public IEnumerable<string> Labels => Tracks.OrderBy(m => m.Key).SelectMany(m => m.Value.OrderBy(t => t.Key).Select(t => $"{m.Key}: {t.Key}  ({t.Value.Count} gates)"));

    private void Save()
    {
        try { File.WriteAllText(Path, JsonSerializer.Serialize(Tracks, new JsonSerializerOptions { WriteIndented = true })); } catch { }
        Changed?.Invoke();
    }

    public void SaveFromGame(string name)
    {
        var trk = _link.Config?.Track;
        if (string.IsNullOrEmpty(trk)) { _link.ShowToast("no track in the game (race build injected? gates placed?)", LogLevel.Warn); return; }
        var parts = trk.Split(';');
        if (parts.Length < 2 || !int.TryParse(parts[1], out var n) || n == 0) { _link.ShowToast("the game holds no gates - place some first", LogLevel.Warn); return; }
        var map = parts[0];
        var gates = parts.Skip(2).Take(n).Where(g => g.Length > 0).ToList();
        if (!Tracks.TryGetValue(map, out var byName)) Tracks[map] = byName = new();
        byName[string.IsNullOrWhiteSpace(name) ? "track" : name.Trim()] = gates;
        Save();
        _link.Log($"saved {gates.Count} gates as '{name}' for {map}", LogLevel.Ok);
    }

    public (string Map, string Name, List<string> Gates)? Resolve(string label)
    {
        var idx = label.IndexOf(": ");
        if (idx < 0) return null;
        var map = label[..idx];
        var rest = label[(idx + 2)..];
        var name = rest.Contains("  (") ? rest[..rest.LastIndexOf("  (", StringComparison.Ordinal)] : rest;
        return Tracks.TryGetValue(map, out var byName) && byName.TryGetValue(name, out var gates) ? (map, name, gates) : null;
    }

    public async void LoadIntoGame(string label)
    {
        var r = Resolve(label);
        if (r == null) return;
        var (map, name, gates) = r.Value;
        _link.Log($"loading '{name}' ({gates.Count} gates) into the game on {map}, one command per 0.5 s...", LogLevel.Info);
        _link.Send("racetrack " + map, Commands.Action("racetrack", map));
        foreach (var g in gates)
        {
            await Task.Delay(500);
            _link.Send("racegate", Commands.Action("racegate", g));
        }
    }

    public void Delete(string label)
    {
        var r = Resolve(label);
        if (r == null) return;
        Tracks[r.Value.Map].Remove(r.Value.Name);
        if (Tracks[r.Value.Map].Count == 0) Tracks.Remove(r.Value.Map);
        Save();
    }
}
