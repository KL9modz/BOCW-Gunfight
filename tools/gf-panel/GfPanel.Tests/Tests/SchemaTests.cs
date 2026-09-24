using System.Text.RegularExpressions;
using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>Game/Schema.cs - every host setting row - against itself and against the GSC that reads it.</summary>
public static class SchemaTests
{
    [Test]
    public static void Dvar_names_are_unique()
    {
        // Schema.ByDvar is a ToDictionary: a duplicate would throw in the type initializer and take the app down at start
        var dup = Schema.Sections.SelectMany(s => s.Rows).GroupBy(r => r.Dvar).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
        Check.True(dup.Count == 0, "duplicate dvars: " + string.Join(", ", dup));
    }

    [Test]
    public static void Defaults_are_values_the_control_can_show()
    {
        var p = new Problems();
        foreach (var d in Schema.All)
        {
            switch (d.Kind)
            {
                case SettingKind.Choice when d.Choices == null || d.Choices.Length == 0:
                    p.Add($"{d.Dvar}: a Choice row with no choices");
                    break;
                case SettingKind.Choice when d.Choices!.All(c => c.Value != d.Default):
                    p.Add($"{d.Dvar}: default {d.Default} is not one of its choices ({string.Join(", ", d.Choices!.Select(c => c.Value))})");
                    break;
                case SettingKind.Toggle when d.Default is not (0 or 1):
                    p.Add($"{d.Dvar}: toggle default {d.Default}");
                    break;
                case SettingKind.Int when d.Default < d.Min || d.Default > d.Max:
                    p.Add($"{d.Dvar}: default {d.Default} outside {d.Min}..{d.Max}");
                    break;
                case SettingKind.Int when d.Step > 0 && (d.Default - d.Min) % d.Step != 0:
                    p.Add($"{d.Dvar}: default {d.Default} is off the {d.Step} step from {d.Min}");
                    break;
            }
            if (d.Choices != null && d.Choices.GroupBy(c => c.Value).Any(g => g.Count() > 1))
                p.Add($"{d.Dvar}: two choices share a value");
        }
        p.ThrowIfAny("schema rows");
    }

    [Test]
    public static void Sections_sit_on_tabs_the_panel_renders()
    {
        var known = new[] { "dashboard", "advanced", "tools", "spawns" };
        var p = new Problems();
        foreach (var s in Schema.Sections.Where(s => !known.Contains(s.Tab))) p.Add($"section \"{s.Title}\" is on tab \"{s.Tab}\"");
        // and the panel really asks for each of those tabs somewhere
        var src = string.Join("\n", Repo.PanelFiles("*.cs").Where(f => !f.EndsWith("Schema.cs", StringComparison.Ordinal)).Select(File.ReadAllText));
        foreach (var tab in Schema.Sections.Select(s => s.Tab).Distinct())
            if (!Regex.IsMatch(src, @"Tab\s*==\s*""" + tab + @"""|""" + tab + @"""\s*==\s*\w+\.Tab|Sections\w*\(\s*""" + tab + @""""))
                p.Add($"no code selects the \"{tab}\" sections (Tab == \"{tab}\") - they would never show");
        p.ThrowIfAny("section tabs");
    }

    /// <summary>A setting no GSC reads is a control that does nothing.</summary>
    [Test]
    public static void Every_setting_is_read_by_the_gsc()
    {
        var code = GscSource.Menu.AllCode + "\n" + GscSource.Lobby.AllCode;
        var p = new Problems();
        foreach (var d in Schema.All)
        {
            // the 15 bot knobs travel packed in gf_bot / gf_bot2 (Bot_knobs_are_in_the_gsc_writers_order... checks the cells)
            var dvar = Packing.BotIndexOf(d.Dvar) switch { < 0 => d.Dvar, < 8 => "gf_bot", _ => "gf_bot2" };
            if (!code.Contains($"#\"{dvar}\"", StringComparison.Ordinal) && !code.Contains($"\"{dvar}\"", StringComparison.Ordinal))
                p.Add($"{d.Dvar} (\"{d.Label}\") appears nowhere in gunfight_menu.gsc or gunfight_lobby.gsc");
        }
        p.ThrowIfAny("settings the game never reads");
    }

    /// <summary>The panel's idea of a setting's default is what it shows before the game answers and what an empty
    /// cell resolves to; it must be the default the GSC actually runs with.</summary>
    [Test]
    public static void Unpacked_defaults_match_the_gsc_readers()
    {
        var readers = Gsc.ReaderDefaults();
        var p = new Problems();
        foreach (var d in Schema.All.Where(d => !d.IsPacked && Packing.BotIndexOf(d.Dvar) < 0))
        {
            if (!readers.TryGetValue(d.Dvar, out var reads)) continue;   // read another way (string / packed pair) - not checked here
            var gsc = reads.Select(r => r.Default).Distinct().ToList();
            if (!gsc.Contains(d.Default))
                p.Add($"{d.Dvar}: Schema default {d.Default}, the GSC reads it with {string.Join(" / ", reads.Select(r => $"{r.Default} ({r.Where})"))}");
        }
        p.ThrowIfAny("defaults");
    }

    /// <summary>Two GSC reads of one dvar with different defaults behave differently while the dvar is unset -
    /// e.g. the config readback reporting ON for a feature the code runs OFF.</summary>
    [Test]
    public static void Gsc_reads_of_a_setting_agree_on_its_default()
    {
        var packed = Packing.Packed.ToHashSet();   // cfg_geti ignores its default for a packed key (cfg_spec's wins)
        var p = new Problems();
        foreach (var (dvar, reads) in Gsc.ReaderDefaults().Where(kv => !packed.Contains(kv.Key)).OrderBy(kv => kv.Key))
            if (reads.Select(r => r.Default).Distinct().Count() > 1)
                p.Add($"{dvar}: " + string.Join(", ", reads.GroupBy(r => r.Default).Select(g => $"{g.Key} at {string.Join(" ", g.Select(r => r.Where))}")));
        p.ThrowIfAny("GSC reads with different defaults");
    }
}
