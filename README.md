# Choose a Planet

A 3D survival game built with Godot 4.7.2: pick one of four planets from orbit, discover its deadly physical rule, and survive the day target. Minecraft-style digging and building, Natural-Disaster-Survival-style escalating events, Tarkov-style inventory and health. Every visual is generated in code (micro-voxels, procedural textures, a bitmap font) and rendered through a PS1-style low-resolution pipeline.

- Design: [`GAME_DESIGN.md`](GAME_DESIGN.md)
- Conventions, commands, architecture: [`CLAUDE.md`](CLAUDE.md)
- Licenses of anything third-party: [`LICENSES.md`](LICENSES.md)

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

Current state: Milestone 1 vertical slice on planet 04 (the CO2 lake planet). See the milestone list in `GAME_DESIGN.md`.
