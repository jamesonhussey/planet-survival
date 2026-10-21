# Choose a Planet

A 3D survival game built with Godot 4.7.2: pick one of four planets from orbit, discover its deadly physical rule, and survive the day target. Minecraft-style digging and building, Natural-Disaster-Survival-style escalating events, Tarkov-style inventory and health. Every visual is generated in code (micro-voxels, procedural textures, a bitmap font) and rendered through a PS1-style low-resolution pipeline.

- Design: [`GAME_DESIGN.md`](GAME_DESIGN.md)
- Conventions, commands, architecture: [`CLAUDE.md`](CLAUDE.md)
- Licenses of anything third-party: [`LICENSES.md`](LICENSES.md)
- Where things stand, the test plan and the backlog: [`docs/HANDOFF.md`](docs/HANDOFF.md)
- Release checklist: [`docs/RELEASE.md`](docs/RELEASE.md)

## Quick start

```powershell
# Windows
.\tools\godot.ps1 --path .          # play (downloads Godot 4.7.2 on first run)
.\tools\test.ps1                    # unit tests
```

```bash
# Linux / macOS
tools/godot.sh --path .
tools/test.sh && tools/smoke.sh
```

Play a planet directly: `tools/godot.sh --path . -- --planet=03 --seed=42` (`01` eclipse, `02` beach, `03` giants, `04` CO2 lake). Co-op on a LAN: `--host` on one machine, `--join=<ip>` on the other.

## Current state

All seven milestones are in: four playable planets with their rules (sunlight line-of-sight, flood + roach swarm, giant footfalls, heavy gas), streamed 1024² voxel worlds (infinite is a data switch), Tarkov-style inventory and body-part health, survival needs, crafting, day/night, save/load, villages with villagers to talk and trade with, enemies tied to each rule, ENet co-op with the Revival Ritual, a Steam bridge (achievements, cloud file calls) that is a no-op until the GodotSteam addon is dropped in (`docs/RELEASE.md`), and a release checklist. See the milestone list and decisions log in `GAME_DESIGN.md`.

## Known gaps

- Sounds are synthesised placeholders (`src/audio/sound_bank.gd`); no CC0 packs are bundled yet. Drop-in packs go in `LICENSES.md` first.
- Steam P2P transport (`SteamMultiplayerPeer`) is not wired; co-op is ENet/LAN.
- Balancing comes from headless runs and screenshots, not play sessions. Escalation plateaus at each mode's end by design.
- The Windows launcher and audio output were not exercised in CI (Linux headless only).
- Rafts/buoyancy on 02 and giants that interact with the world beyond walking are future work.
