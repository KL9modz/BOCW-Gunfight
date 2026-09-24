using System.Diagnostics;
using System.IO;
using GfPanel.Native;
using GfPanel.Services;

namespace GfPanel.ViewModels;

/// <summary>The launch steps (the old Inject / Status tab): cwpatch in the discord slot, the bridge DLL loaded,
/// the menu payload injected (acts injectcw), then a match restart links it. Artifacts sit beside the exe
/// (the bundle) or in the repo tree when run from the dev checkout.</summary>
public sealed class InjectVM : ObservableObject
{
    private readonly MainViewModel _m;
    public string Acts { get; }
    public string BridgeDll { get; }
    public string CwpatchSrc { get; }
    public string PayloadDir { get; }
    private string _payload;
    public string Payload { get => _payload; set { if (Set(ref _payload, value)) { OnPropertyChanged(nameof(PayloadInfo)); OnPropertyChanged(nameof(PayloadIsLive)); } } }
    public string LivePayload => Path.Combine(PayloadDir, "gunfight_menu.gscc");
    /// <summary>The lobby payload (src/gunfight_lobby): the lobby's maxplayers -> the lobby slot count. Its own replace target.</summary>
    public string LobbyPayload => Path.Combine(PayloadDir, "gunfight_lobby.gscc");
    private bool _lobbyInjected;
    public bool PayloadIsLive => string.Equals(Path.GetFullPath(Payload), Path.GetFullPath(LivePayload), StringComparison.OrdinalIgnoreCase);
    public string PayloadInfo => File.Exists(Payload)
        ? $"{(PayloadIsLive ? "LIVE SLOT" : "SIDE BUILD")} · {new FileInfo(Payload).Length:N0} B · {File.GetLastWriteTime(Payload):yyyy-MM-dd HH:mm}"
        : "not found";
    public string[] Payloads => Directory.Exists(PayloadDir)
        ? Directory.GetFiles(PayloadDir, "gunfight_menu*.gscc")
            .Where(f => !f.Contains(".bak", StringComparison.OrdinalIgnoreCase) && !f.Contains("crash", StringComparison.OrdinalIgnoreCase) && !f.Contains("pre-", StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(File.GetLastWriteTime).ToArray()
        : Array.Empty<string>();
    private string _busy = "";
    public string Busy { get => _busy; set => Set(ref _busy, value); }
    public string GameText => _m.Link.GameRunning ? $"running (pid {_m.Link.Pid})" : "not running";
    public string CwpatchText
    {
        get
        {
            var dir = _m.Link.GameDir;
            if (dir == null) return "game folder not found";
            var slot = Path.Combine(dir, "discord_game_sdk.dll");
            var onDisk = Injector.Sha256(slot) == Injector.CwpatchSha256;
            if (_m.Link.GameRunning) return _m.Link.CwpatchLoaded ? "installed + loaded" : onDisk ? "installed but the STOCK SDK is loaded - relaunch the game" : "NOT installed - Install cwpatch, then relaunch";
            return onDisk ? "installed (loads at the next launch)" : File.Exists(slot) ? "NOT installed" : "slot missing";
        }
    }
    public string BridgeText => _m.Link.BridgeListening ? $"listening (seq {_m.Link.BridgeSeq})" : File.Exists(BridgeDll) ? "not loaded" : "gf_bridge.dll missing from the bundle";
    public string MenuText => _m.Link.StateFreshNow ? $"live · {_m.Link.State!.Gametype} on {_m.Link.State.Map}" : _m.Link.Players.Count > 0 ? "roster only (older payload - no GFSTATE)" : "not detected (inject, then restart the match)";
    public string LobbyText
    {
        get
        {
            var l = _m.Link.Lobby;
            if (_m.Link.LobbyFreshNow && l != null)
                return l.Ok && l.Want >= 2 ? $"live · {l.Summary} · now Custom Game Rules → change any row → back → YES; the player count should read N/{l.Want + (l.Spec == 1 ? 4 : 0)}" : "live · " + l.Summary;
            if (l != null) return "last seen in the lobby: " + l.Summary;
            if (!File.Exists(LobbyPayload)) return "payloads\\gunfight_lobby.gscc missing (build src/gunfight_lobby)";
            return _lobbyInjected ? "injected · it runs in the lobby after the next match (first run: check the lobby return)" : "not injected (Set up all, or Inject lobby payload)";
        }
    }
    public bool LobbyOk => _m.Link.LobbyFreshNow && _m.Link.Lobby is { Ok: true };
    public bool GameOk => _m.Link.GameRunning;
    public bool CwpatchOk => _m.Link.GameRunning ? _m.Link.CwpatchLoaded : CwpatchText.StartsWith("installed");
    public bool BridgeOk => _m.Link.BridgeListening;
    public bool MenuOk => _m.Link.StateFreshNow;

    public InjectVM(MainViewModel m)
    {
        _m = m;
        var b = App.BaseDir;
        // bundle layout (publish.ps1) first, then the dev tree (tools/gf-panel/GfPanel/bin/... -> repo)
        string? repo = null;
        for (var d = new DirectoryInfo(b); d != null; d = d.Parent)
            if (File.Exists(Path.Combine(d.FullName, "bootstrap.ps1")) && Directory.Exists(Path.Combine(d.FullName, "tools"))) { repo = d.FullName; break; }
        Acts = FirstExisting(Path.Combine(b, "acts", "acts.exe"), repo == null ? "" : Path.Combine(repo, "..", "ACTS", "bin", "acts.exe"));
        BridgeDll = FirstExisting(Path.Combine(b, "gf-bridge", "gf_bridge.dll"), repo == null ? "" : Path.Combine(repo, "tools", "gf-bridge", "gf_bridge.dll"));
        CwpatchSrc = FirstExisting(Path.Combine(b, "vendor", "discord_game_sdk.CWPATCH-13824.dll"), repo == null ? "" : Path.Combine(repo, "..", "vendor-backup", "discord_game_sdk.CWPATCH-13824.dll"));
        // payloads: on the dev box the REAL slot folder beside the repo (peers swap builds into it under
        // klaze's standing order - the bundle's copy would be a stale snapshot); a friend's bundle has no
        // repo above it and uses its own payloads\
        var repoPayloads = repo == null ? null : Path.GetFullPath(Path.Combine(repo, "..", "payloads"));
        PayloadDir = repoPayloads != null && Directory.Exists(repoPayloads) ? repoPayloads : Path.Combine(b, "payloads");
        // default = the LIVE slot gunfight_menu.gscc - the one build in play. A side build (.panel/.props/
        // .race...) is an explicit pick, never the default, however new it is.
        _payload = File.Exists(LivePayload) ? LivePayload : Payloads.FirstOrDefault() ?? LivePayload;
        m.Link.StatusChanged += Refresh;
    }

    private static string FirstExisting(params string[] paths) => paths.FirstOrDefault(p => p.Length > 0 && File.Exists(p)) ?? paths[0];

    public void Refresh()
    {
        foreach (var n in new[] { nameof(GameText), nameof(CwpatchText), nameof(BridgeText), nameof(MenuText), nameof(GameOk), nameof(CwpatchOk), nameof(BridgeOk), nameof(MenuOk), nameof(LobbyText), nameof(LobbyOk) })
            OnPropertyChanged(n);
    }

    public RelayCommand SetupAll => new(async () =>
    {
        var lobby = _m.Prefs.InjectLobby && File.Exists(LobbyPayload);
        if (!_m.Confirm("Set up all: install cwpatch (if needed), load the bridge DLL, inject the menu payload" + (lobby ? " + the lobby payload (lobby slot count)" : "") + ".\n\ncwpatch is read at game start, so the first time you relaunch once. After the menu injects, restart the match to link it." + (lobby ? "\n\nThe lobby payload is a NEW injection pair (load_shared + containers_shared): on its first run, check that leaving the match back to the lobby works." : ""))) return;
        var pid = _m.Link.Pid;
        var dir = _m.Link.GameDir;
        if (dir != null && Injector.Sha256(Path.Combine(dir, "discord_game_sdk.dll")) != Injector.CwpatchSha256)
        {
            _m.Link.Log("cwpatch: " + Injector.InstallCwpatch(CwpatchSrc, dir, pid > 0), LogLevel.Warn);
            _m.Link.Log(pid > 0 ? "  -> close the game, relaunch it, then Set up all again" : "  -> now LAUNCH the game, then Set up all again", LogLevel.Warn);
            Refresh(); return;
        }
        if (pid == 0) { _m.Link.Log("cwpatch is in place - LAUNCH the game, then Set up all", LogLevel.Warn); return; }
        if (_m.Link.BridgeListening) _m.Link.Log("bridge already loaded - keeping it", LogLevel.Info);
        else _m.Link.Log(Injector.InjectDll(pid, BridgeDll), LogLevel.Ok);
        await InjectMenu();
        if (lobby) await InjectLobby();
    });

    public RelayCommand InjectLobbyCmd => new(async () =>
    {
        if (!File.Exists(LobbyPayload)) { _m.Toasts.Show("payloads\\gunfight_lobby.gscc is missing - build src/gunfight_lobby", LogLevel.Warn); return; }
        if (!_m.Confirm("Inject the LOBBY payload (gunfight_lobby.gscc) into the running game?\n\nIt writes the lobby's max players (Lobby max players, default 12) so the pregame lobby seats 6v6 + spectators. It hooks load_shared.gsc with its own replace target (containers_shared.gsc), so it sits beside the menu payload.\n\n⚠ New injection pair: on its first run, check that leaving a match back to the lobby works, then a lobby → match → lobby cycle.")) return;
        await InjectLobby();
    });

    private async Task InjectLobby()
    {
        Busy = "injecting the lobby payload...";
        var (ok, output) = await Injector.ActsInjectAsync(Acts, LobbyPayload, Injector.LobbyHook, Injector.LobbyReplace);
        Busy = "";
        ok = ok && output.Contains("injected at", StringComparison.OrdinalIgnoreCase);
        foreach (var line in output.Split('\n').TakeLast(4)) _m.Link.Log("  " + line.Trim(), ok ? LogLevel.Info : LogLevel.Err);
        if (output.Contains("find replaced script", StringComparison.OrdinalIgnoreCase))
            _m.Link.Log("  -> containers_shared.gsc is not in the script pool yet: load a private match once, then inject again", LogLevel.Warn);
        _lobbyInjected = ok;
        _m.Link.Log(ok ? "lobby payload injected - it runs in the lobby after the next match; then Custom Game Rules → change any row → back → YES"
                       : "lobby payload inject failed", ok ? LogLevel.Ok : LogLevel.Err);
        _m.Toasts.Show(ok ? "Lobby payload injected - first run: check the lobby return" : "Lobby payload inject failed - see the activity log", ok ? LogLevel.Ok : LogLevel.Err);
        Refresh();
    }

    public RelayCommand InjectMenuCmd => new(async () =>
    {
        if (!_m.Confirm($"Inject {Path.GetFileName(Payload)} ({(PayloadIsLive ? "the LIVE slot" : "a SIDE build")}) into the running game?\n\nOne payload per game launch. Restart the match afterwards to link it.")) return;
        await InjectMenu();
    });

    private async Task InjectMenu()
    {
        Busy = "injecting the menu...";
        var (ok, output) = await Injector.ActsInjectAsync(Acts, Payload);
        Busy = "";
        foreach (var line in output.Split('\n').TakeLast(6)) _m.Link.Log("  " + line.Trim(), ok ? LogLevel.Info : LogLevel.Err);
        if (output.Contains("find target script", StringComparison.OrdinalIgnoreCase))
            _m.Link.Log("  -> load a private MATCH once first (puts bb.gsc in the pool), then inject", LogLevel.Warn);
        _m.Link.Log(ok ? "menu injected - restart the match (F7 / Restart match) to link it" : "menu inject failed", ok ? LogLevel.Ok : LogLevel.Err);
        _m.Toasts.Show(ok ? "Menu injected - restart the match to link it" : "Menu inject failed - see the activity log", ok ? LogLevel.Ok : LogLevel.Err);
        Refresh();
    }

    public RelayCommand InjectBridge => new(() =>
    {
        if (_m.Link.Pid == 0) { _m.Toasts.Show("Launch the game first", LogLevel.Warn); return; }
        if (_m.Link.BridgeListening) { _m.Toasts.Show("A bridge DLL is already loaded (re-injecting would double-load it) - relaunch the game to load a different build", LogLevel.Warn); return; }
        if (!_m.Confirm("Inject the prebuilt gf_bridge.dll into the running game?")) return;
        _m.Link.Log(Injector.InjectDll(_m.Link.Pid, BridgeDll), LogLevel.Ok);
        Refresh();
    });

    public RelayCommand InstallCwpatch => new(() =>
    {
        var msg = Injector.InstallCwpatch(CwpatchSrc, _m.Link.GameDir ?? GameProcess.FindGameDir(0), _m.Link.GameRunning);
        _m.Link.Log("cwpatch: " + msg, LogLevel.Warn);
        if (_m.Link.GameRunning && !msg.Contains("already")) _m.Link.Log("  -> close the game, click again, then relaunch (cwpatch loads at start)", LogLevel.Warn);
        Refresh();
    });

    public RelayCommand UseLive => new(() => Payload = LivePayload);

    public RelayCommand PickPayload => new(() =>
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Filter = "GSC payload (*.gscc)|*.gscc", InitialDirectory = PayloadDir, FileName = Path.GetFileName(Payload) };
        if (dlg.ShowDialog() == true) Payload = dlg.FileName;
    });

    public RelayCommand OpenDataDir => new(() => Process.Start(new ProcessStartInfo("explorer.exe", App.DataDir) { UseShellExecute = true }));
    public RelayCommand OpenBundleDir => new(() => Process.Start(new ProcessStartInfo("explorer.exe", App.BaseDir) { UseShellExecute = true }));
}
