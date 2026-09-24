using GfPanel.Game;

namespace GfPanel.Tests;

/// <summary>The write channel: every `set` line goes through a 47-byte bridge slot (a longer one overflows
/// cwpatch's slot and hard-crashes the game - the sender refuses it, so an oversized line is a button that
/// silently does nothing). And a line break in any printed string closes the match.</summary>
public static class CommandTests
{
    private const int Slot = 47;

    private static void Fits(Problems p, string line, string what)
    {
        var n = Commands.ByteLength(line);
        if (n > Slot) p.Add($"{what}: {n} bytes > {Slot}: {line}");
    }

    /// <summary>The widest values a setting can hold: its limits, default and every choice.</summary>
    private static IEnumerable<int> Candidates(SettingDef d) =>
        new[] { d.Min, d.Max, d.Default }.Concat(d.Choices?.Select(c => c.Value) ?? Enumerable.Empty<int>())
                                         .Concat(d.Kind == SettingKind.Toggle ? new[] { 0, 1 } : Array.Empty<int>());

    private static int Widest(SettingDef d) => Candidates(d).OrderByDescending(v => v.ToString().Length).First();

    [Test]
    public static void Every_plain_setting_write_fits_the_slot()
    {
        var p = new Problems();
        foreach (var d in Schema.All.Where(d => !d.IsPacked && Packing.BotIndexOf(d.Dvar) < 0))
            foreach (var v in Candidates(d))
                Fits(p, Commands.Set(d.Dvar, v), d.Dvar);
        p.ThrowIfAny("plain dvar writes");
    }

    [Test]
    public static void Packed_chunks_and_bot_lines_fit_the_slot_at_their_widest()
    {
        var widest = Schema.All.ToDictionary(d => d.Dvar, Widest);
        var p = new Problems();
        for (var c = 0; c < Packing.ChunkCount; c++) Fits(p, Packing.ChunkLine(c, widest), $"gf_c{c}");
        foreach (var line in Packing.BotLines(widest)) Fits(p, line, "bot line");
        p.ThrowIfAny("packed writes");
    }

    [Test]
    public static void Say_lines_fit_the_slot_whatever_is_typed()
    {
        var p = new Problems();
        var text = new string('W', 200);
        var who = new string('N', 60);
        foreach (var loc in new[] { 0, 1, 2 })
            foreach (var line in Commands.Say(text, loc, 60, 99, who))
                Fits(p, line, $"say loc {loc}");
        p.ThrowIfAny("say");
    }

    [Test]
    public static void Action_lines_fit_the_slot_whatever_the_target_or_argument()
    {
        var p = new Problems();
        foreach (var line in Commands.Action("restartround", new string('9', 200), new string('T', 60)))
            Fits(p, line, "action");
        foreach (var line in Commands.Fire(Commands.Action("fillbots"), 9_999_999_999L))
            Fits(p, line, "fire");
        p.ThrowIfAny("action");
    }

    [Test]
    public static void Every_verb_the_panel_sends_fits_the_slot()
    {
        var p = new Problems();
        foreach (var v in Panel.Verbs().Verbs.Select(s => s.Verb).Distinct())
            foreach (var line in Commands.Action(v))
                Fits(p, line, "verb " + v);
        p.ThrowIfAny("verbs");
    }

    [Test]
    public static void Switch_lines_fit_the_slot_for_every_catalog_map_and_mode()
    {
        var p = new Problems();
        var map = Catalog.Maps.Select(m => m.Id).OrderByDescending(s => s.Length).First();
        var gt = Catalog.Gametypes.Select(g => g.Value).Concat(Catalog.Maps.Where(m => m.Gametype != null).Select(m => m.Gametype!))
                                  .OrderByDescending(s => s.Length).First();
        foreach (var line in Commands.Switch(map, gt, stage: true)) Fits(p, line, "switch");
        p.ThrowIfAny("switch");
    }

    [Test]
    public static void Free_text_loses_line_breaks_quotes_and_separators()
    {
        Check.Equal("ab cd", Commands.Clean("a\nb\r \"c;d\\\t", 30), "Clean");
        Check.Equal("12345", Commands.Clean("1234567", 5), "Clean caps the length");
        Check.Equal("tab", Commands.Clean("\u0001t\u007faéb", 30), "control, DEL and non-ASCII characters go");
    }

    /// <summary>A built-in preset longer than a say line is cut mid-sentence in game (the composer shows a negative
    /// count, the preset list does not).</summary>
    [Test]
    public static void Built_in_message_presets_fit_one_say_line()
    {
        var p = new Problems();
        foreach (var m in Catalog.MessagePresets)
        {
            var sent = Commands.Clean(m.Value, int.MaxValue);
            if (sent.Length > Commands.MaxSayChars) p.Add($"\"{m.Label}\": {sent.Length} chars > {Commands.MaxSayChars}: {m.Value}");
        }
        p.ThrowIfAny("message presets");
    }
}
