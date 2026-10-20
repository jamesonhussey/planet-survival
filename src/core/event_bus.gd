extends Node
## Global signal hub (autoload "EventBus"). Systems talk through these signals
## instead of holding references to each other. Keep payloads plain data.

# Hazard lifecycle. phase is HazardModule.Phase.
signal hazard_phase_changed(hazard_id: String, phase: int, intensity: float)
signal hazard_cue(hazard_id: String, cue: Dictionary)

# World edits (already applied by the server; renderers react).
signal block_changed(pos: Vector3i, old_id: int, new_id: int)
signal chunk_loaded(cpos: Vector3i)
signal chunk_unloaded(cpos: Vector3i)

# Time.
signal day_changed(day: int)
signal hour_changed(hour: int)

# Player vitals / health. values are plain dictionaries.
signal vitals_changed(vitals: Dictionary)
signal player_died(cause: String)
signal player_damaged(part: String, amount: float, kind: String)

# UI / flow.
signal run_started(planet_id: String, mode_id: String)
signal run_ended(won: bool, day: int)
signal toast(text: String, seconds: float)
signal render_settings_reloaded(settings: Dictionary)
