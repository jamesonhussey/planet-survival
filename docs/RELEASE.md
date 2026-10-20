# Release checklist

Everything below is scripted or data; nothing needs the editor.

## Before every build
1. `tools/test.sh` and `tools/smoke.sh` (all four planets) pass; `tools/nettest.sh` passes (host + client).
2. `tools/screenshot.sh 01|02|03|04 150` and a look at `screenshots/` for the PS1 look (dither, fog, palette) after any render change.
3. `data/` validates on boot (the smoke test fails on validation errors). New items/materials/recipes have entries, new third-party pieces are in `LICENSES.md`.
4. `GAME_DESIGN.md` decisions log updated for anything a player would notice.

## Builds
- `tools/build.sh windows|linux|all` (or `tools\build.ps1`) runs `--export-release` with `export_presets.cfg`; templates are fetched on first use.
- The exported game must ship Godot's license and third-party notices (`LICENSES.md` + the engine's Help → About text).
- Run the Linux export headless once: `./build/linux/*.x86_64 --headless -- --smoke --planet=04 --frames=120`.

## Steam (optional per build)
1. `GODOTSTEAM_URL=<GDExtension zip from the GodotSteam releases page, the one marked for Godot 4.7> tools/get_godotsteam.sh` unpacks the GodotSteam GDExtension into `addons/godotsteam/` (gitignored). Without it `SteamBridge` is a no-op and achievements stay local in `user://achievements.json`.
2. Set `SteamBridge.app_id` (`src/steam/steam_bridge.gd`) to the real app id; keep `480` (Spacewar) for testing. Put `steam_appid.txt` beside the executable for local runs.
3. Achievements: create the ids from `data/achievements.json` in the Steamworks dashboard (same ids). They unlock through `EventBus.achievement(id)`.
4. Cloud saves: enable Steam Auto-Cloud for `user://saves/` (Godot's user dir) in the dashboard, or call `SteamBridge.cloud_write/cloud_read` from `SaveSystem` for explicit sync.
5. Lobbies/P2P: `SteamBridge.create_lobby/join_lobby` are stubs. The transport swap is `SteamMultiplayerPeer` in `src/net/net.gd` (same `MultiplayerPeer` interface as ENet); until then co-op is ENet/LAN (`--host`, `--join=ip`).
6. Depots: one per preset (Windows x86_64, Linux x86_64). Launch options: default (no args).

## Tag and ship
- Bump `config/version` in `project.godot`, tag `vX.Y`, CI green on the tag.
- Note known gaps in the release notes (see README "Known gaps").
