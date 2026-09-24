using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace GfPanel.Tests;

/// <summary>
/// The panel's user-facing surface, as a list the redesign must keep reachable (klaze 2026-09-24: "without losing
/// any functionality (only gaining it)"). ui-surface.txt (next to this project) holds one key per thing a user can
/// do from a view:
///   cmd:&lt;Command&gt; [&lt;parameter&gt;]   a button / menu item / key binding (the parameter when it is a literal)
///   set:&lt;Property&gt;                 an input bound two-way (a toggle, a picker, a slider, a text box)
///   click:&lt;Handler&gt;                a code-behind click handler
/// Keys use the LAST segment of a binding path, so moving a control to another view or DataContext keeps its key;
/// renaming a command or property changes it, and then this file changes in the same commit - the diff of
/// ui-surface.txt IS the record of what moved. Regenerate after an intended change:
///   dotnet run --project tools\gf-panel\GfPanel.Tests -- --write-ui-surface
/// </summary>
public static class UiSurfaceTests
{
    public static string BaselinePath => Repo.At("tools", "gf-panel", "GfPanel.Tests", "ui-surface.txt");

    private static readonly Regex BindingPath = new(@"\{Binding\s+(?:Path=)?([\w.\[\]]+)");

    private static readonly Dictionary<string, string[]> InputProps = new()
    {
        ["IsChecked"] = new[] { "CheckBox", "ToggleButton", "RadioButton", "MenuItem" },
        ["SelectedItem"] = new[] { "ComboBox", "ListBox", "ListView", "DataGrid", "TabControl" },
        ["SelectedValue"] = new[] { "ComboBox", "ListBox", "ListView" },
        ["SelectedIndex"] = new[] { "ComboBox", "ListBox", "ListView", "TabControl" },
        ["Value"] = new[] { "Slider" },
        ["Text"] = new[] { "TextBox", "ComboBox" },
    };

    private static string Last(string path) => path.Split('.').Last();

    /// <summary>Every key the XAML exposes now, with where each one is (first place seen).</summary>
    public static SortedDictionary<string, string> Surface()
    {
        var keys = new SortedDictionary<string, string>(StringComparer.Ordinal);
        void Add(string key, string where) { if (!keys.ContainsKey(key)) keys[key] = where; }
        foreach (var file in Repo.PanelFiles("*.xaml"))
        {
            var doc = XDocument.Load(file, LoadOptions.SetLineInfo);
            foreach (var el in doc.Descendants())
            {
                var where = $"{Repo.Rel(file)}:{((System.Xml.IXmlLineInfo)el).LineNumber}";
                var cmd = el.Attribute("Command")?.Value;
                if (cmd != null && BindingPath.Match(cmd) is { Success: true } cm)
                {
                    var key = "cmd:" + Last(cm.Groups[1].Value);
                    var par = el.Attribute("CommandParameter")?.Value;
                    if (par != null)
                        key += par.StartsWith("{", StringComparison.Ordinal)
                            ? (BindingPath.Match(par) is { Success: true } pm ? " {" + Last(pm.Groups[1].Value) + "}" : " {" + par.Trim('{', '}').Split(' ')[0] + "}")
                            : " " + par;
                    Add(key, where);
                }
                foreach (var (prop, types) in InputProps)
                {
                    var v = el.Attribute(prop)?.Value;
                    if (v == null || !types.Contains(el.Name.LocalName) || BindingPath.Match(v) is not { Success: true } bm) continue;
                    if (Regex.IsMatch(v, @"Mode\s*=\s*OneWay\b")) continue;
                    Add("set:" + Last(bm.Groups[1].Value), where);
                }
                // a command set through a style: <Setter Property="Command" Value="{Binding Go}" />
                if (el.Name.LocalName == "Setter" && el.Attribute("Property")?.Value == "Command" &&
                    BindingPath.Match(el.Attribute("Value")?.Value ?? "") is { Success: true } sm)
                    Add("cmd:" + Last(sm.Groups[1].Value), where);
                var click = el.Attribute("Click")?.Value;
                if (click != null) Add("click:" + click, where);
            }
        }
        return keys;
    }

    /// <summary>RelayCommands a view model declares that nothing binds or calls: features the UI does not offer.</summary>
    public static List<string> UnboundCommands()
    {
        var bound = Surface().Keys.Where(k => k.StartsWith("cmd:", StringComparison.Ordinal)).Select(k => k[4..].Split(' ')[0]).ToHashSet();
        var cs = Repo.PanelFiles("*.cs").Select(f => (File: f, Text: File.ReadAllText(f))).ToList();
        var list = new List<string>();
        foreach (var (file, text) in cs.Where(c => c.File.Contains($"{Path.DirectorySeparatorChar}ViewModels{Path.DirectorySeparatorChar}")))
        {
            foreach (Match m in Regex.Matches(text, @"public\s+RelayCommand\s+(\w+)"))
            {
                var name = m.Groups[1].Value;
                if (bound.Contains(name)) continue;
                var used = cs.Any(c => Regex.Matches(c.Text, @"\b" + name + @"\b").Count > (c.File == file ? 1 : 0));
                if (!used) list.Add($"{Path.GetFileNameWithoutExtension(file)}.{name}");
            }
        }
        return list;
    }

    public static IEnumerable<string> BaselineKeys() =>
        File.Exists(BaselinePath)
            ? File.ReadLines(BaselinePath).Select(l => l.Trim()).Where(l => l.Length > 0 && !l.StartsWith("#", StringComparison.Ordinal))
            : Enumerable.Empty<string>();

    public static void WriteBaseline()
    {
        var s = Surface();
        var lines = new List<string>
        {
            "# Everything a user can do from the panel's views - kept reachable through the redesign (UiSurfaceTests).",
            "# cmd:<Command> [<literal parameter>|{<bound parameter>}]  ·  set:<two-way input property>  ·  click:<handler>",
            "# Regenerate after an INTENDED change:  dotnet run --project tools/gf-panel/GfPanel.Tests -- --write-ui-surface",
            $"# {s.Count} keys.",
        };
        lines.AddRange(s.Keys);
        File.WriteAllLines(BaselinePath, lines);
        Console.WriteLine($"wrote {s.Count} keys to {Repo.Rel(BaselinePath)}");
        var dead = UnboundCommands();
        if (dead.Count > 0)
            Console.WriteLine($"{dead.Count} view-model commands nothing binds or calls:\n  " + string.Join("\n  ", dead));
    }

    [Test]
    public static void Nothing_the_panel_offered_has_become_unreachable()
    {
        var baseline = BaselineKeys().ToList();
        Check.True(baseline.Count > 200, $"{Repo.Rel(BaselinePath)} holds only {baseline.Count} keys - regenerate it (--write-ui-surface)");
        var now = Surface();
        var p = new Problems();
        foreach (var k in baseline.Where(k => !now.ContainsKey(k))) p.Add(k);
        p.ThrowIfAny("keys in ui-surface.txt no view offers any more (moved or renamed: regenerate the file in the same change so the diff shows it; removed: say why in the commit)");
    }

    [Test]
    public static void Every_binding_names_a_member_some_view_model_has()
    {
        // WPF drops a binding to a missing property silently: the control just shows nothing / does nothing.
        var members = new HashSet<string>(StringComparer.Ordinal);
        foreach (var f in Repo.PanelFiles("*.cs"))
            foreach (Match m in Regex.Matches(File.ReadAllText(f), @"\bpublic\s+(?:static\s+)?(?:readonly\s+)?(?:override\s+)?[\w<>\[\],.?() ]+?\s+(\w+)\s*(?:=>|\{|=|;)"))
                members.Add(m.Groups[1].Value);
        // positional record parameters are public properties too: record TpTargetVM(string Name, RelayCommand Go)
        foreach (var f in Repo.PanelFiles("*.cs"))
            foreach (Match m in Regex.Matches(File.ReadAllText(f), @"\brecord\s+\w+\s*\(([^)]*)\)"))
                foreach (var param in m.Groups[1].Value.Split(','))
                    if (Regex.Match(param.Trim(), @"(\w+)\s*(?:=.*)?$") is { Success: true } pm) members.Add(pm.Groups[1].Value);
        foreach (var t in new[] { typeof(GfPanel.Game.GfPlayer), typeof(GfPanel.Game.GfEntity), typeof(GfPanel.Game.MenuAction), typeof(GfPanel.Game.SpawnEvent),
                                  typeof(GfPanel.Game.Named), typeof(GfPanel.Game.VehicleDef), typeof(GfPanel.Game.MapDef), typeof(GfPanel.Game.SettingDef),
                                  typeof(GfPanel.Game.SectionDef), typeof(GfPanel.Game.Choice), typeof(GfPanel.Game.ColorDef), typeof(GfPanel.Game.PerkDef),
                                  typeof(GfPanel.Game.DurDef), typeof(GfPanel.Services.LogEntry) })
            foreach (var pr in t.GetProperties()) members.Add(pr.Name);
        // framework members bindings commonly reach (RelativeSource / ElementName / collection views)
        foreach (var fw in new[] { "DataContext", "Count", "Length", "Name", "Content", "IsSelected", "IsMouseOver", "ActualWidth", "ActualHeight", "Items", "Tag", "Header", "Text", "Value", "Key", "Item1", "Item2", "Model", "Size", "Title", "PlacementTarget", "IsEnabled", "Visibility", "IsChecked", "SelectedItem", "Width", "Height", "IsDropDownOpen", "Foreground" })
            members.Add(fw);

        var p = new Problems();
        foreach (var file in Repo.PanelFiles("*.xaml"))
        {
            var lines = File.ReadAllLines(file);
            for (var i = 0; i < lines.Length; i++)
                foreach (Match m in BindingPath.Matches(lines[i]))
                    foreach (var seg in m.Groups[1].Value.Split('.').Select(s => Regex.Replace(s, @"\[.*?\]", "")).Where(s => s.Length > 0 && !char.IsDigit(s[0])))
                        if (!members.Contains(seg)) p.Add($"{Repo.Rel(file)}:{i + 1} {{Binding {m.Groups[1].Value}}} - no public member named '{seg}'");
        }
        p.ThrowIfAny("bindings to nothing");
    }
}
