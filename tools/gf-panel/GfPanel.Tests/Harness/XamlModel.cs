using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace GfPanel.Tests;

/// <summary>The panel's C# types as the XAML sees them: every class / record's public properties and their types,
/// read from the source (the WPF assembly cannot be loaded here). Coarse on purpose - a nested type's members count
/// for its outer type too - so it errs toward accepting a binding, never toward a false alarm.</summary>
public sealed class TypeModel
{
    private readonly Dictionary<string, Dictionary<string, string>> _members = new();
    private readonly Dictionary<string, string> _bases = new();

    public static TypeModel Load()
    {
        var m = new TypeModel();
        foreach (var f in Repo.PanelFiles("*.cs")) m.Read(File.ReadAllText(f));
        return m;
    }

    public bool Knows(string type) => _members.ContainsKey(type);

    private static readonly Regex Decl = new(@"\b(class|record|struct)\s+(\w+)\s*(<[^>{(]*>)?\s*(\((?<params>[^)]*)\))?\s*(:\s*(?<bases>[^{;]+))?\s*(?<open>[{;])");
    private static readonly Regex Prop = new(@"\bpublic\s+(?:(?:static|override|virtual|new|required|readonly|sealed|abstract)\s+)*(?<type>[\w<>\[\],.?() ]+?)\s+(?<name>@?\w+)\s*(?:\{|=>|=(?!=)|;)");

    private void Read(string src)
    {
        foreach (Match d in Decl.Matches(src))
        {
            var name = d.Groups[2].Value;
            if (!_members.TryGetValue(name, out var members)) _members[name] = members = new Dictionary<string, string>();
            if (d.Groups["bases"].Success) _bases[name] = d.Groups["bases"].Value.Split(',')[0].Trim();
            if (d.Groups["params"].Success)
                foreach (var p in SplitTop(d.Groups["params"].Value, ','))
                {
                    var pm = Regex.Match(p.Trim(), @"^(?<type>.+?)\s+(?<name>\w+)\s*(=.*)?$");
                    if (pm.Success) members[pm.Groups["name"].Value] = pm.Groups["type"].Value.Trim();
                }
            if (d.Groups["open"].Value != "{") continue;
            var open = d.Groups["open"].Index;
            var close = Match(src, open);
            var body = src[(open + 1)..close];
            foreach (Match p in Prop.Matches(body))
            {
                var type = p.Groups["type"].Value.Trim();
                if (type is "class" or "record" or "struct" or "enum" or "event" or "const" or "delegate" || type.EndsWith(" class", StringComparison.Ordinal)) continue;
                members.TryAdd(p.Groups["name"].Value.TrimStart('@'), type);
            }
        }
    }

    /// <summary>The type of <paramref name="member"/> on <paramref name="type"/> (bases included); null = no such member.</summary>
    public string? MemberType(string type, string member)
    {
        for (var t = type; t != null; t = _bases.GetValueOrDefault(t))
        {
            if (_members.TryGetValue(t, out var ms) && ms.TryGetValue(member, out var mt)) return Clean(mt);
            if (Regex.IsMatch(t, "^I[A-Z]")) return null;   // an interface (INotifyPropertyChanged, ICommand ...): no bindable members
            if (!_members.ContainsKey(t)) return "?";       // a framework base class (Freezable, Window ...): cannot tell
        }
        return null;
    }

    public static string Clean(string t) => t.Replace("?", "").Trim();

    /// <summary>The element type of a collection type, "?" when it cannot be told.</summary>
    public static string ElementType(string t)
    {
        t = Clean(t);
        if (t.EndsWith("[]", StringComparison.Ordinal)) return t[..^2];
        var g = Regex.Match(t, @"^(?:[\w.]+\.)?(ObservableCollection|List|IEnumerable|IReadOnlyList|IReadOnlyCollection|ICollection|IList)<(?<a>.+)>$");
        return g.Success ? g.Groups["a"].Value.Trim() : "?";
    }

    public static bool IsCollection(string t) => ElementType(t) != "?" || Clean(t) is "ICollectionView" or "CompositeCollection" or "IEnumerable" or "object";

    private static int Match(string s, int open)
    {
        var depth = 0;
        for (var i = open; i < s.Length; i++)
        {
            var c = s[i];
            if (c == '"' || c == '\'')
            {
                var verbatim = i > 0 && s[i - 1] == '@' || i > 1 && s[i - 1] == '$' && s[i - 2] == '@';
                i++;
                while (i < s.Length && s[i] != c)
                {
                    if (s[i] == '\\' && !verbatim) i++;
                    i++;
                }
                continue;
            }
            if (c == '/' && i + 1 < s.Length && s[i + 1] == '/') { while (i < s.Length && s[i] != '\n') i++; continue; }
            if (c == '{') depth++;
            else if (c == '}' && --depth == 0) return i;
        }
        return s.Length - 1;
    }

    public static List<string> SplitTop(string s, char sep)
    {
        var parts = new List<string>();
        var depth = 0;
        var start = 0;
        var quoted = false;
        for (var i = 0; i < s.Length; i++)
        {
            var c = s[i];
            if (c == '\'') { quoted = !quoted; continue; }   // StringFormat='{0}, {1}' is one argument
            if (quoted) continue;
            if (c is '<' or '(' or '{' or '[') depth++;
            else if (c is '>' or ')' or '}' or ']') depth--;
            else if (c == sep && depth == 0) { parts.Add(s[start..i]); start = i + 1; }
        }
        parts.Add(s[start..]);
        return parts;
    }
}

/// <summary>One {Binding ...} markup extension, parsed.</summary>
public sealed record BindingExpr(string Path, string? RelativeSource, string? ElementName, string? Source)
{
    public static BindingExpr? Parse(string value)
    {
        var v = value.Trim();
        if (!v.StartsWith("{Binding", StringComparison.Ordinal) || !v.EndsWith("}", StringComparison.Ordinal)) return null;
        var inner = v["{Binding".Length..^1].Trim();
        string path = "", rel = null!, el = null!, src = null!;
        foreach (var raw in TypeModel.SplitTop(inner, ','))
        {
            var a = raw.Trim();
            if (a.Length == 0) continue;
            var eq = a.IndexOf('=');
            if (eq < 0 || a.StartsWith("(", StringComparison.Ordinal)) { path = a; continue; }
            var k = a[..eq].Trim(); var val = a[(eq + 1)..].Trim();
            switch (k)
            {
                case "Path": path = val; break;
                case "RelativeSource": rel = val; break;
                case "ElementName": el = val; break;
                case "Source": src = val; break;
            }
        }
        return new BindingExpr(path, rel, el, src);
    }
}

/// <summary>
/// Walks every view's XAML with the DataContext type each element really runs under, and resolves each binding path
/// against it. WPF reports a wrong path only as a runtime trace line, so a block moved into a view with another
/// DataContext silently shows nothing - this is the check that sees it without running the app.
/// </summary>
public sealed class BindingWalker
{
    private readonly TypeModel _types;
    public List<string> Problems { get; } = new();
    public int Checked { get; private set; }
    private readonly Dictionary<string, string?> _viewContext = new();   // view class name → its root context type
    private string _file = "";
    private string? _root;                                             // the file's UserControl / Window context
    private readonly Dictionary<string, string?> _proxies = new();

    public BindingWalker(TypeModel types) { _types = types; }

    public void Run()
    {
        var files = Repo.PanelFiles("*.xaml").Where(f => !f.EndsWith("App.xaml", StringComparison.Ordinal) && !Path.GetFileName(f).StartsWith("Theme", StringComparison.Ordinal)).ToList();
        // hosts first: MainWindow names the tab views (and their DataContext), views may host views
        var pending = new Queue<string>(files.OrderBy(f => Path.GetFileName(f) == "MainWindow.xaml" ? 0 : Path.GetFileName(f) == "Templates.xaml" ? 2 : 1));
        var passes = 0;
        while (pending.Count > 0 && passes++ < 200)
        {
            var f = pending.Dequeue();
            var doc = XDocument.Load(f, LoadOptions.SetLineInfo);
            var root = doc.Root!;
            var cls = root.Attribute(X("Class"))?.Value.Split('.').Last();
            string? ctx;
            if (root.Name.LocalName == "Window" && cls == "MainWindow") ctx = "MainViewModel";
            else if (root.Name.LocalName == "ResourceDictionary") ctx = null;
            else if (cls != null && _viewContext.TryGetValue(cls, out var vc)) ctx = vc;
            else if (cls != null && files.Any(o => o != f && File.ReadAllText(o).Contains($":{cls}", StringComparison.Ordinal)) && passes < 100)
            {
                pending.Enqueue(f);   // its host has not been walked yet
                continue;
            }
            else ctx = null;          // a window whose DataContext comes from code (PromptWindow): unknown
            _file = Repo.Rel(f);
            _root = ctx;
            _proxies.Clear();
            Walk(root, ctx);
        }
    }

    private static XName X(string local) => XName.Get(local, "http://schemas.microsoft.com/winfx/2006/xaml");

    private void Walk(XElement el, string? ctx)
    {
        var local = el.Name.LocalName;

        // resources: proxies and typed DataTemplates are checked with their own context; styles are skipped
        if (local.EndsWith(".Resources", StringComparison.Ordinal) || local == "ResourceDictionary")
        {
            foreach (var r in el.Elements())
            {
                if (r.Name.LocalName == "BindingProxy")
                {
                    var key = r.Attribute(X("Key"))?.Value;
                    var data = r.Attribute("Data")?.Value;
                    if (key != null) _proxies[key] = data != null && BindingExpr.Parse(data) is { } b ? Resolve(b, ctx, Line(r), check: true) : null;
                }
                else if (r.Name.LocalName is "DataTemplate" or "HierarchicalDataTemplate") WalkTemplate(r, ctx);
                else if (r.Name.LocalName is "ResourceDictionary.MergedDictionaries") continue;
                else if (r.Name.LocalName != "Style" && r.Name.LocalName != "ControlTemplate") Walk(r, null);
            }
            return;
        }
        if (local is "ControlTemplate" or "ItemsPanelTemplate") return;
        if (local is "DataTemplate" or "HierarchicalDataTemplate") { WalkTemplate(el, ctx); return; }

        // a hosted view: remember the context it runs under
        if (el.Name.NamespaceName.StartsWith("clr-namespace:GfPanel.Views", StringComparison.Ordinal) && local.EndsWith("View", StringComparison.Ordinal))
        {
            var dcv = el.Attribute("DataContext")?.Value;
            var vctx = dcv != null && BindingExpr.Parse(dcv) is { } vb ? Resolve(vb, ctx, Line(el), check: true) : ctx;
            _viewContext.TryAdd(local, vctx);
        }

        var dc = el.Attribute("DataContext")?.Value;
        if (dc != null) ctx = BindingExpr.Parse(dc) is { } db ? Resolve(db, ctx, Line(el), check: true) : null;

        string? itemCtx = null;
        foreach (var a in el.Attributes())
        {
            if (a.Name.LocalName == "DataContext" || a.Name.NamespaceName.Length > 0) continue;
            if (BindingExpr.Parse(a.Value) is not { } b) continue;
            var t = Resolve(b, ctx, Line(el), check: true);
            if (a.Name.LocalName == "ItemsSource") itemCtx = t == null ? null : TypeModel.ElementType(t) is var e && e != "?" ? e : null;
        }

        foreach (var c in el.Elements())
        {
            var n = c.Name.LocalName;
            if (n.EndsWith(".ItemTemplate", StringComparison.Ordinal) || n.EndsWith(".ItemContainerStyle", StringComparison.Ordinal))
            {
                foreach (var t in c.Elements())
                {
                    if (t.Name.LocalName == "Style") WalkStyle(t, itemCtx);
                    else Walk(t, itemCtx);
                }
            }
            else if (n.EndsWith(".Style", StringComparison.Ordinal))
            {
                foreach (var s in c.Elements()) WalkStyle(s, ctx);
            }
            else if (n.EndsWith(".ItemsPanel", StringComparison.Ordinal) || n.EndsWith(".Template", StringComparison.Ordinal)) { }
            else Walk(c, ctx);
        }
    }

    /// <summary>An inline style: its setters and data triggers bind against the styled element's context.</summary>
    private void WalkStyle(XElement style, string? ctx)
    {
        foreach (var e in style.Descendants())
        {
            if (e.Name.LocalName == "Setter" && e.Attribute("Value")?.Value is { } v && BindingExpr.Parse(v) is { } b) Resolve(b, ctx, Line(e), check: true);
            if (e.Name.LocalName == "DataTrigger" && e.Attribute("Binding")?.Value is { } tv && BindingExpr.Parse(tv) is { } tb) Resolve(tb, ctx, Line(e), check: true);
        }
    }

    private void WalkTemplate(XElement tpl, string? ctx)
    {
        var dt = tpl.Attribute("DataType")?.Value;
        if (dt != null)
        {
            var m = Regex.Match(dt, @"\{x:Type\s+(?:\w+:)?(\w+)\s*\}");
            ctx = m.Success ? m.Groups[1].Value : null;
        }
        foreach (var c in tpl.Elements()) Walk(c, ctx);
    }

    private static int Line(XElement e) => ((IXmlLineInfo)e).LineNumber;

    /// <summary>The type a binding produces (null = unknown), recording a problem when a path segment does not exist.</summary>
    private string? Resolve(BindingExpr b, string? ctx, int line, bool check)
    {
        if (b.ElementName != null) return null;
        var path = b.Path;
        string? start = ctx;
        if (b.Source != null)
        {
            var key = Regex.Match(b.Source, @"StaticResource\s+(\w+)").Groups[1].Value;
            if (!_proxies.TryGetValue(key, out var proxied)) return null;
            if (!path.StartsWith("Data", StringComparison.Ordinal)) return null;
            start = proxied;
            path = path.Length > 4 ? path[5..] : "";
        }
        else if (b.RelativeSource != null)
        {
            var anc = Regex.Match(b.RelativeSource, @"AncestorType=\{?(?:x:Type\s+)?(\w+)").Groups[1].Value;
            if (!path.StartsWith("DataContext", StringComparison.Ordinal)) return null;   // a framework property of the ancestor
            start = anc switch { "Window" => "MainViewModel", "UserControl" => _root, _ => null };
            path = path.Length > 11 ? path[12..] : "";
        }
        if (start == null || !_types.Knows(start)) return null;
        Checked++;
        var t = start;
        foreach (var raw in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            if (raw.StartsWith("(", StringComparison.Ordinal)) return null;   // an attached property
            var seg = Regex.Replace(raw, @"\[.*?\]", "");
            var indexed = seg.Length != raw.Length;
            if (seg is "Count" && TypeModel.IsCollection(t)) return "int";
            if (seg is "Length" && (t == "string" || t.EndsWith("[]", StringComparison.Ordinal))) return "int";
            var mt = _types.MemberType(t, seg);
            if (mt == null)
            {
                if (check) Problems.Add($"{_file}:{line} {{Binding {b.Path}}} - {t} has no '{seg}' (the element runs under {start})");
                return null;
            }
            if (mt == "?") return null;
            t = indexed ? TypeModel.ElementType(mt) : mt;
            if (t == "?" || !_types.Knows(t.Split('<')[0])) return t;
        }
        return t;
    }
}
