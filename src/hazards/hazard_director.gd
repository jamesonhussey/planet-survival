class_name HazardDirector
extends Node
## Server-side scheduler: instantiates each hazard listed in the planet JSON,
## triggers events on an escalating schedule, exposes debug triggers.
## Escalation curves are linear in day count with clamps:
##   interval_days = clamp(base + per_day * day, min, max)
##   intensity     = clamp(base + per_day * day, min, max)

const MODULES := {
	"heavy_gas": "res://src/hazards/heavy_gas_hazard.gd",
	"light_ray": "res://src/hazards/eclipse_hazard.gd",
	"flood": "res://src/hazards/flood_hazard.gd",
	"crush": "res://src/hazards/giant_hazard.gd",
}

var modules: Array[HazardModule] = []
var next_event_day: Dictionary = {}   # hazard id -> day_time of next trigger
var clock: GameClock
var world: WorldData
var context: Dictionary = {}
var enabled: bool = true


func setup(planet: Dictionary, world_data: WorldData, game_clock: GameClock, ctx: Dictionary) -> void:
	world = world_data
	clock = game_clock
	context = ctx
	context["planet"] = planet
	for h in planet.get("hazards", []):
		var module_name := str(h.get("module", ""))
		if not MODULES.has(module_name):
			push_error("[hazards] unknown module '%s' for hazard %s" % [module_name, h.get("id", "?")])
			continue
		var script: GDScript = load(MODULES[module_name])
		var m: HazardModule = script.new()
		m.name = str(h.get("id", module_name))
		add_child(m)
		m.setup(h, world, clock, context)
		modules.append(m)
		next_event_day[m.id] = float(h.get("first_event_day", 1.0))
	print("[hazards] %d module(s): %s" % [modules.size(), ", ".join(modules.map(func(x: HazardModule) -> String: return x.id))])


static func curve(c: Variant, day: float, fallback: float) -> float:
	if c is Dictionary:
		var d: Dictionary = c
		var v := float(d.get("base", fallback)) + float(d.get("per_day", 0.0)) * day
		return clampf(v, float(d.get("min", -1e9)), float(d.get("max", 1e9)))
	if c is float or c is int:
		return float(c)
	return fallback


func _process(_delta: float) -> void:
	if not enabled or clock == null:
		return
	var now := clock.day_time()
	for m in modules:
		if not m.is_idle():
			continue
		if now >= float(next_event_day.get(m.id, 1e9)):
			trigger(m, now)


## Multiplies the day fed to the curves (100 / mode day target): see run.gd.
var escalation_scale: float = 1.0


func trigger(m: HazardModule, now: float = -1.0) -> void:
	if now < 0.0:
		now = clock.day_time()
	var inten := curve(m.cfg.get("intensity", 1.0), now * escalation_scale, 1.0)
	m.trigger(inten)
	var interval := curve(m.cfg.get("interval_days", 2.0), now * escalation_scale, 2.0)
	next_event_day[m.id] = now + maxf(interval, 0.05)
	print("[hazards] %s triggered at day %.2f (intensity %.2f); next in %.2f days" % [m.id, now, inten, interval])


## Debug: fire the first idle hazard immediately (F5).
func debug_trigger_any() -> void:
	for m in modules:
		if m.is_idle():
			trigger(m)
			return
	EventBus.toast.emit("hazard already running", 1.5)


func get_module(hazard_id: String) -> HazardModule:
	for m in modules:
		if m.id == hazard_id:
			return m
	return null


func first() -> HazardModule:
	return modules[0] if modules.size() > 0 else null


func seconds_until_next(m: HazardModule) -> float:
	var days := float(next_event_day.get(m.id, 0.0)) - clock.day_time()
	return maxf(0.0, days * clock.minutes_per_day * 60.0 / maxf(clock.time_scale, 0.0001))
