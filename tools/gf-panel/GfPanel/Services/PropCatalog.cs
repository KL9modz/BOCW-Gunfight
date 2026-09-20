using System.IO;
using System.Reflection;
using System.Text.Json;
using GfPanel.Game;

namespace GfPanel.Services;

public sealed record PropEntry(int Index, string Model, string Label, bool Barrel)
{
    /// <summary>-1 = a per-map model (spawned by chunked name); >= 0 = a universal index (prop_master()).</summary>
    public bool IsUniversal => Index >= 0;
    public string Display => (Barrel ? "🛢 " : "") + Label + (IsUniversal ? $"  [#{Index}]" : "");
    public override string ToString() => Display;
}

/// <summary>
/// docs/data/map-props.json, embedded in the exe (docs/notes/prop-catalog.md is the contract): 546 universal
/// props resident on every MP map (index == the GSC prop_master() index == the propidx / barrelidx arg) and
/// each map's own ~1-2k props, spawned by chunked NAME (gf_pn0/1/2 + propname / barrelname).
/// </summary>
public sealed class PropCatalog
{
    public List<PropEntry> Universal { get; } = new();
    public Dictionary<string, List<PropEntry>> Maps { get; } = new();
    public string Generated { get; private set; } = "";
    public string LoadNote { get; private set; } = "";

    public PropCatalog()
    {
        try
        {
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("GfPanel.Data.map-props.json")
                          ?? (Stream?)File.OpenRead(Path.Combine(App.BaseDir, "map-props.json"));
            if (s == null) { LoadNote = "map-props.json not found"; return; }
            using var doc = JsonDocument.Parse(s);
            var root = doc.RootElement;
            Generated = root.TryGetProperty("generated", out var g) ? g.GetString() ?? "" : "";
            foreach (var u in root.GetProperty("universal").EnumerateArray())
                Universal.Add(new PropEntry(u.GetProperty("i").GetInt32(), u.GetProperty("model").GetString() ?? "", u.GetProperty("label").GetString() ?? "", u.GetProperty("barrel").GetBoolean()));
            foreach (var m in root.GetProperty("maps").EnumerateObject())
            {
                var list = new List<PropEntry>();
                foreach (var e in m.Value.EnumerateArray())
                    list.Add(new PropEntry(-1, e.GetProperty("model").GetString() ?? "", e.GetProperty("label").GetString() ?? "", e.GetProperty("barrel").GetBoolean()));
                Maps[m.Name] = list;
            }
            LoadNote = $"{Universal.Count} universal · {Maps.Count} maps · generated {Generated}";
        }
        catch (Exception e) { LoadNote = "map-props.json failed to load: " + e.Message; }
    }

    public const int ChunkChars = 36;   // `set gf_pn0 ` (11) + 36 = 47 bytes exactly

    /// <summary>The lines that spawn a model by NAME: three chunk dvars (always all three, so a stale chunk can
    /// never concatenate onto a shorter name), then the verb with scale x100 as its arg. Null if the name cannot fit.</summary>
    public static List<string>? ByNameLines(string model, int scalePct, bool barrel)
    {
        if (model.Length > ChunkChars * 3) return null;
        var lines = new List<string>();
        for (var c = 0; c < 3; c++)
        {
            var from = c * ChunkChars;
            var chunk = from < model.Length ? model.Substring(from, Math.Min(ChunkChars, model.Length - from)) : "";
            lines.Add(chunk.Length > 0 ? $"set gf_pn{c} {chunk}" : $"set gf_pn{c} \"\"");
        }
        lines.AddRange(Commands.Action(barrel ? "barrelname" : "propname", scalePct == 100 ? "0" : scalePct.ToString()));
        return lines;
    }

    /// <summary>gf_prop_favs / gf_prop_favs2 CSV lines (each ≤ 47 bytes); indices that do not fit are reported back.</summary>
    public static (List<string> Lines, List<int> Dropped) FavLines(IEnumerable<int> favs)
    {
        var lines = new List<string>();
        var dropped = new List<int>();
        var names = new[] { "gf_prop_favs", "gf_prop_favs2" };
        var queue = new Queue<int>(favs.Distinct().OrderBy(i => i));
        foreach (var n in names)
        {
            var cap = Native.BridgeChannel.MaxCommandBytes - ("set " + n + " ").Length;
            var csv = "";
            while (queue.Count > 0)
            {
                var next = (csv.Length == 0 ? "" : ",") + queue.Peek();
                if (csv.Length + next.Length > cap) break;
                csv += next; queue.Dequeue();
            }
            lines.Add(csv.Length > 0 ? $"set {n} {csv}" : $"set {n} \"\"");
        }
        dropped.AddRange(queue);
        return (lines, dropped);
    }
}
