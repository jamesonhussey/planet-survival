class_name GiantHazard
extends HazardModule
## Planet 03: a giant walks past. Warning: tremors from far off, growing.
## Active: it crosses within `pass_distance` of the players, each footfall
## pressing the ground (CrushSim). Recovery: it walks away. The giant never
## hunts; it just does not look down. Clients replay the same footfalls from
## net params, so the ground matches everywhere.

var sim: CrushSim
var rng := RandomNumberGenerator.new()
var stride: float = 6.0
var step_interval: float = 2.2
var foot_radius: float = 2.2
var crush_force_base: float = 5.0
var crush_force_per_intensity: float = 0.6
var pass_distance_base: float = 18.0
var pass_distance_per_intensity: float = 4.0
var tremor_range: float = 70.0
var crush_damage: float = 400.0
var near_miss_damage: float = 18.0
var path_start: Vector2 = Vector2.ZERO
var path_end: Vector2 = Vector2(1, 0)
var walked: float = 0.0            # metres along the path
var _step_accum: float = 0.0
var step_count: int = 0            # footfalls so far this event (also the net sequence)
var left_foot: bool = true
var recent_steps: Array = []       # [[x, z, seq], ...] last few footfalls for clients
var blocks_crushed: int = 0
var footfall_seq_applied: int = 0  # client side

signal footfall(pos: Vector3, force: float, radius: float, seq: int)


func _on_setup() -> void:
	var s: Dictionary = cfg.get("sim", {})
	sim = CrushSim.new(world)
	stride = float(s.get("stride", 6.0))
	step_interval = float(s.get("step_interval", 2.2))
	foot_radius = float(s.get("foot_radius", 2.2))
	crush_force_base = float(s.get("crush_force", 5.0))
	crush_force_per_intensity = float(s.get("crush_force_per_intensity", 0.6))
	pass_distance_base = float(s.get("pass_distance", 18.0))
	pass_distance_per_intensity = float(s.get("pass_distance_per_intensity", 4.0))
	tremor_range = float(s.get("tremor_range", 70.0))
	crush_damage = float(s.get("crush_damage", 400.0))
	near_miss_damage = float(s.get("near_miss_damage", 18.0))
	rng.seed = hash([world.world_size, id, 3])


func speed() -> float:
	return stride / maxf(step_interval, 0.05)


func crush_force() -> float:
	return crush_force_base + crush_force_per_intensity * (intensity - 1.0)


func pass_distance() -> float:
	return maxf(6.0, pass_distance_base - pass_distance_per_intensity * (intensity - 1.0))


func _focus() -> Vector3:
	if context.has("player_position"):
		return (context["player_position"] as Callable).call()
	return Vector3.ZERO


func _all_players() -> Array:
	if context.has("player_positions"):
		return (context["player_positions"] as Callable).call()
	return [_focus()]


func _on_phase(p: Phase) -> void:
	match p:
		Phase.WARNING:
			if not client_mode:
				var f := _focus()
				# Closest approach lands mid-ACTIVE; start far enough to walk there.
				var before := speed() * (warning_time() + active_time() * 0.5)
				var after := speed() * (active_time() * 0.5 + recovery_time())
				var path := CrushSim.plan_path(Vector2(f.x, f.z), pass_distance(), before, after, rng)
				path_start = path["start"]
				path_end = path["end"]
			walked = 0.0
			_step_accum = 0.0
			step_count = 0
			recent_steps.clear()
			blocks_crushed = 0
			footfall_seq_applied = 0
			left_foot = true
		Phase.IDLE:
			recent_steps.clear()


func _tick_warning(dt: float) -> void:
	_walk(dt)


func _tick_active(dt: float) -> void:
	_walk(dt)


func _tick_recovery(dt: float) -> void:
	_walk(dt)


func _recovery_done() -> bool:
	return walked >= path_length()


func path_length() -> float:
	return path_start.distance_to(path_end)


func heading() -> Vector2:
	var d := path_end - path_start
	return d.normalized() if d.length() > 0.01 else Vector2(1, 0)


## Where the body is now (x, z on the path; y = ground under it).
func giant_position() -> Vector3:
	var p := path_start + heading() * minf(walked, path_length())
	var y := world.surface_y(int(floor(p.x)), int(floor(p.y)))
	return Vector3(p.x, float(y + 1) if y >= 0 else _focus().y, p.y)


## 0..1 within the current step (for the renderer's leg swing).
func step_phase() -> float:
	return clampf(_step_accum / maxf(step_interval, 0.05), 0.0, 1.0)


func _walk(dt: float) -> void:
	if walked >= path_length():
		return
	walked = minf(walked + speed() * dt, path_length())
	_step_accum += dt
	while _step_accum >= step_interval:
		_step_accum -= step_interval
		_do_step()


func _do_step() -> void:
	var h := heading()
	var side := Vector2(-h.y, h.x) * (2.6 if left_foot else -2.6)
	left_foot = not left_foot
	var p := path_start + h * minf(walked, path_length()) + side
	step_count += 1
	_apply_footfall(int(floor(p.x)), int(floor(p.y)), step_count)
	recent_steps.append([int(floor(p.x)), int(floor(p.y)), step_count])
	while recent_steps.size() > 6:
		recent_steps.pop_front()


func _apply_footfall(cx: int, cz: int, seq: int) -> void:
	var y := world.surface_y(cx, cz)
	if y >= 0:
		blocks_crushed += sim.footfall(cx, cz, foot_radius, crush_force())
	footfall.emit(Vector3(cx + 0.5, float(maxi(y, 0)), cz + 0.5), crush_force(), foot_radius, seq)


## Felt tremor at `pos` from the giant's last footfall position (0..1).
func tremor_at(pos: Vector3) -> float:
	var g := giant_position()
	return CrushSim.tremor(Vector2(pos.x, pos.z).distance_to(Vector2(g.x, g.z)), tremor_range)


func net_params() -> Dictionary:
	return {"sx": path_start.x, "sz": path_start.y, "ex": path_end.x, "ez": path_end.y, "w": walked, "p": step_phase(), "steps": recent_steps.duplicate()}


func apply_remote_params(p: Dictionary) -> void:
	path_start = Vector2(float(p.get("sx", 0)), float(p.get("sz", 0)))
	path_end = Vector2(float(p.get("ex", 1)), float(p.get("ez", 0)))
	walked = float(p.get("w", 0))
	_step_accum = float(p.get("p", 0)) * step_interval
	for s in p.get("steps", []):
		var seq := int(s[2])
		if seq > footfall_seq_applied:
			footfall_seq_applied = seq
			_apply_footfall(int(s[0]), int(s[1]), seq)
