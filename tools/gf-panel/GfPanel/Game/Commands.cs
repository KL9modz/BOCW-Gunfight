using System.Text;

namespace GfPanel.Game;

/// <summary>
/// Composes the console `set` lines the GSC command poller consumes (cmd_poll / cmd_dispatch /
/// cmd_action in gunfight_menu.gsc). One line = one bridge message; every line must fit the 47-byte
/// slot, so free text is capped here and never truncated mid-send by the transport.
///
/// A command = its payload lines + `set gf_cmd_seq N` + `set gf_cmd_go 1` (go LAST: the poller is
/// gated on that pulse). The GSC records N as the ack once dispatched and ignores a repeated N, so a
/// timed-out command may be re-sent verbatim.
/// </summary>
public static class Commands
{
    public const int MaxTargetChars = 24;
    public const int MaxSayChars = 30;      // `set gf_cmd_say "` (17) + text + `"` = 47
    public const int MaxArgChars = 32;      // `set gf_cmd_arg ` (15) + arg

    /// <summary>Quote a free-text value (spaces survive `set`); strip what would break the line.</summary>
    public static string Clean(string s, int max) =>
        new string(s.Where(c => c >= 32 && c < 127 && c != '"' && c != ';' && c != '\\').ToArray()).Trim() is var t && t.Length > max ? t[..max] : t;

    public static List<string> Action(string action, string? arg = null, string? target = null)
    {
        var lines = new List<string>();
        if (!string.IsNullOrEmpty(target)) lines.Add($"set gf_cmd_target \"{Clean(target, MaxTargetChars)}\"");
        lines.Add($"set gf_cmd_action {action}");
        if (!string.IsNullOrEmpty(arg)) lines.Add($"set gf_cmd_arg {Clean(arg, MaxArgChars)}");
        return lines;
    }

    public static List<string> Say(string text, int loc, int dur, int indent, string audience)
    {
        var lines = new List<string>
        {
            $"set gf_cmd_say_loc {loc}",
            $"set gf_cmd_say_dur {dur}",
        };
        if (loc == 2) lines.Add($"set gf_say_hint_indent {Math.Clamp(indent, 0, 40)}");
        if (!string.IsNullOrEmpty(audience) && audience != "all") lines.Add($"set gf_cmd_say_aud \"{Clean(audience, MaxTargetChars)}\"");
        lines.Add($"set gf_cmd_say \"{Clean(text, MaxSayChars)}\"");
        return lines;
    }

    public static List<string> Switch(string? map, string gametype, bool stage) => new()
    {
        $"set gf_cmd_map {(string.IsNullOrEmpty(map) ? "\"\"" : map)}",
        $"set gf_cmd_gametype {gametype}",
        $"set gf_cmd_stage {(stage ? 1 : 0)}",
    };

    /// <summary>Stamp + fire: the seq line and the go pulse appended to a payload.</summary>
    public static List<string> Fire(IEnumerable<string> payload, long seq)
    {
        var l = payload.ToList();
        l.Add($"set gf_cmd_seq {seq}");
        l.Add("set gf_cmd_go 1");
        return l;
    }

    /// <summary>A plain dvar write (unpacked setting).</summary>
    public static string Set(string dvar, int value) => $"set {dvar} {value}";

    /// <summary>Verbs that change or end the level: sent once, never retried - the ack is lost in the reload, and a
    /// retry ran map_restart AGAIN (klaze 2026-09-22: "restart round and restart match fire multiple quick restarts").</summary>
    public static readonly HashSet<string> LevelVerbs = new(StringComparer.OrdinalIgnoreCase) { "restart", "restartround", "relaunch", "endmatch", "endround" };
    /// <summary>Verb + argument pairs that end the level too. RACE → END MATCH is `race endmatch` - verb `race`, so the
    /// verb list above missed it and a retry could land in the NEXT match (the 2026-09-24 panel review).</summary>
    public static readonly HashSet<string> LevelVerbArgs = new(StringComparer.OrdinalIgnoreCase) { "race endmatch" };

    /// <summary>What a command's lines do to the level: "switch" for a map switch / stage (gf_cmd_map), the verb (or
    /// "verb arg") for a level verb, null for everything else.</summary>
    public static string? LevelChange(IReadOnlyList<string> lines)
    {
        if (lines.Any(l => l.StartsWith("set gf_cmd_map ", StringComparison.Ordinal))) return "switch";
        string? Value(string prefix) => lines.Where(l => l.StartsWith(prefix, StringComparison.Ordinal)).Select(l => l[prefix.Length..].Trim()).FirstOrDefault();
        var action = Value("set gf_cmd_action ");
        if (action == null) return null;
        if (LevelVerbs.Contains(action)) return action;
        var arg = Value("set gf_cmd_arg ");
        return arg != null && LevelVerbArgs.Contains(action + " " + arg) ? action + " " + arg : null;
    }

    public static int ByteLength(string line) => Encoding.ASCII.GetByteCount(line);
}
