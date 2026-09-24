using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace GfPanel.Tests;

/// <summary>What gunfight_menu.gsc (and the lobby payload) say about the panel's channels, read from the source.</summary>
public static class Gsc
{
    private static GscSource M => GscSource.Menu;

    /// <summary>cfg_spec(): the packed settings, in store order, with their defaults.</summary>
    public static List<(string Dvar, int Default)> CfgSpec() =>
        Regex.Matches(M.Function("cfg_spec").Body, @"cfg_add\(\s*c\s*,\s*#""(gf_\w+)""\s*,\s*(-?\d+)\s*\)")
             .Select(m => (m.Groups[1].Value, int.Parse(m.Groups[2].Value))).ToList();

    /// <summary>One-line cfg_* readers: `function private cfg_x() { return ...cfg_geti( #"gf_x", d )... }` → (dvar, default).</summary>
    public static Dictionary<string, (string Dvar, int Default)> Wrappers()
    {
        var d = new Dictionary<string, (string, int)>();
        foreach (Match m in Regex.Matches(M.AllCode,
                     @"function\s+(?:private\s+)?(cfg_\w+)\(\s*\)\s*\{[^{}\n]*?\bcfg_geti\(\s*#""(gf_\w+)""\s*,\s*(-?\d+)\s*\)"))
            d[m.Groups[1].Value] = (m.Groups[2].Value, int.Parse(m.Groups[3].Value));
        return d;
    }

    /// <summary>The dvars a config_publish extra carries, in order: `s += "|key=" + a() + "," + b() ...;`.</summary>
    public static List<string> PublishList(string key)
    {
        var body = M.Function("config_publish").Body;
        var at = body.IndexOf($"\"|{key}=\"", StringComparison.Ordinal);
        if (at < 0) throw new CheckFailed($"config_publish has no \"|{key}=\" extra");
        var end = body.IndexOf(';', at);
        var expr = body[at..end];
        var wrappers = Wrappers();
        var list = new List<string>();
        foreach (Match m in Regex.Matches(expr, @"\bcfg_geti\(\s*#""(gf_\w+)""|\bgetdvar\w*\(\s*#""(gf_\w+)""|\b(cfg_\w+)\(\s*\)"))
        {
            if (m.Groups[1].Success) list.Add(m.Groups[1].Value);
            else if (m.Groups[2].Success) list.Add(m.Groups[2].Value);
            else if (wrappers.TryGetValue(m.Groups[3].Value, out var w)) list.Add(w.Dvar);
            else throw new CheckFailed($"config_publish |{key}=: can't tell which dvar {m.Groups[3].Value}() reads");
        }
        return list;
    }

    /// <summary>The bot knobs in gf_bot / gf_bot2 order: the writer's `cfg_seti( #"gf_bot", hit + "," + head ...)`.</summary>
    public static List<string> BotOrder(string dvar)
    {
        var m = Regex.Match(M.AllCode, @"cfg_seti\(\s*#""" + dvar + @"""\s*,\s*([a-z_]+(?:\s*\+\s*"",""\s*\+\s*[a-z_]+)+)\s*\)");
        if (!m.Success) throw new CheckFailed($"no cfg_seti( #\"{dvar}\", a + \",\" + b ... ) writer found");
        return Regex.Matches(m.Groups[1].Value, @"[a-z_]+").Select(x => "gf_bot_" + x.Value).ToList();
    }

    /// <summary>The fallback string a gf_bot / gf_bot2 read uses when the dvar is empty.</summary>
    public static List<int> BotDefaults(string dvar)
    {
        var m = Regex.Match(M.AllCode, @"getdvarstring\(\s*#""" + dvar + @"""\s*,\s*""([-\d,]+)""\s*\)");
        if (!m.Success) throw new CheckFailed($"no getdvarstring( #\"{dvar}\", \"...\" ) read found");
        return m.Groups[1].Value.Split(',').Select(int.Parse).ToList();
    }

    /// <summary>Every int read of a gf_* dvar with a default, in the menu (minus the dead dvars_register) and the
    /// lobby payload: dvar → the (default, file:line) of each read.</summary>
    public static Dictionary<string, List<(int Default, string Where)>> ReaderDefaults()
    {
        var d = new Dictionary<string, List<(int, string)>>();
        foreach (var src in new[] { GscSource.Menu, GscSource.Lobby })
        {
            var skip = (From: -1, To: -1);
            if (src == GscSource.Menu)
            {
                var (line, body) = src.Function("dvars_register");   // ⚠ never called (the dvar-pool crash)
                skip = (line, line + body.Count(ch => ch == '\n'));
            }
            for (var i = 0; i < src.Code.Length; i++)
            {
                if (i + 1 >= skip.From && i + 1 <= skip.To) continue;
                foreach (Match m in Regex.Matches(src.Code[i], @"\b(?:cfg_geti|getdvarint)\(\s*#?""(gf_\w+)""\s*,\s*(-?\d+)\s*\)"))
                {
                    if (!d.TryGetValue(m.Groups[1].Value, out var list)) d[m.Groups[1].Value] = list = new List<(int, string)>();
                    list.Add((int.Parse(m.Groups[2].Value), $"{Path.GetFileName(src.RelPath)}:{i + 1}"));
                }
            }
        }
        return d;
    }

    /// <summary>The keys GFSTATE carries: every `|key=` in state_build's string literals plus the fallback line's.</summary>
    public static List<string> StateKeys()
    {
        var keys = new List<string>();
        foreach (var fn in new[] { "state_build", "state_publish" })
            foreach (var lit in GscSource.StringLiterals(M.Function(fn).Body))
                foreach (Match m in Regex.Matches(lit, @"(?:^|\|)([a-z][a-z0-9]*)="))
                    if (!keys.Contains(m.Groups[1].Value)) keys.Add(m.Groups[1].Value);
        return keys;
    }

    /// <summary>The verbs the command channel answers: cmd_action's switch plus panel_verb's (its default: branch).</summary>
    public static HashSet<string> Verbs() =>
        GscSource.CaseLabels(M.Function("cmd_action").Body).Concat(GscSource.CaseLabels(M.Function("panel_verb").Body)).ToHashSet();

    /// <summary>fun_verb's sub-verbs (`fun &lt;what&gt; [args]`).</summary>
    public static HashSet<string> FunVerbs() => GscSource.CaseLabels(M.Function("fun_verb").Body).ToHashSet();

    /// <summary>veh_master()'s rows in order: (label, kind) of each veh_def( m, name, label, kind [, fallback] ).</summary>
    public static List<(string Label, int Kind)> VehicleRows() =>
        Regex.Matches(M.Function("veh_master").Body, @"\bveh_def\(\s*m\s*,\s*#?""[^""]*""\s*,\s*""((?:[^""\\]|\\.)*)""\s*,\s*(\d+)")
             .Select(m => (m.Groups[1].Value, int.Parse(m.Groups[2].Value))).ToList();

    /// <summary>A `switch ( i ) { case 0: ... }` pick table: the code of each numbered case, in order.</summary>
    public static List<string> NumberedCases(string function)
    {
        var body = M.Function(function).Body;
        var ms = Regex.Matches(body, @"\bcase\s+(\d+)\s*:");
        var list = new List<string>();
        for (var k = 0; k < ms.Count; k++)
        {
            Check.Equal(k, int.Parse(ms[k].Groups[1].Value), $"{function}() case order");
            var from = ms[k].Index + ms[k].Length;
            var to = k + 1 < ms.Count ? ms[k + 1].Index : body.IndexOf("default", from, StringComparison.Ordinal) is var dflt && dflt > 0 ? dflt : body.Length;
            list.Add(body[from..to]);
        }
        return list;
    }
}

/// <summary>What the panel's own source sends, read from the C# and the XAML.</summary>
public static class Panel
{
    public sealed record Sent(string Verb, string Where);

    /// <summary>Every gf_cmd_action verb a panel source file can send, and every call site whose verb is not a
    /// literal (the check lists those rather than guessing).</summary>
    public static (List<Sent> Verbs, List<string> Unresolved) Verbs()
    {
        var verbs = new List<Sent>();
        var unresolved = new List<string>();
        foreach (var file in Repo.PanelFiles("*.cs"))
        {
            if (file.EndsWith($"Game{Path.DirectorySeparatorChar}Commands.cs", StringComparison.Ordinal)) continue;
            var src = File.ReadAllText(file);
            var rel = Repo.Rel(file);
            var lines = src.Split('\n');
            void Take(string callee, int argIndex)
            {
                foreach (var (line, args) in CSharpText.Calls(src, callee))
                {
                    // the Do(...) helpers' own bodies pass their parameter through - their callers are read instead
                    if (Regex.IsMatch(lines[line - 1], @"\bvoid\s+Do\(")) continue;
                    if (args.Count <= argIndex) { unresolved.Add($"{rel}:{line} {callee}(...) has no verb argument"); continue; }
                    var lits = CSharpText.Literals(args[argIndex]);
                    if (lits == null) { unresolved.Add($"{rel}:{line} {callee}( {args[argIndex]} )"); continue; }
                    verbs.AddRange(lits.Select(v => new Sent(v, $"{rel}:{line}")));
                }
            }
            Take("Commands.Action", 0);
            // the per-VM helpers: Do(label, verb, arg[, target]) in BotsVM / ForgeVM / PlayersVM / ToolsVM
            if (Regex.IsMatch(src, @"\bvoid\s+Do\(\s*string\s+\w+\s*,\s*string\s+\w+")) Take("Do", 1);
            foreach (Match m in Regex.Matches(src, @"""set gf_cmd_action ([a-z0-9_]+)"))
                verbs.Add(new Sent(m.Groups[1].Value, $"{rel}:{CSharpText.LineAt(src, m.Index)}"));
        }
        return (verbs, unresolved);
    }

    /// <summary>Every `fun &lt;what&gt; ...` argument the panel can send: XAML CommandParameters on a Fun / Fun.Send
    /// command, FunVM's Send.Execute("...") literals, and `fun` verbs sent through a Do(...) helper.</summary>
    public static List<Sent> FunArgs()
    {
        var list = new List<Sent>();
        foreach (var file in Repo.PanelFiles("*.xaml"))
        {
            var doc = XDocument.Load(file, LoadOptions.SetLineInfo);
            foreach (var el in doc.Descendants())
            {
                var cmd = el.Attribute("Command")?.Value;
                var par = el.Attribute("CommandParameter")?.Value;
                if (cmd == null || par == null || par.StartsWith("{", StringComparison.Ordinal)) continue;
                var path = Regex.Match(cmd, @"\{Binding\s+(?:Path=)?([\w.]+)").Groups[1].Value;
                if (path is "Fun" or "Fun.Send" || path.EndsWith(".Fun", StringComparison.Ordinal) || path.EndsWith(".Fun.Send", StringComparison.Ordinal))
                    list.Add(new Sent(par, $"{Repo.Rel(file)}:{((System.Xml.IXmlLineInfo)el).LineNumber}"));
            }
        }
        foreach (var file in Repo.PanelFiles("*.cs"))
        {
            var src = File.ReadAllText(file);
            var rel = Repo.Rel(file);
            foreach (Match m in Regex.Matches(src, @"\bSend\.Execute\(\s*""([^""]+)"""))
                list.Add(new Sent(m.Groups[1].Value, $"{rel}:{CSharpText.LineAt(src, m.Index)}"));
            if (!Regex.IsMatch(src, @"\bvoid\s+Do\(\s*string\s+\w+\s*,\s*string\s+\w+")) continue;
            foreach (var (line, args) in CSharpText.Calls(src, "Do"))
                if (args.Count > 2 && CSharpText.Literals(args[1]) is [ "fun" ] && CSharpText.Literals(args[2]) is { } a)
                    list.AddRange(a.Select(v => new Sent(v, $"{rel}:{line}")));
        }
        return list;
    }
}
