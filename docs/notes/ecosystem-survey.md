# Ecosystem survey — every other Cold War GSC / PC-modding project, swept 2026-09-13

**Question answered:** is anyone else doing Cold War multiplayer GSC work, and what does the wider Cold
War PC-modding scene look like as of September 2026. Extends [[pipeline-toolchain-survey]] (Aug 2026, six
repos) to the whole scene. Everything below was checked in-session — GitHub API, raw files, YouTube
upload-date search, Discord invite resolution — not inherited from search-engine summaries.

## The answer

1. **No one else is doing open MP gametype or lobby work on Cold War.** Every MP-capable GSC artifact
   found is a mod menu, and the MP-capable ones are closed and paid. BOCW-Gunfight is alone in its niche.
2. **A new Cold War modding scene appeared 2026-08-16 — and it is Zombies-only.** "T9 Mod Manager" +
   the **T9 Modding** Discord: a closed launcher that compiles, injects, packages and distributes ZM mods.
   1,398 members after four weeks; eight packages; a 40k-view showcase. Details in §2 — it is the only
   group plausibly touching the same *pregame-lobby* layer this project is working.
3. **The "client" route is dead.** ProjectDonetsk/T9 (Defcon) unmaintained, its named successor
   `xifil/t9-mod` gone (xifil now does BOIII forks). The nearest living engine sibling with real
   lobby/server control is **Project-BO4 Shield** (BO4/T8), last pushed 2025-03-12.
4. **This project's own toolchain authors are the most active people in the scene** — ACTS pushed
   2026-09-12, `t7-compiler-custom` 2026-09-13. §3 has what changed and the one open question it raises
   (a CW fastfile *linker* now exists; nothing loads its output into retail).

## 1 · Project table

Verified = read from the GitHub API / raw files on 2026-09-13. Known = already in the notes.

| Project | What it is | Verified state | Relevance here |
|---|---|---|---|
| **FanaticSoftware/T9ModPackages** (+ the closed *T9 Mod Manager*) | ZM mod distribution: encrypted `.cwm` packages, `manifest.json`, security-scan counts, Discord approvals | created 2026-08-18, 358 commits, pushed 2026-09-11 | §2. Same *hosting-control* goal as Goal A, ZM only |
| **AuroraDoesCode/ColdWar-Lucy-Base** | open ZM GSC menu base (12★) on the t7-compiler line | pushed 2026-09-03 | same compiler; inject-from-lobby recipe; ZM only |
| **AuroraDoesCode/t7-compiler-custom** `dev_csc_inj` (known) | the injector line | pushed 2026-09-13 | §3 — nothing beyond the `4de00c8` the notes cite |
| **socankam/ColdWarGSCMenu** · `cwmenu` · **Cold-War-PS4-GSC-Injector** | open ZM menu (GPLv3, credits ate47 + TheUnknownCod3r) · PS4 injector source · **MP+ZM menu is closed, $40** (PC/PS4) | 2026-05-23 · 2025-12-06 · 2026-07-16 | PS4 injector corroborates the PC load model exactly (§3.3) |
| **DanMillar99 "Uprising"** via **infinityloader.com** | ZM GSC menu distributed through a 2020-era multi-game GSC loader with a paid store | video 2026-08-20; loader zip dated 2023-11-11; store API dead | closed; nothing to learn |
| **ProjectDonetsk/T9** (Defcon) (known) | the CW client | pushed 2025-06-01, unmaintained, MIT; its Discord now resolves to a general hangout ("Zero • Chair Hacks OT", 1,029) | dead end stands. `xifil/t9-mod` still 404; xifil's live repos are all BOIII (`t7-lfx`) |
| **project-bo4/shield-development** | BO4 client: Demonware emulator, own lobby, GSC/Lua loading, 264★ | pushed 2025-03-12; ACTS 3.3.0 ships an `acts-shield-plugin.dll` | the only *open* implementation of lobby-level control on this engine family |
| ate47/cod-source · ate47/oldcod-source | fastfile extraction · old-CoD dump | 2025-12 | reference |
| Scobalula/Greyhound · Scobalula/Cordycep | asset export, both support CW | 2024-07 · 2024-08 (Cordycep continued by dest1yo) | assets, not scripts |
| xSoniz/T9-Assets-Extracted-List · adamspiteri/CoDs_GSC_Wiki_Library_IW8Plus | T9 asset name list (2022) · GSC wiki for IW8+ (IW engine, not T9) | stale · 2025-11 | marginal |
| MrJasonDEX/Cold-War-Mods · OhItsDiiTz/T9Host · MrSkylineee/… · caffeinepub/… | "public leak" batch files · 2021 tools · a TypeScript site | dead | ignore |

GitHub topic pages tag only two CW repos (`ate47/t8-atian-menu`, `ate47/bocw-source`); the rest surfaced
only through the search API. `xensik/gsc-tool`: no default-branch commits since 2026-08-01, T9 unchanged.

## 2 · T9 Mod Manager / "T9 Modding" — what is verifiable

**People and places.** Discord guild `1538475911203266600`, name **T9 Modding**, created 2026-08-16
09:14 UTC, **1,398 members / 401 online** at 2026-09-13 07:34 UTC, boosted tier 2, invite
`discord.gg/Y2Ww4btH99` (inviter: MJPW). Its self-description, verbatim:

> The only place you need to be to use mods on Black Ops Cold War Zombies! We host the Mod Manager,
> supply the Mod Tools, and handle all of your Mod distribution, all built straight into the launcher!

`members.json` lists four modders: Fanatic (`fanaticsoftware` — the BO3 mod-tools/Steam-workshop
veteran; also maintains CoDMayaTools for Maya 2026+), SaintVertigo, Figglebottom (`illuminatidonut`),
TheTeaa. Showcase: MJPW, *"Modded Zombies For Call of Duty Black Ops Cold War IS REAL!"*
(`youtu.be/DMWnkUE-ZQ0`, 2026-08-24, 39,974 views, 31 min). Fanatic's *"BOSS RUSH MOD IN COLD WAR
ZOMBIES! (T9 Mod Manager)"* (`youtu.be/6eL8Q3wozFk`, 2026-08-21): *"Simply load into a map, setup in
the pregame lobby, ready up, and fight the Boss!"* — mod configuration happens **in the ZM pregame lobby**.

**The repo** (`github.com/FanaticSoftware/T9ModPackages`, 0★, README is two lines): `manifest.json`
(schema 1, regenerated on every publish), `members.json`, `shared.json` (three shared-source projects),
`notices.json` (approval log), `stats.json` (favourites/ratings), `drafts.json`, `invites.json`,
`collab_optout.json`, `mod_packages/<id>/<id>-<ver>.cwm` + `thumbnail.png`,
`shared_projects/<id>/source.cwm`. Eight packages on 2026-09-11:

| id | ver | author | note |
|---|---|---|---|
| `zm_classic_beta` | 2.0.13 | Figglebottom | classic points/perks/PaP, no rarities, 1911 start; **63 settings** |
| `realism_mode` | 1.1.22 | SaintVertigo | gameplay overhaul |
| `aetheria_unfinished_test_ver` | 1.0.35 | TheTeaa | test build |
| `doom_mode` | 1.0.5 | SaintVertigo | speed/ammo pickups |
| `onslaught_survival` | 1.0.3 | SaintVertigo | Onslaught → survival |
| `boss_rush` | 1.0.2 | Fanatic | straight to the boss fight; auto-detects the four round maps |
| `holiday_events` | 1.0.2 | Fanatic | re-enables The Haunting + Jingle Hells (removed content) |
| `directors_cut` | 1.0.1 | Fanatic | IW super-EE reward |

Per-package manifest fields: `title, description, author{discordName,id,name}, developer, sourceSha256,
scan{critical,high,medium,low,rules:"2026.08.19",summary}, settings (count), tags[], changelog,
highAlerts[], approved{by,byId,at,thread}, version, file, size, sha256, history[], thumbnail,
collaborators[]`. The `scan` block is a rules-based script-security scan (e.g. `realism_mode`: 124 high /
241 medium / 19 low) and `approved.thread` is a Discord thread URL — a review gate before distribution.

**Package format.** `.cwm` = `CWMPKG` magic, `01 00 01 00`, eight zero bytes, a 32-byte high-entropy blob
at 0x10, then a body at **7.95 bits/byte with no plaintext** — encrypted, not merely compressed. The mod
sources are not readable from the repo.

**Not verifiable (closed):** the manager app itself is not on GitHub (distributed in the Discord); how it
loads a package into the game (a launcher, so presumably its own DLL + the same scriptparsetree patch
everyone uses — *unconfirmed*); Battle.net vs Steam; anti-cheat posture; any MP support (none advertised,
the Discord says "Zombies"). Not indexed on Reddit at all as of today.

**Why it matters here.** Two things. (a) It is a working model of Goal A's *distribution* half — a
launcher, per-mod settings surfaced pre-match, hashes, review gate — built in four weeks by people who
already had BO3 mod-tools muscle. (b) Their mods configure themselves **in the pregame lobby**, which is
the layer [[pregame-routes]] and [[lobby-setters]] are fighting for. Whether they reached it from GSC
(`load_shared.gsc` hook, the P1 payload's route) or from their launcher's DLL is exactly the question
worth asking them. ⚠ Asking is klaze's call — the project is not public.

## 3 · Toolchain news

### 3.1 ACTS (ate47/atian-cod-tools) — 3.3.0 is dated 2026-09-05; the pin is current

Release 3.3.0 (assets `acts.zip` 25.6 MB, `acts-shield-plugin.dll`), Cold War items verbatim: *enhance cw
zone linker · fix unsaved scans in handler · unhash kvp keys · allow to aes encrypt fastfile ·
weaponfrontend, scriptbundlelist and zbarrier unlinkers · bgcache, keyvaluepairs, localize and
scriptparsetree linkers*; GSC items: *`gsco` tool to obfuscate GSC scripts · detect in-script trampolines*;
*acts bocw dll: faster scans loading, cleanup old code*.

Since the release: `#xx` hash syntax (09-06), a WIP BO4 plugin (09-10), **a GSC language server and a
VS Code extension** (`acts-vs/`: `src/extension.ts`, `syntaxes/gsc.tmLanguage.json`; LSP gained the syntax
parser + preprocessor info on 09-12). Worth a try for authoring `src/` once it ships a build.

**The CW zone linker and the open question.** `test/ff-linker/core_actscw/core_actscw.zone` builds a CW
fastfile from GSC:

```
>game=cw
>name=core_acts_dev
>compression=oodle_kraken
>gsc.gendbg=true
>gsc.dev=true
rawfile,acts/test_rawfile.txt
scriptparsetree,scripts/core_common/acts/no_linked_test.gsc
scriptparsetree,!scripts/core_common/acts/echo_test.gsc      // '!' = auto-link
scriptparsetree,!scripts/core_common/acts/echo_test.csc
```

(`echo_test.gsc` is the familiar `autoexec __init__system__` → `system::register` → `callback::on_connect`
shape.) Linker source: `src/core/acts/tools/fastfile/linkers/cw/linker_cw_scriptparsetree.cpp`. But the
current `src/dll/bocw-dll/systems/gsc.cpp` (73 lines) only installs a LazyLink handler at
`gVmOpJumpTable[0x13]` and detours `Scr_GscObjLink` to log — **nothing in ACTS loads a custom `.ff` into
retail Cold War.** So: a build-side capability with no measured load side. Belongs in *Untried — not ruled
out*, not in the plan. The one cheap probe, if ever wanted: whether retail's DB layer accepts an
ACTS-linked, AES-encrypted zone dropped beside the stock ones — a klaze-runs-it experiment, not script.

### 3.2 t7-compiler-custom `dev_csc_inj` — active, but the CW work is what the notes already have

Commit timeline (only branch is `dev_csc_inj`): 2026-08-13 *fix Cold War Opcodes*, *Get rid of the MOTD*;
08-17 *Update Compiler*; **08-20 *Cold War Pattern Scanning* = `4de00c8`**, the commit
[[pipeline-toolchain-survey]] cites — the change is inside the binary `update.zip` / `t7c_installer.exe`,
source diff is one line each in `DebugCompiler/Root.cs` and `t8cinternal/builtins.cpp`; 08-21 *Script Hash
on Inject* (`506affb`, `Root.cs`); 08-22 → 09-12 Luisete2105: three-version BO3 support, *Fixed game
version detection when using a custom game client* (08-23), *Pattern base scan for all Bo3 versions*
(09-12); 09-13 merge of PR #2. Nothing Cold War-specific after 08-21.

### 3.3 The PS4 injector says the load model is universal

`socankam/Cold-War-PS4-GSC-Injector/ColdWarGSC.cpp` (Orbis, 2026-07-16): `scriptAssetType = 68`,
`DB_FindXAsset` at RVA `0x0054D840` (PS4 build), hook target `scripts/core_common/load_shared.gsc`
(`0x00FD2E9FE6934867`), replacement `scripts/core_common/clientids_shared.gsc` (`0x124CECFF7280BE52`),
reads `/data/app/compiled.gsc`, patches the `ScriptAsset{name, buffer, len}` (0x18 bytes) in place, and
verifies the compiled header's name matches the replacement hash. That is the PC injector's mechanism to
the letter — including the **one replace target per launch** constraint [[desktop-session]] is built
around. Independent confirmation that the constraint is structural, not a t7-compiler quirk.

## 4 · Community hubs (member counts 2026-09-13, from Discord's invite endpoint)

| Hub | Size | What it is |
|---|---|---|
| **T9 Modding** (`Y2Ww4btH99`) | 1,398 / 401 online | the mod-manager scene, ZM |
| cdogbruv's server (`cG24bcrpEV`) | 13,257 | T9-client downloads ("How To Install T9 Client [UPDATED FOR 2025]", 2025-01-01, 12.3k views) — Defcon-era client, current-retail status unknown |
| Infinity Loader (`nppTRMjsHr`) | 4,823 | multi-game GSC loader + paid store, 2020-era; site refreshed 2026-06, download 2023-11, store API unreachable |
| Slingshot Mods (`d3m8mZm8aB`) | 1,621 | PS4 test-kit modding (Gir); not PC |
| FANATIC (`FM3rqK4YpD`) | 281 | Fanatic's BO3 mod-tools community |
| Uprising (`JkvNaraV2M`) | 204 | DanMillar99's ZM menu |
| Se7enSins *Black Ops Cold War Modding* forum | dormant | newest thread 2024-07; content is account-unlock tools and PS4 1.27 "cheater" tools |
| CabConModding thread 8305 (*"Black Ops Cold War GSC Mods?"*) | — | Cloudflare JS wall (HTTP 403 to everything tried) |
| MPGH *"Cold war Offline Tool"* (t=1532791) | — | cheat forum, 403; not pursued (ground rules) |
| Nexus Mods CW page | — | exists, 403 to fetch; nothing indexed suggests gameplay GSC there |

Steam: BOCW has a Steam build (app `1985810`, live discussions). This project runs the Battle.net build;
the injector's pattern scanning should make the exe difference moot, but that is untested here.

## 5 · Dead ends and non-findings (so they are not walked again)

- **Reddit** has no indexed post on T9 Mod Manager / T9 Modding (site-scoped searches return nothing;
  `reddit.com/search.json` is bot-walled).
- **No 2026 Cold War client** of any kind. `xifil/t9-mod` remains 404; xifil's account has no T9 work.
- **No open MP project**: not a gametype, not a map vote, not a lobby tool. MP GSC = menus only.
- **Anti-cheat news** in 2026 is all BO7/Warzone (Ricochet S03/S04 posts); nothing Cold War-specific
  surfaced. [[tac-risk-model]] stays the reference.
- The glitch videos the roadmap said were proxy-blocked are readable now — **the verbatim three-variant
  text is in [[roadmap]] §B2 and [[pregame-routes]]** ("THE GLITCH'S ACTUAL INPUT SEQUENCE"). The founder
  is GlitchHunterz (`youtu.be/Wxctp-7rrEs`); FacelessOne (`youtu.be/uzXXE7v_PBU`) re-posted the same text.

## 6 · Method (reproducible)

- GitHub search API, unauthenticated (10 req/min): `"cold war" gsc`, `"black ops cold war" mod`,
  `"black ops cold war" gsc`, `bocw gsc`, `"cold war" "mod menu"`, `BlackOpsColdWar`, `"cold war" t9 call
  of duty`, `"cold war" zombies mod call of duty` → 19 unique repos, then `GET /repos/<r>` for
  `pushed_at`/`archived`, `GET /repos/<r>/commits?since=…`, `GET /repos/<r>/git/trees/HEAD?recursive=1`,
  and `raw.githubusercontent.com` for files.
- YouTube: `results?search_query=…&sp=CAI%3D` (upload-date sort) parsed from `ytInitialData`; video
  descriptions from `shortDescription` in the watch page.
- Discord: `GET https://discord.com/api/v10/invites/<code>?with_counts=true` (guild name, id → creation
  date from the snowflake, member/online counts). No login needed.
- WebFetch 403s on Se7enSins/MPGH/CabCon/Nexus; `curl` with a browser UA gets Se7enSins only.
