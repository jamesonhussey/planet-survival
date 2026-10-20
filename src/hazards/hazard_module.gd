class_name HazardModule
extends Node
## Base class for every planet hazard. A data-configured state machine:
##   IDLE -> WARNING (telegraph cues) -> ACTIVE (the rule applies) -> RECOVERY -> IDLE
## Subclasses implement the simulation hooks. Runs only on the server; the
## director triggers it and the Telegraph turns cues into sound/visuals.
## Cue entries come from the planet JSON: {"t": seconds_into_phase, "type": ..., ...}

enum Phase { IDLE, WARNING, ACTIVE, RECOVERY }

var id: String = "hazard"
var cfg: Dictionary = {}
var phase: Phase = Phase.IDLE
var phase_time: float = 0.0
var intensity: float = 1.0
var world: WorldData
var clock: GameClock
var context: Dictionary = {}      # shared refs: "player_position": Callable, "planet": Dictionary
var events_so_far: int = 0

var _cue_index: int = 0
var _cues: Array = []

signal phase_changed(hazard_id: String, phase: int, intensity: float)
signal cue(hazard_id: String, cue: Dictionary)


func setup(hazard_cfg: Dictionary, world_data: WorldData, game_clock: GameClock, ctx: Dictionary) -> void:
	cfg = hazard_cfg
	id = str(cfg.get("id", "hazard"))
	world = world_data
	clock = game_clock
	context = ctx
	_on_setup()


func warning_time() -> float:
	return float(cfg.get("warning_time", 30.0))


func active_time() -> float:
	return float(cfg.get("active_time", 60.0)) * (1.0 + 0.25 * (intensity - 1.0))


func recovery_time() -> float:
	return float(cfg.get("recovery_time", 60.0))


func is_idle() -> bool:
	return phase == Phase.IDLE


## Start an event. Always begins with the warning phase: deaths must be fair.
func trigger(event_intensity: float = 1.0) -> void:
	if phase != Phase.IDLE:
		return
	intensity = maxf(0.1, event_intensity)
	events_so_far += 1
	_enter(Phase.WARNING)


func cancel() -> void:
	if phase == Phase.IDLE:
		return
	_enter(Phase.IDLE)


func _enter(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	_cue_index = 0
	_cues = []
	var cues_cfg: Dictionary = cfg.get("cues", {})
	match p:
		Phase.WARNING: _cues = cues_cfg.get("warning", [])
		Phase.ACTIVE: _cues = cues_cfg.get("active", [])
		Phase.RECOVERY: _cues = cues_cfg.get("recovery", [])
	_cues = _cues.duplicate()
	_cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0)) < float(b.get("t", 0)))
	_on_phase(p)
	phase_changed.emit(id, p, intensity)
	EventBus.hazard_phase_changed.emit(id, p, intensity)
	_fire_due_cues()


func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		_tick_idle(delta)
		return
	var scaled := delta * (clock.time_scale if clock != null else 1.0)
	phase_time += scaled
	_fire_due_cues()
	match phase:
		Phase.WARNING:
			_tick_warning(scaled)
			if phase_time >= warning_time():
				_enter(Phase.ACTIVE)
		Phase.ACTIVE:
			_tick_active(scaled)
			if phase_time >= active_time():
				_enter(Phase.RECOVERY)
		Phase.RECOVERY:
			_tick_recovery(scaled)
			if phase_time >= recovery_time() or _recovery_done():
				_enter(Phase.IDLE)


func _fire_due_cues() -> void:
	while _cue_index < _cues.size() and float(_cues[_cue_index].get("t", 0)) <= phase_time:
		var c: Dictionary = _cues[_cue_index]
		_cue_index += 1
		var payload := c.duplicate()
		payload["hazard"] = id
		payload["phase"] = phase
		payload["intensity"] = intensity
		_decorate_cue(payload)
		cue.emit(id, payload)
		EventBus.hazard_cue.emit(id, payload)


## Fraction of the current phase elapsed (for UI).
func phase_progress() -> float:
	match phase:
		Phase.WARNING: return clampf(phase_time / maxf(warning_time(), 0.01), 0, 1)
		Phase.ACTIVE: return clampf(phase_time / maxf(active_time(), 0.01), 0, 1)
		Phase.RECOVERY: return clampf(phase_time / maxf(recovery_time(), 0.01), 0, 1)
	return 0.0


# ---- hooks for subclasses ----
func _on_setup() -> void: pass
func _on_phase(_p: Phase) -> void: pass
func _tick_idle(_dt: float) -> void: pass
func _tick_warning(_dt: float) -> void: pass
func _tick_active(_dt: float) -> void: pass
func _tick_recovery(_dt: float) -> void: pass
func _recovery_done() -> bool: return false
## Lets a subclass attach positions etc. to a cue before it is emitted.
func _decorate_cue(_payload: Dictionary) -> void: pass
