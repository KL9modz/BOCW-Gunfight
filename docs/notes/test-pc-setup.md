# Test PC — headless closet box, driven over RDP

**Conclusion up front.** The test box is a headless Windows **Pro** machine in a closet, reached by
RDP from the dev PC over the LAN. RDP is the *only* display path. That is a deliberate trade: it
covers Phase 0/1 menu work and the injector comfortably, and it is the weak link for Phase 2, which
needs real framerate and working audio. The risk is gated by one cheap test (Step 3) before anything
expensive is built on top of it.

## Decisions taken

| Question | Answer | Consequence |
|---|---|---|
| Machine | already built, Windows running | start at RDP enablement, not OS install |
| Display path | **RDP only** | no Sunshine / Parsec / capture card. Step 3 is the gate |
| Toolchain | mirrored on both machines, synced by git | the repo **must** sit beside `ACTS\` and `bocw-source-main\` |
| Game copy | new Battle.net copy, throwaway account | separate purchase — and it needs a separate **Activision** account too |

⚠ Streaming hosts were considered and declined, not overlooked. Recording why so it is not
re-litigated: `.claude/CLAUDE.md` records that TAC detects API hooks and overlays. Capture that works
by injecting an overlay into the game process is that exact shape. Capture via the Desktop
Duplication API sits outside the process and does not hook it. **If Step 3 fails, Sunshine is the
fallback to reach for — not Steam Remote Play**, whose capture rides the Steam overlay hook.
`UNVERIFIED` — nobody outside Activision can confirm what TAC actually scores; the asymmetry is just
free to avoid.

---

## Step 0 — inventory

```powershell
Get-ComputerInfo -Property WindowsProductName,WindowsVersion,CsName,CsTotalPhysicalMemory | Format-List
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM
Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter,FileSystemLabel,
    @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}
Get-NetIPConfiguration | Where-Object IPv4Address | Select-Object InterfaceAlias,IPv4Address,
    @{n='LinkSpeed';e={(Get-NetAdapter $_.InterfaceAlias).LinkSpeed}}
```

Two hard gates in that output:

- **`WindowsProductName` must not say Home.** Home cannot host RDP — the service is absent, no
  registry flip adds it. Pro / Enterprise / Education only.
- **`LinkSpeed` should be 1 Gbps wired, both ends.** RDP to a game over Wi-Fi is not usable.

Budget **~150 GB** free for MP + Zombies.

---

## Step 1 — reachability

```powershell
# RDP on, NLA left enabled
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
    -Name UserAuthentication -Value 1
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

# Scope to the LAN. Do not skip.
Set-NetFirewallRule -DisplayGroup 'Remote Desktop' -RemoteAddress LocalSubnet

# Never sleep, never hibernate, no fast startup
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /hibernate off

# SSH server — saves a lot of RDP round-trips later
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
```

🛑 **Never port-forward 3389.** Exposed RDP is the most-exploited remote entry point on Windows. The
`LocalSubnet` scope above is what keeps this a closet box. If it ever needs to be reachable from
outside, use Tailscale or WireGuard, never a port forward.

At the closet itself:

- **DHCP reservation** on the router, keyed to the MAC. Beats a static IP — it survives a Windows
  reinstall.
- **BIOS: restore on AC power loss → Power On**, plus Wake-on-LAN if the board has it. A headless box
  that stays dark after a power blip is a trip to the closet.
- **HDMI/DP dummy plug** (~$8). Some GPU drivers will not fully initialise with zero displays
  attached, and it leaves a real console session to fall back on if RDP ever wedges.

Auto-logon is **not** needed — you authenticate through RDP itself. One less credential in the
registry.

---

## Step 2 — wring what you can out of RDP

Defaults cap at 30 fps and never touch the dGPU.

```powershell
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item -Path $ts -Force | Out-Null
Set-ItemProperty $ts -Name bEnumerateHWBeforeSW       -Value 1 -Type DWord  # use the real GPU
Set-ItemProperty $ts -Name AVC444ModePreferred        -Value 1 -Type DWord
Set-ItemProperty $ts -Name AVCHardwareEncodePreferred -Value 1 -Type DWord  # NVENC/AMF the stream

# 30fps -> ~60fps
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\WinStations\RDP-Tcp' `
    -Name DWMFRAMEINTERVAL -Value 15 -Type DWord

Restart-Computer
```

In `gpedit.msc`, under *Computer Config → Administrative Templates → Windows Components → Remote
Desktop Services → Remote Desktop Session Host → **Remote Session Environment***:

- **Configure image quality for RemoteFX Adaptive Graphics** → High
- **Configure compression for RemoteFX data** → *Do not use an RDP compression algorithm* (LAN —
  compression is spending latency to save bandwidth you already have)

Client side in `mstsc`: full screen, 32-bit colour, Experience → **LAN (10 Mbps or higher)**. Leave
audio on *Play on this computer*; Phase 2's announcer-VO checks depend on it.

---

## Step 3 — the gate ⚠

Do this **before** mirroring the toolchain. It can invalidate the display decision, and it is cheap.

Install Battle.net and BOCW, RDP in, launch the game. Three questions:

1. **Does it launch under RDP at all?** `UNVERIFIED` — CoD titles have a mixed record here.
2. **Is it watchable?** Set the game to **borderless windowed** (exclusive fullscreen and RDP fight),
   drop to 1280×720, cap the framerate. RDP encodes what it renders, so lower internal resolution is
   a direct latency win.
3. **Is audio audible over the session?** Half of Phase 2 is music, VO, and HUD cues.

If it fails, the dummy plug from Step 1 plus Sunshine is the fallback. Revisit before proceeding.

---

## Step 4 — accounts ⚠ the part that is easy to get wrong

`.claude/CLAUDE.md` says "throwaway Battle.net account". That is necessary and **not sufficient**.

**BOCW bans land on the Activision account, not the Battle.net one.** The Activision ID is the
cross-platform identity linking every CoD you own. Link a fresh Battle.net account to your *existing*
Activision ID at first launch and a ban propagates to your main CoD identity on every platform — and
you would have bought a second copy to achieve nothing.

So: **new Battle.net account AND a new Activision account**, linked only to each other. The prompt
appears at BOCW's first launch and will happily attach to whatever you are already signed into.
**This is the step that actually delivers the blast-radius reduction the platform decision was made
for.** Battle.net licences are account-bound, so a Steam copy cannot be moved across.

---

## Step 5 — toolchain mirror

🛑 **Do not sign OneDrive into the closet box.** OneDrive and git both syncing the same `.git` across
two machines corrupts repos. Git is the sync mechanism here; pick one.

Target layout — **`ACTS\` and `bocw-source-main\` sit BESIDE the repo, never inside it**, because
`tools/check-gsc.ps1` resolves them via `$PSScriptRoot\..\..`:

```
C:\bocw\
├── ACTS\                 60 MB   compiler + injector
├── bocw-source-main\    664 MB   decompiled T9 dump  (see the size check below)
└── BOCW-Gunfight\                this repo
    ├── src\gunfight_tweaks.gsc
    └── tools\check-gsc.ps1
```

```powershell
mkdir C:\bocw ; cd C:\bocw
git clone https://github.com/KL9modz/BOCW-Gunfight.git
git clone --depth 1 https://github.com/ate47/bocw-source.git bocw-source-main
# ACTS: copy from the dev PC over RDP drive redirection (see the version pin below)
```

`atian-cod-tools-3.1.0\` (18 MB) is reading reference only. It does not need to travel.

Verify, rather than assuming:

```powershell
Test-Path C:\bocw\bocw-source-main\scripts\mp_common\gametypes\gunfight.gsc   # must be True
Get-Content C:\bocw\ACTS\bin\version                                          # must match the dev PC
cd C:\bocw\BOCW-Gunfight ; .\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc    # must print PASS
```

---

## Step 6 — resolve the injector conflict

The two notes files disagree, and the closet box is where it gets settled:

- `Cold War/.claude/toolchain.md` → **ACTS `injectcw`**, hook/replaced argument pair already worked
  out, magic bytes VERIFIED
- `BOCW-Gunfight/.claude/CLAUDE.md` → **AuroraDoesCode/t7-compiler-custom**, branch `dev_csc_inj`

Install both — they are small — and let the hello-world decide. ACTS is the better-documented path in
these notes, so start there.

`injectcw` aborts instantly if `BlackOpsColdWar.exe` is not running, and per `cw.cpp:506` it patches a
`scriptparsetree` pool entry, so timing relative to script *link* is the open question. The SSH server
from Step 1 lets you fire the inject from the dev PC while the game holds focus in the RDP session,
instead of alt-tabbing inside it. `UNVERIFIED` whether cross-session `OpenProcess` behaves — run the
SSH session elevated, and fall back to a second window inside RDP if not.

---

## Gotchas found while writing this — all VERIFIED on the dev PC

**1. ACTS auto-updates mid-run and swallows the compile step.** During a routine `check-gsc.ps1` run
it went 3.1.0 → 3.3.0. The update banner **replaced the compile output** — no `Done into ...` line —
so step 2 had nothing to read and the harness failed with `ROUND-TRIP FAILED (decompiler produced
nothing)`. The very next run compiled clean. **That failure looks like a broken script and is not
one. Re-run once before debugging anything.**

**2. The off switch exists**, and the earlier notes never found it — `ACTS\bin\acts-updater.json`:

```json
{ "disabled": true, "timeDelta": 86400000, "lastCheck": 0, "forced": false }
```

VERIFIED: with `disabled: true` **and** a deliberately stale `lastCheck: 0` — which should force a
check — no update fired and the run passed. Both machines must be pinned to the same build.
⚠ `UNVERIFIED` whether an update rewrites this file; re-check the flag after any deliberate un-pin.

**3. Read the build from `ACTS\bin\version`, not the folder name.** It currently reads `3.3.0` /
`3003000`. The sibling `atian-cod-tools-3.1.0\` is a separate source tree and does not track it.

**4. ACTS 3.3.0 still emits correct bytecode.** Re-verified after the bump:
`80 47 53 43 0d 0a 00 38` — exactly `cw::GSC_MAGIC`, last byte `38` = VM38 retail, not the `37`
alpha VM. The earlier VERIFIED claim in `toolchain.md` survives the version change.

**5. The updater leaves litter on a failed cleanup** — `acts_update.zip` (~26 MB) and
`acts-updater-tmp.exe`, with `remove: Access is denied`. Both are safe to delete. Worth doing before
copying `ACTS\` to the second machine.

**6. `check-gsc.ps1` used to pass hollowly on a fresh machine.** Without
`bocw-source-main\scripts` it printed a yellow warning and `exit 0` — reporting success while
skipping stage 3, the only stage that catches a typo'd API name. It now exits 1 with a fix hint. This
was a second-machine bug that could only ever bite on a second machine.

---

## ⚠ `injectcw` sequencing — the game must have entered MP once first

Discovered 2026-09-07. On a freshly launched game that has **never entered multiplayer in that
process**, injection fails with:

```
Can't find target script 'scripts\mp_common\bb.gsc'
```

That is not a tooling fault and not a bad path. `injectcw` patches an entry in the live
**`scriptparsetree` pool**, and `bb.gsc` is not in that pool until the game has loaded MP scripts at
least once. **Enter a multiplayer lobby before injecting.**

It reads exactly like a broken invocation, which is why it is recorded here — same class as the ACTS
auto-update gotcha: a sequencing problem wearing the costume of a tool failure.

## ⚠ Battle.net repairs files placed in the game folder

Also 2026-09-07. The `powrprof.dll` proxy and loader-shim work triggered a **full game re-download**.
Battle.net's integrity check reverts foreign files in the install directory.

Two consequences worth planning around:

- Any approach that **places a file in the game folder** is fighting the launcher, not just the
  anti-cheat. Budget for re-downloads.
- **GSC injection is unaffected** — it writes to a running process and leaves no file behind. That is
  a durability argument for the injection path independent of everything else.
