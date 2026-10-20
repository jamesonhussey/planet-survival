class_name EclipseHazard
extends HazardModule
## Planet 01: the moon slides aside and the sun burns everything with a
## clear line to it. Warning: light creeps up (the moon's edge glows), then
## full exposure for the active phase. LightRaySim answers "is this spot
## lit" from the block grid; flammable blocks in the sun burn away.

var sim: LightRaySim
var tick_hz: float = 4.0
var region_radius: int = 28
var burn_dps: float = 9.0
var block_burn_rate: float = 0.08
var elevation_deg: float = 62.0
var azimuth: float = 0.6
var azimuth_drift: float = 0.15
var light_factor: float = 0.0     # 0 = eclipse dark, 1 = full sun
var rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var burned_total: int = 0


func _on_setup() -> void:
	var s: Dictionary = cfg.get("sim", {})
	sim = LightRaySim.new(world)
	sim.burn_threshold = float(s.get("burn_threshold", 0.35))
	tick_hz = float(s.get("tick_hz", 4.0))
	region_radius = int(s.get("region_radius", 28))
	burn_dps = float(s.get("burn_dps", 9.0))
	block_burn_rate = float(s.get("block_burn_rate", 0.08))
	elevation_deg = float(s.get("sun_elevation_degrees", 62.0))
	azimuth_drift = float(s.get("sun_azimuth_drift", 0.15))
	rng.seed = hash([world.world_size, id])
	sim.set_sun(sun_dir())


func sun_dir() -> Vector3:
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(azimuth) * cos(el), sin(el), sin(azimuth) * cos(el)).normalized()


func _on_phase(p: Phase) -> void:
	match p:
		Phase.IDLE:
			light_factor = 0.0
		Phase.WARNING:
			azimuth = rng.randf() * TAU
			sim.set_sun(sun_dir())
		Phase.ACTIVE:
			light_factor = 1.0


func _tick_warning(dt: float) -> void:
	light_factor = clampf(phase_time / maxf(warning_time(), 0.01), 0.0, 1.0) * 0.25
	azimuth += azimuth_drift * dt * 0.1
	sim.set_sun(sun_dir())


func _tick_active(dt: float) -> void:
	light_factor = 1.0
	azimuth += azimuth_drift * dt * 0.1
	sim.set_sun(sun_dir())
	_accum += dt
	var step := 1.0 / tick_hz
	var n := 0
	while _accum >= step and n < 2:
		_accum -= step
		n += 1
		var focus: Vector3 = Vector3.ZERO
		if context.has("player_position"):
			focus = (context["player_position"] as Callable).call()
		burned_total += sim.tick(Vector3i(focus.floor()), region_radius, block_burn_rate * intensity, rng)


func _tick_recovery(_dt: float) -> void:
	light_factor = maxf(0.0, 1.0 - phase_time / maxf(recovery_time(), 0.01))


func _recovery_done() -> bool:
	return phase_time >= recovery_time()


## Burn exposure 0..1 at a position: only the active phase burns.
func exposure_at(feet: Vector3, height: float = 1.7) -> float:
	if phase != Phase.ACTIVE:
		return 0.0
	return sim.exposure(feet, height) * (1.0 if sim.exposure(feet, height) >= sim.burn_threshold else 0.0)


func burn_damage_per_second() -> float:
	return burn_dps * intensity


## Parameters replicated to clients.
func net_params() -> Dictionary:
	return {"sun": sun_dir(), "light": light_factor}


func apply_remote_params(p: Dictionary) -> void:
	if p.has("sun"):
		sim.set_sun(p["sun"])
	light_factor = float(p.get("light", light_factor))
