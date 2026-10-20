# GAME_DESIGN.md — "Choose a Planet"

Living record of design decisions. Update when a decision changes; keep the reasoning.

## Premise

From orbit the player sees four planets (01–04) and picks one. Each looks livable and has one deadly **quirk** that is a consistent simulated rule. Survive the day target: Short 30, Standard 100, Long Haul 730 (`data/modes.json`). Modes differ only in the day target.

## Pillar: rules, not puzzles

- **Materials have properties, not purposes.** `data/materials.json` gives every block `waterproof, airtight, opacity, heat_resistance, flammability, strength, buoyancy, weight` (plus `hardness`, `tool`, `drop`). Hazards only ever test properties. Any build that satisfies the property works.
- **Hazards are readable physics.** Gas is heavier than air and flows downhill; water fills open space below a level; sunlight is a straight line; a footfall crushes what is under it.
- **Always telegraph.** Every event has a warning phase with layered cues (`cues.warning` in the planet JSON: toasts, synthesized sounds, tremors, bubbling, animals fleeing or dying). Deaths must feel fair.
- **Planet gear is one option among several** and always has a cost (consumable, heavy, breaks, partial).
- **Escalation.** `interval_days` and `intensity` are linear-in-day curves with clamps (`HazardDirector.curve`).

## Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-10-20 | Godot 4.7.2, GDScript only, Compatibility renderer | Newest stable; PS1 look needs no Forward+ features; best low-end/Deck support; renders under Mesa for CI screenshots |
| 2026-10-20 | Own streamed voxel engine, 16³ chunks in a dictionary, lazy deterministic generation | 1024² world now, infinite later is a config change (`world_size: 0`) |
| 2026-10-20 | Server-authoritative from M1 (`Session`/`WorldCommands`); solo = local host | Co-op later without a rewrite |
| 2026-10-20 | Permadeath in solo; co-op gets a Revival Ritual (below) | Player answer: permadeath, but a dead friend must not just watch |
| 2026-10-20 | Planet 03 = giants, mostly benign (crush rule) | Player answer; detailed design deferred to its milestone |
| 2026-10-20 | Windows is the primary dev OS | PowerShell launchers ship beside shell ones; Windows export verified first |
| 2026-10-20 | Materials ids are stable bytes; id 0 = air | Saves and network use raw block arrays |
| 2026-10-20 | Hazard sims run on an *active region* around players, never the whole world | Bounded cost at any world size; open region edges destroy gas |
| 2026-10-20 | Props spawn per chunk column from the seed; no props within 5 blocks of spawn | Deterministic, streamable; player must not wake up inside a tree |
| 2026-10-20 | Creatures obey hazard rules (`breathes`) and die first on low ground | Dead animals are the brief's organic warning sign |
| 2026-10-20 | Inventory: 4 built-in 1×1 pockets + rig + backpack container items with per-grid shapes (`grids: [[w,h],...]`), nesting allowed, 6 quick slots that reference items anywhere in the kit | Tarkov model; quick slots double as the block hotbar so one UI concept covers meds, gear and building |
| 2026-10-20 | Health: 7 parts (35/85/70/60/60/65/65 = 440), blacked part forwards 70% of further damage to the rest, head/thorax 0 = death; meds as data with `med` kind, `treats`, `uses`/`hp_pool`, `use_time` | Tarkov model; use times make healing a decision during an event |
| 2026-10-20 | Unknown items (`known: false`) show a vague name until examined (timed action) | Brief requirement; cheap tension on finds |
| 2026-10-20 | Weight limit 25 kg (reduced by arm injuries); over it, speed drops 1.5%/kg to 60% | Makes block stacks a real choice without Minecraft-style infinite pockets |
| 2026-10-20 | Planet gear example: breather mask (85% filtering, 90 s consumable filters, 1.2 kg) | One costed option among several (high ground, airtight room, trenches) |
| 2026-10-20 | Fall damage above 11 m/s landing speed goes to the legs as blunt damage | Gives the health system a reason to exist before enemies arrive |
| 2026-10-20 | Survival needs: hunger empties in 36 game hours, thirst in 20; at zero they cost 6 / 10 HP per game hour. Body temperature drifts toward the felt ambient (day/night from the planet mood, +shelter, +campfire); below 33 °C or above 41 °C costs HP | Pressure without a timer; every need has a readable fix (eat, drink, roof, fire) |
| 2026-10-20 | Food spoils in game hours (`spoil_hours`) into Spoiled Food (80% poison chance); raw meat 35%; cooking at a campfire removes it | Cooking matters, as the brief asks |
| 2026-10-20 | Campfire is a block with `emissive`, `light`, `heat` and `station` properties, placed from a crafted item | Keeps everything on the block grid; hazards can read its flammability later |
| 2026-10-20 | Resources: trees are harvested with E (logs + fiber, tree removed), bushes regrow in 24 h, grazers drop meat when killed by the player (not by gas), lake water is drinkable | Closes the gather → craft → build loop on planet 04 |
| 2026-10-20 | One save slot per run (`user://saves/current.*`), edited chunks only, autosave every 3 real minutes, deleted on death or win | Permadeath per the player's answer; saves exist for quitting, not retrying |
| 2026-10-20 | Orbit screen: all four planets shown, uncharted ones greyed with a note | The fantasy of choosing is there from day one |
| 2026-10-20 | Day/night cycle drives sun angle, sky, fog and ambient; nights reach 85% darkness on 04 | Flashlight and campfire earn their keep |
| 2026-10-20 | Co-op over ENet: host runs the world; clients generate terrain from the seed and receive edited chunks, block edits, hazard phases, packed gas cells (2 Hz, within 64 blocks of a player), clock, creatures (5 Hz), pickups, harvests, rituals. Inventory/health/movement are client-owned; the server grants dug items and trusts placement | Friendly co-op first; the authority seam is in place to tighten later. Steam transport swaps in at M7 |
| 2026-10-20 | Death in co-op = ghost: fly, watch, cannot act; all items plus a Survivor's Tag drop as pickups. Solo stays permadeath | Nobody sits out a session |
| 2026-10-20 | Revival Ritual: craft Cairn Stones (6 cobble + rope), place the cairn, select the dead player's Tag and press E on it, keep a heat source within 3 blocks through one full night (1.25 nights for the second revive, +0.25 each); a destroyed cairn fails the vigil, a dead fire only pauses it. Revived: 60% max HP, half hunger/thirst, empty hands | Property-based (any fire, any stone), costs time and attention during the planet's own hazard |

## Planets

### 04 — The CO2 Lake Planet (vertical slice, Milestone 1)
Lush hills with still lakes (`co2_water`). **Rule:** a lake "breathes out" a heavy gas (`GasSim`): emitted from lake-surface cells, it falls first, spreads sideways toward lower concentration, creeps upward only when a cell is nearly full, is stopped by `airtight` blocks, and decays. Oxygen drains when breathed concentration ≥ `vitals.gas_threshold`; empty lungs deal `suffocation_dps`.
- Telegraph (45 s): toast, deep rumble loop, bubbling particles on the lake, tremor at 15 s, birds scatter at 20 s, stronger bubbling at 30 s, second tremor at 40 s, screen tints green when active.
- Solutions that fall out of the rules: high ground; airtight room (brick/stone/glass/clay/dirt, not thatch/planks/leaves); walls or trenches that redirect the flow; waiting it out on a roof. Breathing gear and oxygen plants come in later milestones as costed options.
- Escalation: `interval_days 2.0 − 0.02/day (min 0.5)`, `intensity 1.0 + 0.03/day (max 3.0)`; intensity scales emission and active duration.
- Grazers wander the hills and suffocate in pooled gas (greyed, tipped over) — read the corpses.

### 01 — The Eclipse Planet (M5)
Permanent twilight under a moon; periodic sun exposure. **Rule:** `LightRaySim` traces straight lines from the sun; transmitted light accumulates `1 − opacity` through blocks; exposed surfaces/entities burn. Farmhouse shadows of the dead on barn walls.

### 02 — The Beach Planet (M5)
Pleasant beach; periodic storm flood plus roach swarm. **Rules:** `FluidSim` raises a water level and fills non-waterproof/open cells below it (sealed waterproof volumes stay dry; `wave_force` vs `strength` destroys weak blocks; `buoyancy` floats rafts). `SwarmSim` paths roaches to the nearest dry cells; they squeeze through non-airtight solids slowly.

### 03 — The Giants Planet (M7)
Mostly benign giants. **Rule:** `CrushSim` applies `crush_force` under each footfall to blocks (`strength`) and `crushable` entities; tremor telegraph scales with distance. Giants ignore players unless provoked and may be useful.

## Death and the Revival Ritual (co-op, M4)

Solo: permadeath; saves are deleted on death. Co-op: a dead player becomes a **ghost** (spectate, whisper hints, no actions). Living players can revive them with the same ritual on every planet (`data/ritual.json`, tunable):
1. Build a **Cairn**: any blocks whose combined `weight ≥ W` and minimum `strength ≥ S` (property check, so each planet uses its own stone).
2. Place the dead player's **Tag** (a 1×1 item dropped on death; can be lost to flood or fire) on the cairn.
3. Hold a **vigil**: a burning light source on the cairn must stay lit through one full in-game night (fuel cost; the cairn is subject to the planet's hazard like anything else).
4. The revived player returns with low max HP on previously blacked-out limbs and an empty inventory. Cost scales mildly with revives per run.
Alternative kept for comparison: a plain 3-day cooldown.

## Visual style

PS1 / liminal: 3D rendered to a 480×270 SubViewport, nearest upscale, Bayer 4×4 dither, 5-bit colour, vertex snap, affine texture warp, depth fog, vignette; all in `data/render_settings.json` (F8 reloads). Art is procedural micro-voxels: terrain blocks at 1 m, trees at 1/4 block voxels, creatures 1/8, small items 1/16; greedy-meshed, cached per (generator, params, seed). Pixel font 5×7 with baked outline, scale 1 for HUD, 2 for banners. Palette per planet in `data/palettes.json`; moods: 01 purple-black dusk + corona, 02 overexposed sand/sea, 03 TBD, 04 saturated greens with sickly haze.

## Systems roadmap (milestones)

1. ✅ Vertical slice on 04: movement, streamed voxel terrain, dig/place, 15 materials with properties, GasSim + director + telegraph, oxygen, PS1 pipeline, micro-voxel tree/lantern/grazer, debug tools, tests.
2. ✅ Tarkov inventory (grid, rotation, nested containers, weight, examine, quick slots, pickups) + body-part health, status effects, meds with use times, health screen, fall damage, breather mask.
3. ✅ Survival loop: hunger/thirst/temperature/stamina, food & spoilage & cooking, crafting from `recipes.json`, campfire, harvesting, hunting, day/night, planet select, pause menu, save/load, export presets + build scripts.
4. ✅ Co-op foundation (ENet host/join, replication, remote avatars, ghost + Revival Ritual, `tools/nettest.sh`).
5. Planets 01 and 02 (light ray; flood + swarm).
6. NPCs, villages, enemies for 01/02/04.
7. Planet 03, escalation balancing, polish, GodotSteam (achievements, cloud saves, Steam lobbies), release checklist; infinite-world switch evaluated.
