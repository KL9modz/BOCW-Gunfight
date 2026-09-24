using System.Text;
using System.Text.RegularExpressions;

namespace GfPanel.Tests;

/// <summary>The repository the checks run against: found by walking up from the test binary (or the current
/// folder) to the folder that holds src/gunfight_menu/scripts/gunfight_menu.gsc.</summary>
public static class Repo
{
    private static string? _root;

    public static string Root => _root ??= Find();

    public static string At(params string[] parts) => Path.Combine(new[] { Root }.Concat(parts).ToArray());

    public static string Read(params string[] parts) => File.ReadAllText(At(parts));

    /// <summary>The panel's own source folder (tools/gf-panel/GfPanel).</summary>
    public static string PanelDir => At("tools", "gf-panel", "GfPanel");

    public static IEnumerable<string> PanelFiles(string pattern) =>
        Directory.EnumerateFiles(PanelDir, pattern, SearchOption.AllDirectories)
                 .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") &&
                             !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
                 .OrderBy(f => f, StringComparer.Ordinal);

    public static string Rel(string path) => Path.GetRelativePath(Root, path).Replace('\\', '/');

    private static string Find()
    {
        foreach (var start in new[] { AppContext.BaseDirectory, Environment.CurrentDirectory })
        {
            for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "src", "gunfight_menu", "scripts", "gunfight_menu.gsc")))
                    return d.FullName;
        }
        throw new CheckFailed("repo root not found: no src/gunfight_menu/scripts/gunfight_menu.gsc above the test binary or the current folder");
    }
}

/// <summary>A GSC source file, read the way the contract checks need it: comment-free code lines and function
/// bodies by name. Parsing is textual on purpose - the checks exist to catch the two sides drifting apart,
/// and a function they cannot find fails loudly (renamed? update the check) instead of passing quietly.</summary>
public sealed class GscSource
{
    private static GscSource? _menu, _lobby;

    public static GscSource Menu => _menu ??= new GscSource("src/gunfight_menu/scripts/gunfight_menu.gsc");
    public static GscSource Lobby => _lobby ??= new GscSource("src/gunfight_lobby/scripts/gunfight_lobby.gsc");

    public string RelPath { get; }
    /// <summary>The file's lines with // and /* */ comments blanked out (string literals respected), 0-based.</summary>
    public string[] Code { get; }
    public string AllCode { get; }

    public GscSource(string relPath)
    {
        RelPath = relPath;
        Code = StripComments(File.ReadAllLines(Repo.At(relPath.Split('/'))));
        AllCode = string.Join("\n", Code);
    }

    /// <summary>One function's code, from its `function` line up to the next top-level `function` line.
    /// Line is 1-based (as editors and file:line citations count).</summary>
    public (int Line, string Body) Function(string name)
    {
        var head = new Regex(@"^function\s+(?:private\s+)?(?:autoexec\s+)?" + Regex.Escape(name) + @"\s*\(");
        for (var i = 0; i < Code.Length; i++)
        {
            if (!head.IsMatch(Code[i])) continue;
            var j = i + 1;
            while (j < Code.Length && !Code[j].StartsWith("function ", StringComparison.Ordinal)) j++;
            return (i + 1, string.Join("\n", Code[i..j]));
        }
        throw new CheckFailed($"{RelPath}: function {name}() not found - renamed or removed? Update the check with it.");
    }

    /// <summary>1-based line of the first code line matching <paramref name="pattern"/> at or after <paramref name="from"/> (1-based).</summary>
    public int LineOf(string pattern, int from = 1)
    {
        var re = new Regex(pattern);
        for (var i = Math.Max(0, from - 1); i < Code.Length; i++)
            if (re.IsMatch(Code[i])) return i + 1;
        return -1;
    }

    /// <summary>Every `case "x":` label in a piece of code, in order.</summary>
    public static List<string> CaseLabels(string code) =>
        Regex.Matches(code, @"\bcase\s+""([A-Za-z0-9_]+)""\s*:").Select(m => m.Groups[1].Value).ToList();

    /// <summary>The contents of every string literal in a piece of code (#"..." hashes included).</summary>
    public static List<string> StringLiterals(string code) =>
        Regex.Matches(code, @"""((?:[^""\\]|\\.)*)""").Select(m => m.Groups[1].Value).ToList();

    private static string[] StripComments(string[] lines)
    {
        var outLines = new string[lines.Length];
        var inBlock = false;
        for (var n = 0; n < lines.Length; n++)
        {
            var s = lines[n];
            var sb = new StringBuilder(s.Length);
            var inString = false;
            for (var i = 0; i < s.Length; i++)
            {
                var c = s[i];
                if (inBlock)
                {
                    if (c == '*' && i + 1 < s.Length && s[i + 1] == '/') { inBlock = false; i++; }
                    continue;
                }
                if (inString)
                {
                    sb.Append(c);
                    if (c == '\\' && i + 1 < s.Length) { sb.Append(s[++i]); continue; }
                    if (c == '"') inString = false;
                    continue;
                }
                if (c == '"') { inString = true; sb.Append(c); continue; }
                if (c == '/' && i + 1 < s.Length && s[i + 1] == '/') break;
                if (c == '/' && i + 1 < s.Length && s[i + 1] == '*') { inBlock = true; i++; continue; }
                sb.Append(c);
            }
            outLines[n] = sb.ToString();
        }
        return outLines;
    }
}

/// <summary>Just enough C# reading for the contract checks: the arguments of a call, with strings (plain,
/// verbatim, interpolated) and nested brackets respected.</summary>
public static class CSharpText
{
    /// <summary>Every call to <paramref name="callee"/> (e.g. "Do" or "Commands.Action") in a source text, as
    /// (1-based line, argument source texts). A definition (`void Do(`) is not a call and is skipped.</summary>
    public static IEnumerable<(int Line, List<string> Args)> Calls(string source, string callee)
    {
        var re = new Regex(@"(?<![\w.])" + Regex.Escape(callee) + @"\s*\(");
        foreach (Match m in re.Matches(source))
        {
            var before = source[..m.Index].TrimEnd();
            if (Regex.IsMatch(before, @"\b(void|string|bool|int|List<string>|RelayCommand)$")) continue;   // a definition
            var open = m.Index + m.Length - 1;
            var args = SplitArgs(source, open);
            if (args == null) continue;
            yield return (LineAt(source, m.Index), args);
        }
    }

    /// <summary>The literal values an argument expression can take: "x" gives [x]; c ? "a" : "b" gives [a, b];
    /// anything else gives null (not a literal - the caller reports it).</summary>
    public static List<string>? Literals(string arg)
    {
        arg = arg.Trim();
        var one = Regex.Match(arg, @"^""((?:[^""\\]|\\.)*)""$");
        if (one.Success) return new List<string> { Regex.Unescape(one.Groups[1].Value) };
        var tern = Regex.Match(arg, @"^[^?]+\?\s*""((?:[^""\\]|\\.)*)""\s*:\s*""((?:[^""\\]|\\.)*)""$");
        if (tern.Success) return new List<string> { tern.Groups[1].Value, tern.Groups[2].Value };
        return null;
    }

    public static int LineAt(string source, int index)
    {
        var line = 1;
        for (var i = 0; i < index && i < source.Length; i++) if (source[i] == '\n') line++;
        return line;
    }

    /// <summary>The top-level arguments of the call whose '(' is at <paramref name="open"/>; null when unterminated.</summary>
    public static List<string>? SplitArgs(string s, int open)
    {
        var args = new List<string>();
        var depth = 0;
        var start = open + 1;
        var i = open;
        while (i < s.Length)
        {
            var c = s[i];
            if (c == '"' || c == '@' && i + 1 < s.Length && s[i + 1] == '"' || c == '$' && i + 1 < s.Length && (s[i + 1] == '"' || s[i + 1] == '@'))
            {
                i = SkipString(s, i);
                continue;
            }
            if (c == '\'')
            {
                i = SkipChar(s, i);
                continue;
            }
            if (c is '(' or '[' or '{') depth++;
            else if (c is ')' or ']' or '}')
            {
                depth--;
                if (depth == 0)
                {
                    var last = s[start..i].Trim();
                    if (last.Length > 0 || args.Count > 0) args.Add(last);
                    return args;
                }
            }
            else if (c == ',' && depth == 1)
            {
                args.Add(s[start..i].Trim());
                start = i + 1;
            }
            i++;
        }
        return null;
    }

    /// <summary>Index just past the string literal starting at i ("..", @"..", $"..", $@"..", @$"..").</summary>
    private static int SkipString(string s, int i)
    {
        var interp = false;
        var verbatim = false;
        while (s[i] != '"')
        {
            if (s[i] == '$') interp = true;
            if (s[i] == '@') verbatim = true;
            i++;
        }
        i++;   // opening quote
        while (i < s.Length)
        {
            var c = s[i];
            if (!verbatim && c == '\\') { i += 2; continue; }
            if (c == '"')
            {
                if (verbatim && i + 1 < s.Length && s[i + 1] == '"') { i += 2; continue; }
                return i + 1;
            }
            if (interp && c == '{')
            {
                if (i + 1 < s.Length && s[i + 1] == '{') { i += 2; continue; }
                i = SkipHole(s, i + 1);
                continue;
            }
            i++;
        }
        return i;
    }

    /// <summary>Index just past the '}' closing an interpolation hole whose code starts at i.</summary>
    private static int SkipHole(string s, int i)
    {
        var depth = 1;
        while (i < s.Length)
        {
            var c = s[i];
            if (c == '"' || c == '@' && i + 1 < s.Length && s[i + 1] == '"' || c == '$' && i + 1 < s.Length && (s[i + 1] == '"' || s[i + 1] == '@'))
            {
                i = SkipString(s, i);
                continue;
            }
            if (c == '\'') { i = SkipChar(s, i); continue; }
            if (c is '(' or '[' or '{') depth++;
            else if (c is ')' or ']' or '}')
            {
                depth--;
                if (depth == 0) return i + 1;
            }
            i++;
        }
        return i;
    }

    private static int SkipChar(string s, int i)
    {
        i++;
        while (i < s.Length && s[i] != '\'')
        {
            if (s[i] == '\\') i++;
            i++;
        }
        return i + 1;
    }
}
