using GfPanel.Game;

namespace GfPanel.Services;

/// <summary>
/// Writes host settings the way the in-game menu does: a packed field rebuilds ITS chunk (the other
/// five cells come from the game's LIVE values, never from app defaults - the F4 "packed-chunk
/// contamination" that used to reload the match), the bot knobs rebuild gf_bot / gf_bot2, a plain
/// dvar is a plain `set`; then, for a field a live subsystem owns, one `apply <scope>` pulse so the
/// running match picks it up (exactly what a menu pick does). Structural fields land at the next
/// match start (mod_apply) - the caller offers the restart.
/// </summary>
public sealed class ConfigWriter
{
    private readonly GameLink _link;
    public ConfigWriter(GameLink link) { _link = link; }

    /// <summary>The game's config readback must have landed before a packed chunk is rebuilt.</summary>
    public bool CanWritePacked => _link.Config != null;

    public sealed record Plan(List<string> Lines, string? Scope, bool NeedsRestart, string Summary, Dictionary<string, int> Applied);

    public Plan Compose(IReadOnlyDictionary<string, int> changes)
    {
        var lines = new List<string>();
        var chunks = new SortedSet<int>();
        var bot = false;
        var scopes = new SortedSet<string>();
        var restart = false;
        var merged = new Dictionary<string, int>(_link.Baseline);
        var applied = new Dictionary<string, int>();
        foreach (var (dvar, value) in changes)
        {
            merged[dvar] = value;
            applied[dvar] = value;
            if (!Schema.ByDvar.TryGetValue(dvar, out var def)) continue;
            if (def.Scope != null) scopes.Add(def.Scope);
            if (def.RestartRequired) restart = true;
            if (Packing.PackedIndex(dvar) >= 0) chunks.Add(Packing.ChunkOf(dvar));
            else if (Packing.BotIndexOf(dvar) >= 0) bot = true;
            else lines.Add(Commands.Set(dvar, value));
        }
        foreach (var c in chunks) lines.Add(Packing.ChunkLine(c, merged));
        if (bot) lines.AddRange(Packing.BotLines(merged));
        var summary = string.Join(", ", changes.Select(kv => $"{Schema.ByDvar.GetValueOrDefault(kv.Key)?.Label ?? kv.Key} = {ValueLabel(kv.Key, kv.Value)}"));
        return new Plan(lines, scopes.Count > 0 ? string.Join(",", scopes) : null, restart, summary, applied);
    }

    public static string ValueLabel(string dvar, int value)
    {
        if (!Schema.ByDvar.TryGetValue(dvar, out var def)) return value.ToString();
        if (def.Kind == SettingKind.Toggle) return value == 1 ? "on" : "off";
        return def.Choices?.FirstOrDefault(c => c.Value == value)?.Label ?? value.ToString();
    }

    /// <summary>Send a plan: the dvar lines (background lane, no ack), then the apply pulse (acked) when a live
    /// scope is involved and <paramref name="applyLive"/>. Returns the queue entry of the pulse, if any.</summary>
    public async Task<QueuedCommand?> WriteAsync(Plan plan, bool applyLive)
    {
        if (plan.Lines.Count > 0) await _link.SendRaw(plan.Lines, 8);
        // neighbour on what we just sent until the GFCFG readback confirms it (2 s later)
        foreach (var kv in plan.Applied) _link.Baseline[kv.Key] = kv.Value;
        if (applyLive && plan.Scope != null)
            return _link.Send("apply " + plan.Scope, Commands.Action("apply", plan.Scope), 10);
        return null;
    }
}
