class_name HeavyGasHazard
extends HazardModule
## Planet 04's limnic eruption: drives a GasSim from lake-surface sources in
## an active region around the players. Warning: bubbling, tremors. Active:
## emission. Recovery: emission stops, gas dissipates.

var sim: GasSim
var fluid_id: int = 10
var tick_hz: float = 6.0
var region_margin: int = 40
var _accum: float = 0.0
var region_min: Vector3i
var region_max: Vector3i
var source_count: int = 0
var peak_cells: int = 0
var peak_mass: float = 0.0


func _on_setup() -> void:
	var sim_cfg: Dictionary = cfg.get("sim", {})
	sim = GasSim.new(world, sim_cfg)
	tick_hz = float(sim_cfg.get("tick_hz", 6.0))
	region_margin = int(sim_cfg.get("region_margin", 40))
	var planet: Dictionary = context.get("planet", {})
	var terrain: Dictionary = planet.get("terrain", {})
	fluid_id = Data.block_id(str(terrain.get("lake_fluid", "co2_water")))


func _on_phase(p: Phase) -> void:
	match p:
		Phase.WARNING:
			_rebuild_region()
			sim.intensity = intensity
			sim.emitting = false
		Phase.ACTIVE:
			sim.emitting = true
		Phase.RECOVERY:
			sim.emitting = false
		Phase.IDLE:
			sim.emitting = false
			sim.clear()


## Region = box around the focus (player) covering nearby lakes. Sources are
## the air cells above lake fluid in that box (loaded chunks only).
func _rebuild_region() -> void:
	var focus: Vector3 = Vector3.ZERO
	if context.has("player_position"):
		focus = (context["player_position"] as Callable).call()
	var f := Vector3i(focus.floor())
	region_min = Vector3i(f.x - region_margin, 0, f.z - region_margin)
	region_max = Vector3i(f.x + region_margin, world.world_height - 1, f.z + region_margin)
	sim.set_region(region_min, region_max)
	var lake_level: int = int((context.get("planet", {}) as Dictionary).get("terrain", {}).get("lake_level", 40))
	source_count = sim.collect_sources_from_fluid(fluid_id, Vector3i(region_min.x, maxi(0, lake_level - 6), region_min.z), Vector3i(region_max.x, lake_level + 2, region_max.z), int(cfg.get("sim", {}).get("max_sources", 3000)))
	if source_count > 0:
		var c := Vector3.ZERO
		for s in sim.sources:
			c += Vector3(s)
		c /= float(source_count)
		print("[gas] %d lake-surface sources around %s (focus %s)" % [source_count, str(c.floor()), str(f)])
	else:
		print("[gas] no lake within %d blocks of %s; this eruption happens elsewhere" % [region_margin, str(f)])


func _decorate_cue(payload: Dictionary) -> void:
	if payload.get("type", "") == "lake_bubbles":
		var pts: Array = []
		var n := mini(sim.sources.size(), 24)
		if n > 0:
			var stride := maxi(1, sim.sources.size() / n)
			for i in range(0, sim.sources.size(), stride):
				pts.append(sim.sources[i])
		payload["points"] = pts


func _tick_active(dt: float) -> void:
	_step(dt)


func _tick_recovery(dt: float) -> void:
	_step(dt)


func _recovery_done() -> bool:
	return sim.cells.is_empty() and phase_time > 2.0


func _step(dt: float) -> void:
	_accum += dt
	var step := 1.0 / tick_hz
	var n := 0
	while _accum >= step and n < 4:
		_accum -= step
		sim.tick()
		n += 1
	peak_cells = maxi(peak_cells, sim.cells.size())
	peak_mass = maxf(peak_mass, sim.total_mass)


## Concentration an entity standing at `feet` breathes.
func exposure_at(feet: Vector3, height: float = 1.7) -> float:
	return sim.exposure(feet, height)
