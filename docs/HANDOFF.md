# Handoff: where the project stands and what comes next

Read this first when picking the project up in a new session. `CLAUDE.md` has the
rules and commands, `GAME_DESIGN.md` the design and the decisions log,
`docs/RELEASE.md` the release checklist. This file is the plan.

## State (2026-10-21)

All seven planned milestones are implemented and pushed on branch
`claude/new-session-ymiute` (no other branch exists yet; making it `main` is a
one-line GitHub setting).

- Four playable planets: 01 eclipse (sunlight line-of-sight), 02 beach (flood +
  roach swarm), 03 giants (footfall crush), 04 CO2 lake (heavy gas).
- Streamed 1024² voxel world; `world_size: 0` (infinite) boots and runs 5000
  blocks out but is not the default.
- Tarkov-style inventory and body-part health, survival needs, crafting,
  day/night, save/load, villages + dialogue, data-driven enemies, ENet co-op
  with ghosts and the Revival Ritual, a Steam bridge that is a no-op until the
  GodotSteam addon is present, F1 help, no on-screen instructions.
- Verified only headless on Linux plus Xvfb screenshots: 77 unit tests, smoke
  boots of all planets with hazards triggered, a host+client network run.
  **Nobody has played it with a mouse yet.** The first Windows launch failed on
  a missing import cache; the launchers now import automatically (commit
  1ff4948). Expect the first hour of play to surface feel and input issues.

## First session on a real machine: test plan

Do these in order and write findings into `GAME_DESIGN.md` (decisions) or this
file (backlog) as you go.

1. `.\tools\godot.ps1 --path .` opens the orbit screen; pick 04 / Standard.
2. Movement, look, dig, place, jump, sprint, crouch. Check FOV (104°), mouse
   sensitivity, camera shake, PS1 look (dither, snap, fog) at 1080p and 1440p.
3. Tab inventory: drag, rotate (R), nest the pouch in the backpack, quick
   slots, examine, drop. H body screen: use a bandage on a bleeding limb.
4. C crafting: planks, campfire, cook meat. Place the campfire, warm up at
   night.
5. F5 on 04: survive the gas by height, then by an airtight room. Confirm no
   text appears except the HUD state, and that the warning is readable from the
   world alone (bubbles, animals, rumble, haze).
6. 03: F5, stand in the open, under a boulder, inside a dome; build a plank
   hut and a stone hut and let the giant step on both.
7. 02: stilts vs a sealed brick room; squash roaches; swim.
8. 01: the moon slips, light burns; shade behind opaque blocks vs glass.
9. Talk to a villager on each planet; trade; accept and turn in a task; F5 and
   watch them go home.
10. Esc: save and return to orbit; relaunch with `++ --continue` (PowerShell eats a bare `--`; `++` is Godot's other user-arg separator and works everywhere).
11. Co-op on a LAN: `--host` and `--join=<ip>`; die on one side and run the
    Revival Ritual from the other.
12. `.\tools\test.ps1` and `.\tools\build.ps1 windows`; run the export.

## Backlog, in priority order

1. **Feel pass from real play** (expected to be large): movement speed,
   gravity, dig/place reach and timing, hit feedback, inventory drag
   ergonomics, font size at common resolutions (`render_settings.json:
   ui_scale`), FOV, head bob/shake amounts.
2. **Sound.** Everything is synthesised in `src/audio/sound_bank.gd` and
   mono. Options: more synthesis (footsteps per material, UI, water, wind,
   creature calls), or a CC0 pack (Kenney, OpenGameArt) dropped under
   `sounds/`, loaded by id in `SoundBank`, listed in `LICENSES.md` first.
   Positional audio (AudioStreamPlayer3D) for creatures, footfalls and the
   giant.
3. **Balancing from play.** Curves are in each `data/planets/*.json`
   (`interval_days`, `intensity`, `warning_time`, `active_time`). They are
   written in 100-day terms and scaled by `100 / mode.days`. Survival rates in
   `vitals`. Nothing has been tuned against a human yet.
4. **Steam P2P transport.** `SteamMultiplayerPeer` behind the same
   `MultiplayerPeer` seam as ENet in `src/net/net.gd`; lobby create/join in
   `src/steam/steam_bridge.gd` are stubs. Needs the GodotSteam addon
   (`tools/get_godotsteam.sh`, see `docs/RELEASE.md`) and a real app id.
5. **Co-op hardening.** Inventory, health and movement are client-owned by
   design (friendly co-op). If needed later: server validation of placement
   and item grants, reconnection, late-join world catch-up for large edit
   sets, chunk edit compression.
6. **Planet depth.** 02: rafts (`buoyancy` property is defined but unused),
   decoy warm spots. 03: giants that turn soil, scare predators, or react to
   being hit. 01: barn silhouettes that cast real shade. 04: gas that pools in
   player-dug pits (works) plus visible wind.
7. **Infinite world switch.** Flip `world_size` to 0 per planet after
   checking: float jitter in `ps1_snap` and physics past ~20 000 blocks, save
   size growth, structure cache growth (`ChunkGenerator._structure_cache`
   clears at 512 entries), chunk streaming at sprint speed.
8. **Performance.** `ChunkGenerator`/`ChunkMesher` are isolated for a
   GDExtension port if GDScript becomes the limit; measure with F3 at load
   radius changes first. Gas sim cell caps and flood `max_cells` are the other
   knobs.
9. **Accessibility and options.** A settings screen for FOV, sensitivity,
   dither strength, UI scale, key rebinding (`InputSetup.ACTIONS` is already
   data), colour-blind palette variants (`data/palettes.json`).
10. **Release.** `docs/RELEASE.md`. Steam depots, achievements in the
    dashboard, cloud save path, a `main` branch and tagging.

## Open design questions (not decided)

- Should solo death keep a "watch the world go on" ghost for a minute before
  the end screen, for the story value, or cut straight to it as now?
- Villager tasks are one chain per villager kind; do they need a reward that
  teaches the rule by example (e.g. the dome folk hand you a stone roof kit)?
- Night prowlers on 03 and dark hounds on 01 are the same logic with different
  data; is a third behaviour needed (ambush, pack) before launch?
- Long Haul (730 days) with the scaled curve means intensity peaks around
  day 440; is a mode that long wanted at all?

## Things that look wrong but are intentional

- No banner, no tutorial toast, no "day N" popup: rule 4 in `CLAUDE.md`.
- The air meter is hidden until oxygen drops.
- Solo saves are deleted on death and on winning (permadeath).
- Hazard cues in planet JSON contain no `toast` entries; the Telegraph still
  understands the type for debugging only.
- `screenshots/` and `.godot/` are gitignored; `tools/screenshot.sh` is
  Linux-only (Xvfb).

## How the sessions relate

Cloud sessions can edit, test headless and push; they cannot run the game
with a display or reach your PC. Local sessions can play and screenshot.
Both work on the same branch: `git pull` before each run, commit small, push
often. Every decision a player would notice goes in the `GAME_DESIGN.md`
decisions log; every command or gotcha goes in `CLAUDE.md`.
