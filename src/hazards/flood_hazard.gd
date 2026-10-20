class_name FloodHazard
extends HazardModule
## Planet 02: the storm. Warning: the tide pulls out. Active: the sea rises
## by `rise_blocks` (more with intensity), waves break weak blocks, and the
## flood drives roaches out of the sand toward anything dry and warm.
## Recovery: the water goes back, the swarm dies off.

var sim: FluidSim
var swarm: SwarmSim
var tick_hz: float = 2.0
var region_radius: int = 40
var rise_blocks: float = 9.0
var rise_per_intensity: float = 2.0
var tide_out_blocks: float = 2.0
var wave_force_base: float = 2.5
var wave_force_per_intensity: float = 1.5
var spawn_per_tick: int = 6
var rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var _swarm_accum: float = 0.0
var _field_accum: float = 0.0
var region_min: Vector3i
var region_max: Vector3i
var peak_level: float = 0.0
var bites_total: int = 0
var swarm_positions_remote: PackedVector3Array = PackedVector3Array()
var fluid_id: int = 10


func _on_setup() -> void:
	var s: Dictionary = cfg.get("sim", {})
	var planet: Dictionary = context.get("planet", {})
	var terrain: Dictionary = planet.get("terrain", {})
	fluid_id = Data.block_id(str(terrain.get("lake_fluid", "sea_water")))
	sim = FluidSim.new(world, float(terrain.get("sea_level", terrain.get("lake_level", 34))), fluid_id)
	swarm = SwarmSim.new(world)
	var sw: Dictionary = s.get("swarm", {})
	swarm.max_agents = int(sw.get("max_agents", 220))
	swarm.speed = float(sw.get("speed", 3.2))
	swarm.bite_damage = float(sw.get("bite_damage", 4.0))
	swarm.squeeze_factor = float(sw.get("squeeze_factor", 0.25))
	spawn_per_tick = int(sw.get("spawn_per_tick", 6))
	tick_hz = float(s.get("tick_hz", 2.0))
	region_radius = int(s.get("region_radius", 40))
	rise_blocks = float(s.get("rise_blocks", 9.0))
	rise_per_intensity = float(s.get("rise_per_intensity", 2.0))
	tide_out_blocks = float(s.get("tide_out_blocks", 2.0))
	wave_force_base = float(s.get("wave_force", 2.5))
	wave_force_per_intensity = float(s.get("wave_force_per_intensity", 1.5))
	rng.seed = hash([world.world_size, id, 2])


func _focus() -> Vector3:
	if context.has("player_position"):
		return (context["player_position"] as Callable).call()
	return Vector3.ZERO


func _all_players() -> Array:
	if context.has("player_positions"):
		return (context["player_positions"] as Callable).call()
	return [_focus()]


func _rebuild_region() -> void:
	var f := Vector3i(_focus().floor())
	region_min = Vector3i(f.x - region_radius, 0, f.z - region_radius)
	region_max = Vector3i(f.x + region_radius, world.world_height - 1, f.z + region_radius)
	sim.set_region(region_min, region_max)


func target_rise() -> float:
	return rise_blocks + rise_per_intensity * (intensity - 1.0)


func _on_phase(p: Phase) -> void:
	match p:
		Phase.WARNING:
			_rebuild_region()
			sim.wave_force = 0.0
		Phase.ACTIVE:
			sim.wave_force = wave_force_base + wave_force_per_intensity * (intensity - 1.0)
		Phase.RECOVERY:
			sim.wave_force = 0.0
		Phase.IDLE:
			sim.level = sim.base_level
			sim.wet.clear()
			swarm.clear()


func _tick_warning(dt: float) -> void:
	# The tide pulls out: the sea drops below its calm level.
	var t := clampf(phase_time / maxf(warning_time(), 0.01), 0.0, 1.0)
	sim.level = sim.base_level - tide_out_blocks * t
	_step(dt, false)


func _tick_active(dt: float) -> void:
	var at := active_time()
	var t := clampf(phase_time / maxf(at * 0.4, 0.01), 0.0, 1.0)
	sim.level = lerpf(sim.base_level - tide_out_blocks, sim.base_level + target_rise(), t)
	peak_level = maxf(peak_level, sim.level)
	if t >= 1.0:
		sim.wave_force = 0.0  # the surge is over; standing water holds
	_step(dt, true)


func _tick_recovery(dt: float) -> void:
	var t := clampf(phase_time / maxf(recovery_time(), 0.01), 0.0, 1.0)
	sim.level = lerpf(sim.base_level + target_rise(), sim.base_level, t)
	_step(dt, false)
	# The swarm thins out as the water goes.
	if rng.randf() < dt * 0.6:
		for a in swarm.agents:
			if a.alive and rng.randf() < 0.1:
				a.alive = false
		swarm.prune_dead()


func _recovery_done() -> bool:
	return phase_time >= recovery_time()


func _step(dt: float, spawning: bool) -> void:
	_accum += dt
	var step := 1.0 / tick_hz
	var n := 0
	while _accum >= step and n < 2:
		_accum -= step
		n += 1
		_rebuild_region()
		sim.tick(rng)
	# Swarm: field at 1 Hz, agents at 10 Hz.
	swarm.wet_cells = sim.wet
	_field_accum += dt
	if _field_accum >= 1.0:
		_field_accum = 0.0
		var targets: Array[Vector3i] = []
		for p in _all_players():
			targets.append(Vector3i((p as Vector3).floor()))
		swarm.targets = targets
		swarm.rebuild_field()
		if spawning:
			_spawn_from_front()
	_swarm_accum += dt
	while _swarm_accum >= 0.1:
		_swarm_accum -= 0.1
		var bites := swarm.tick(0.1, rng)
		for b in bites:
			bites_total += int(b[1])
		_pending_bites.append_array(bites)
var _pending_bites: Array = []


## Roaches come out of the sand where the water arrives, near players.
func _spawn_from_front() -> void:
	if swarm.agents.size() >= swarm.max_agents:
		return
	var candidates: Array[Vector3i] = []
	var focus := _focus()
	var tries := 0
	for p in sim.wet:
		tries += 1
		if tries > 4000:
			break
		var cell: Vector3i = p
		if absf(cell.x - focus.x) > 24 or absf(cell.z - focus.z) > 24:
			continue
		# A dry walkable neighbour above or beside the water line.
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
			var nb: Vector3i = cell + d
			if not sim.wet.has(nb) and swarm.walkable(nb):
				candidates.append(nb)
				break
		if candidates.size() >= 24:
			break
	if candidates.is_empty():
		return
	for i in spawn_per_tick:
		swarm.spawn(candidates[rng.randi_range(0, candidates.size() - 1)], int(ceil(intensity)), rng)


## Bites since the last call: [[cell, count], ...]
func take_bites() -> Array:
	var out := _pending_bites
	_pending_bites = []
	return out


func submersion(feet: Vector3, height: float = 1.7) -> int:
	return sim.submersion(feet, height)


func swarm_positions() -> PackedVector3Array:
	if client_mode:
		return swarm_positions_remote
	return swarm.positions()


func net_params() -> Dictionary:
	return {"level": sim.level}


func apply_remote_params(p: Dictionary) -> void:
	if p.has("level"):
		sim.level = float(p["level"])
		_rebuild_region()
		sim.wave_force = 0.0
		sim.tick()
