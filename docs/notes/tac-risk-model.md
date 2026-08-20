# TAC risk model — where this mod is exposed, and to whom

**What this note is.** A threat model for the mod: the points at which Treyarch Anti-Cheat (TAC) and
Activision's server-side telemetry can observe it, who carries each risk (host vs joiner), and how
confident that assessment is. Its purpose is **informed consent** — CLAUDE.md's standing instruction is
*"Tell participants; it's their accounts,"* and this is the artifact that lets you do that honestly.

**What this note is NOT.** It does not describe how to hide the injector, defeat a detection, spoof
hardware, or reduce detection probability. That is anti-cheat evasion and is out of scope for this
project by decision (CLAUDE.md ground rules), not covered here, and not something the rest of the repo
depends on. Identifying where a tripwire is so people can decide whether to step is disclosure;
disarming it is not. This note stops at disclosure.

**Bottom line up front.** The host runs an injector, so the host should assume TAC *can* detect the
modification and that a ban is a live possibility. The project does not try to prevent that — it limits
the *consequences* (throwaway account, secondary PC, Battle.net instead of the Steam VAC stack) and
accepts the *detection* risk. Joiners inject nothing, so their **local** exposure is expected to be
low, but **server-side telemetry is unknowable from outside Activision** and cannot be certified safe
for anyone. Nobody should join on an account they care about.

---

## What TAC is (from CLAUDE.md, restated so this note stands alone)

- **TAC**: Treyarch Anti-Cheat. **User-mode only, no kernel driver.** Present on both Battle.net and
  Steam. Documented detections: **API hooks, debugger artifacts, overlays.**
- **Arxan**: EXE obfuscation plus **runtime API hashing** — integrity checks over the game's own native
  code and imports.
- **VAC**: Steam only. Not present on Battle.net. (This is the entire reason the project targets
  Battle.net.)
- **Ricochet**: not present — BOCW is absent from the Ricochet title list.
- **Ban policy**: bans cite *"unauthorized software and manipulation of game data,"* are **account-wide,
  permanent, and non-appealable** (appeals auto-rejected).

## Risk register

Confidence is my assessment, not Activision's: **High** = follows directly from documented TAC behavior;
**Med** = plausible from how the tech works; **Unknown** = cannot be assessed without Activision-side
data.

| # | Vector | Who | What is observable | Detect confidence | Notes |
|---|---|---|---|---|---|
| R1 | **Injector process & memory write** | Host | A foreign process opening a handle to the game and writing/allocating executable memory in it | Med–High | The base act of injection. TAC is user-mode and can enumerate handles/threads/memory of its own process from user space |
| R2 | **API hooks / detours** | Host | If the injector or the mod installs detours (candidate 2+ in [[mp-load-path]] uses `replacefunc`), the hooked call sites / trampolines | **High** | TAC **explicitly** detects API hooks. This is the single most on-the-nose vector. A `replacefunc`-based MP bootstrap sits directly in it |
| R3 | **Script-VM modification** | Host | Added/renamed functions and the reassigned `level.ontimelimit` in the loaded script state | Med | Squarely matches the ban language *"manipulation of game data."* Whether TAC or the server actually hashes/inspects VM state is unconfirmed |
| R4 | **Arxan integrity trip** | Host | Only if injection perturbs native code or imports Arxan hashes | Med (Low for pure GSC) | GSC/VM injection is data-level, so it may not touch Arxan's coverage — **but a native detour (R2) can**. Do not assume GSC = invisible to Arxan without testing |
| R5 | **Debugger / overlay during dev** | Host (dev) | An attached debugger or a rendering overlay on the **live** game process | **High** | TAC detects both by name. This is a *development* footgun: debugging the injector against the live game adds a detection vector that has nothing to do with the mod itself |
| R6 | **Server-side match telemetry** | Host **and** joiners | Impossible-in-stock states: 6v6 Gunfight, Gunfight on a map with no `gunfight_zone_center`, a timer outside the published 0/20/30/40/50/60 set | **Unknown** | The one vector joiners share. Not a local TAC detection — it rides on whatever Activision logs server-side. Unknowable and uncertifiable from outside |
| R7 | **Behavioral / statistical flags** | Both | Aggregate anomalies across matches on the host account | Unknown | Same epistemic status as R6 |

## Host vs joiner — the asymmetry participants must be told

- **Host** carries R1–R5 in full. The host is the machine running the injector; every local detection
  vector lives there. Treat the host account as **expendable**.
- **Joiners** run an unmodified client connecting to a host running modified gametype logic. They inject
  nothing, install no hooks, load no foreign scripts — so R1–R5 do **not** apply to them locally, which
  is why the expectation is low joiner exposure.
- **But R6/R7 are shared and Unknown.** A joiner sitting in a 6v6 Gunfight on an unsupported map is
  *in* a match state that stock cannot produce. If Activision's server-side telemetry flags that state,
  it flags everyone in the lobby, joiners included. **No one outside Activision can rule this out.** The
  honest statement to a joiner is: *"your local risk is expected to be low, your server-side risk is
  unknown and unprovable, and the ban if it comes is permanent and account-wide."*

## What the project does about it (consequence-limiting, not evasion)

Stated so participants understand the posture, and so the boundary is explicit:

- **Throwaway account** — limits what a ban costs, does not lower detection odds.
- **Secondary PC** — isolates the host machine, does not lower detection odds.
- **Battle.net over Steam** — removes the VAC layer (Steam-only); TAC is identical on both, so this
  **does not reduce detection probability**, only the number of enforcement systems that can act.

⚠ Every item above changes the **blast radius**, not the **probability**. CLAUDE.md says this in the
ground rules; it is repeated here because it is the exact thing people get wrong. If a plan claims to
make detection *less likely*, it has crossed from this note's scope into evasion.

## Unknowns (cannot be closed from this side)

- Does TAC or the server hash loaded script state? (R3 confidence)
- Does any part of injection cross Arxan's hashed coverage? (R4 — testable only by trying, on an
  expendable account)
- What match-state telemetry does Activision collect and act on? (R6/R7 — **unknowable**)
- Joiner server-side exposure — flagged UNKNOWN in CLAUDE.md ground rules and unresolved here.

## Participant disclosure checklist

Before anyone joins, they should be told, in plain terms:

- [ ] This is a modified game state produced by injecting into the host's game. It violates the game's
      terms.
- [ ] Bans are **account-wide, permanent, and not appealable**.
- [ ] Your client is unmodified, so your *local* detection risk is expected to be low.
- [ ] Your *server-side* risk is **unknown** and cannot be guaranteed — you are in match states stock
      cannot create.
- [ ] Use an account you are willing to lose.
- [ ] The project does **not** hide any of this from the anti-cheat; it accepts the risk and limits the
      fallout. It is not making you safer than the above.

If a participant cannot say yes to "an account I'm willing to lose," they should not join. That is the
whole point of writing this down.
