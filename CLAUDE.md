# CLAUDE.md — project conventions for "Choose a Planet"

Godot 4 survival game: pick one of four planets, learn its deadly physical rule, survive the day target. Everything is built from code and data; see `GAME_DESIGN.md` for the design.

## Engine version (pinned)

**Godot 4.7.2-stable.** Only Godot 4 APIs and GDScript 2.0. Never use Godot 3 names (`KinematicBody`, `yield`, `export var`, `onready var`, `instance()`, `connect("sig", self, "m")`). Use typed GDScript, `@export`, `@onready`, `CharacterBody3D`, `signal.connect(callable)`, `await`.

`tools/godot.sh` / `tools/godot.ps1` download the exact binary on first use into `.godot-bin/` (gitignored). `GODOT_BIN=/path/to/godot` overrides. On Windows the launcher uses the `_console.exe` build so output shows in the terminal.

## Run, test, screenshot

| What | Windows (PowerShell) | Linux/macOS |
|---|---|---|
| Play | `.\tools\godot.ps1 --path .` | `tools/godot.sh --path .` |
| Play a planet directly | `.\tools\godot.ps1 --path . -- --planet=04 --seed=42` | same args |
| Unit tests | `.\tools\test.ps1 [--filter=gas]` | `tools/test.sh [--filter=gas]` |
| Smoke boot (headless, fails on script errors) | `.\tools\godot.ps1 --headless --path . -- --smoke --planet=04 --frames=240` | `tools/smoke.sh 04` |
| Eruption smoke run | add `--trigger --timescale=10` | same |
| Screenshot without a GPU (Linux, Xvfb + Mesa) | n/a | `tools/screenshot.sh 04 120` |
| Dump the official class reference for the pinned version | `.\tools\godot.ps1 --headless --doctool docs\godot-classes --no-docbase` | `tools/docs.sh` |
| Open the editor | `.\tools\godot.ps1 --path . -e` | `tools/godot.sh --path . -e` |

Command-line user args (after `--`): `--planet=ID`, `--mode=short|standard|long_haul`, `--seed=N`, `--smoke`, `--screenshot`, `--frames=N`, `--trigger`, `--timescale=N`, `--eye=dx,dy,dz --yaw=r --pitch=r` (debug fly camera offset from spawn).

In-game keys: WASD move, Space jump, Shift sprint, Ctrl crouch, LMB dig, RMB place the block in the selected quick slot, 1–6 / wheel select quick slot, Q use the selected item (med → auto-picks the worst part; breather → toggle), E take a nearby pickup, Tab inventory, H health screen, F flashlight, Esc release mouse / close screens, R restart after death. In the inventory: click an item to hold it, click a cell to put it there, R rotates while holding, right-click for Examine/Use/Equip/Open/Split/Drop, 1–6 while hovering assigns a quick slot, G drops. Debug: F3 overlay, F5 trigger hazard, F6 time ×20, F7 fly, F8 reload `data/render_settings.json`.

Screenshot/smoke args for the screens: `--ui=inventory`, `--ui=health --hurt` (pre-damages the body).

**After every change:** run `tools/test.sh` and `tools/smoke.sh` (CI runs both). Headless `class_name` lookups need a fresh import; `tools/ensure_import.sh` handles that and the test scripts call it. For API questions, grep the doctool dump (`docs/godot-classes/doc/classes/*.xml`) rather than guessing.

## Architecture map

```
src/core      Game (autoload: boot/args/state), Run (one survival run, builds everything), GameClock, EventBus, InputSetup
src/data      DataRegistry (autoload "Data": loads + validates data/*.json), MaterialProps
src/net       Session (always a server; solo = local host), WorldCommands (validated dig/place, drops into / consumes from the player's kit; RPC transport lands in M4)
src/items     ItemInstance (stack, rotation, examined, uses/pool, nested grids), Equipment (pockets, rig, backpack, quick slots)
src/world     WorldData (chunk dict, bounds clamp, world_size 0 = infinite), Chunk, ChunkGenerator (seeded, deterministic),
              ChunkMesher (face culling + AO, worker threads), ChunkStreamer (load/unload around focus), BlockTextureGen, VoxelRay, PropSpawner
src/sim       Pure logic, no nodes, unit tested: GasSim, Vitals, InventoryGrid, BodyHealth (more sims land per milestone)
src/hazards   HazardModule (IDLE→WARNING→ACTIVE→RECOVERY), HazardDirector (schedule + escalation), HeavyGasHazard, Telegraph, GasRenderer
src/render    PS1Pipeline (low-res SubViewport + post shader), MaterialFactory, shaders/ (terrain, voxel_model, post, ps1_common)
src/voxel_art VoxelModel, VoxelMesher (greedy), PartRig (rigid parts), VoxelArt (generator registry + cache), generators/
src/player    PlayerController (first person, camera shake, dig/place through Session), PlayerKit (equipment + body + timed med/examine actions + breather)
src/entities  Creature (part-rig animation, wander brain, breathes), ItemPickup
src/ui        PixelFont (+glyph data), HUD, GridView, InventoryUI, HealthScreen
src/audio     SoundBank (synthesised AudioStreamWAV)
data/         materials.json, items.json (blocks, meds, containers, gear), palettes.json, planets/*.json (incl. starting_kit), render_settings.json, modes.json
tests/        run_tests.gd (runner), test_case.gd (base), unit/test_*.gd
```

## Rules of the codebase

1. **Code-first.** No scene editing. `main.tscn` is a single node; every other node is created in scripts. Don't add `.tscn`/`.tres` files; generate resources in code.
2. **Data-driven.** Items, materials, recipes, planets, hazards, enemies, trades live in `data/`. Add content there, not in code. `DataRegistry` validates on boot and the smoke test fails on validation errors.
3. **Rules, not puzzles.** Hazards only read material properties (`waterproof`, `airtight`, `opacity`, `heat_resistance`, `flammability`, `strength`, `buoyancy`, `weight`). Never special-case a material id in a hazard, and never add an item whose only purpose is to beat one hazard.
4. **Always telegraph.** Every hazard config must have `warning_time > 0` and warning cues; validation enforces the former.
5. **Server authority.** World mutations go through `Session.submit()` → `WorldCommands`. Sims and AI run only where `Session.is_server()`.
6. **Pure sims.** Anything in `src/sim/` is a `RefCounted` with no node dependencies so it runs in unit tests and (later) on worker threads.
7. **Procedural art.** Models come from `src/voxel_art/generators/*.gd` (`generate(params, rng, ctx) -> PartRig`), textures from `BlockTextureGen`, fonts from `PixelFont`, sounds from `SoundBank`. Seeded RNG everywhere; same seed = same result.
8. **Tests for logic.** New sim/inventory/health logic ships with `tests/unit/test_*.gd` (extend `TestCase`, methods named `test_*`).
9. **Performance escape hatch.** `ChunkGenerator` and `ChunkMesher` are the only hot paths; keep them isolated so they can move to a GDExtension if GDScript ever becomes the limit.
10. **Licenses.** Anything third-party goes in `LICENSES.md` before it is used.

## Gotchas learned the hard way

- Godot front faces are **clockwise**; wind triangles accordingly or everything renders inside out and trimesh collision stops working from above.
- Nodes inside a `SubViewport` do not receive input unless the event is pushed with `viewport.push_input()` (see `PS1Pipeline._input`).
- Writing `POSITION` in a spatial shader also runs in the shadow pass; `ps1_snap` skips orthographic projections for that reason.
- `pass` is a keyword, `Input` is a global class: don't use them as loop variables or inner class names.
- `signi()` truncates floats to int first; use `int(signf(x))`.
- Negative constants can't be built with `<<`; write `-(1 << 20)`.
- `WorkerThreadPool` tasks capture `self`; wait for them in `_exit_tree` (see `ChunkStreamer`).
- Two `RefCounted` objects referencing each other leak (no cycle collector). Back-references (`InventoryGrid.owner_item`, `ItemInstance.parent_grid`) are `WeakRef` properties; connect signals to methods, not to lambdas that capture `self`.
- `Dictionary.merge()` does not overwrite existing keys unless you pass `true`.
- Mouse events pushed into the low-res SubViewport must be remapped with `PS1Pipeline.screen_to_view_transform()` or GUI hit-testing is off.
- The test runner calls `Data.load_all()` itself; autoloads exist in `-s` runs but `Game.boot()` never runs there.
