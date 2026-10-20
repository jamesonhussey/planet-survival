class_name Vitals
extends RefCounted
## Survival stats as pure logic: oxygen, hunger, thirst, body temperature,
## stamina. Each is 0..1 except temperature (degrees C). Damage is routed
## through `damage_sink` (the player's BodyHealth) when set, otherwise into a
## simple `hp` pool (creatures). Rates are in game-seconds; the caller passes
## dt already scaled by the clock.

var oxygen: float = 1.0
var hunger: float = 1.0          # 1 = full, 0 = starving
var thirst: float = 1.0          # 1 = hydrated, 0 = parched
var temperature: float = 37.0    # body core temperature
var stamina: float = 1.0
var hp: float = 100.0
var max_hp: float = 100.0
var alive: bool = true
var suffocating: bool = false
var starving: bool = false
var dehydrated: bool = false
var cold: bool = false
var hot: bool = false
var exhausted: bool = false

# Oxygen (real seconds, scaled by the caller).
var oxygen_seconds: float = 40.0
var oxygen_recover_seconds: float = 8.0
var suffocation_dps: float = 7.0
var gas_threshold: float = 0.22
# Hunger/thirst: game hours from full to empty.
var hunger_hours: float = 36.0
var thirst_hours: float = 20.0
# Damage while a need sits at zero, in HP per game hour.
var starvation_hp_per_hour: float = 6.0
var dehydration_hp_per_hour: float = 10.0
# Temperature.
var comfort_temp: float = 20.0   # ambient where the body holds 37
var temp_drift_rate: float = 0.004  # degrees per game-second per degree of difference
var cold_threshold: float = 35.0
var hot_threshold: float = 39.5
var cold_hp_per_hour: float = 12.0
var hot_hp_per_hour: float = 10.0
# Stamina.
var sprint_drain: float = 0.12   # per real second while sprinting
var stamina_regen: float = 0.18  # per real second

var last_damage_cause: String = ""
## When set, damage is routed here (e.g. into a BodyHealth) instead of `hp`.
var damage_sink: Callable = Callable()


func configure(cfg: Dictionary) -> void:
	oxygen_seconds = float(cfg.get("oxygen_seconds", oxygen_seconds))
	oxygen_recover_seconds = float(cfg.get("oxygen_recover_seconds", oxygen_recover_seconds))
	suffocation_dps = float(cfg.get("suffocation_dps", suffocation_dps))
	gas_threshold = float(cfg.get("gas_threshold", gas_threshold))
	hunger_hours = float(cfg.get("hunger_hours", hunger_hours))
	thirst_hours = float(cfg.get("thirst_hours", thirst_hours))
	starvation_hp_per_hour = float(cfg.get("starvation_hp_per_hour", starvation_hp_per_hour))
	dehydration_hp_per_hour = float(cfg.get("dehydration_hp_per_hour", dehydration_hp_per_hour))
	comfort_temp = float(cfg.get("comfort_temp", comfort_temp))
	temp_drift_rate = float(cfg.get("temp_drift_rate", temp_drift_rate))
	cold_threshold = float(cfg.get("cold_threshold", cold_threshold))
	hot_threshold = float(cfg.get("hot_threshold", hot_threshold))
	cold_hp_per_hour = float(cfg.get("cold_hp_per_hour", cold_hp_per_hour))
	hot_hp_per_hour = float(cfg.get("hot_hp_per_hour", hot_hp_per_hour))
	sprint_drain = float(cfg.get("sprint_drain", sprint_drain))
	stamina_regen = float(cfg.get("stamina_regen", stamina_regen))


## `gas` is the breathed concentration (0..1). Returns damage dealt this step.
func breathe(gas: float, dt: float) -> float:
	if not alive:
		return 0.0
	var dmg := 0.0
	var was_empty := oxygen <= 0.0
	if gas >= gas_threshold:
		var severity := 1.0 + clampf((gas - gas_threshold) / maxf(1.0 - gas_threshold, 0.01), 0.0, 1.0)
		oxygen = maxf(0.0, oxygen - dt * severity / oxygen_seconds)
		suffocating = true
	else:
		oxygen = minf(1.0, oxygen + dt / oxygen_recover_seconds)
		suffocating = false
	if was_empty and oxygen <= 0.0:
		dmg = suffocation_dps * dt
		damage(dmg, "suffocation")
	return dmg


## Hunger, thirst and temperature over `dt_game` game-seconds given the
## environment: {"ambient": degrees C at the player, "sheltered": bool,
## "heat_source": 0..1 nearby fire strength}. Returns total damage dealt.
func metabolize(dt_game: float, env: Dictionary = {}) -> float:
	if not alive:
		return 0.0
	var dmg := 0.0
	# Only the part of the step spent at zero deals damage.
	var hunger_empty_time := maxf(0.0, dt_game - hunger * hunger_hours * 3600.0)
	var thirst_empty_time := maxf(0.0, dt_game - thirst * thirst_hours * 3600.0)
	hunger = maxf(0.0, hunger - dt_game / (hunger_hours * 3600.0))
	thirst = maxf(0.0, thirst - dt_game / (thirst_hours * 3600.0))
	starving = hunger <= 0.0
	dehydrated = thirst <= 0.0
	if hunger_empty_time > 0.0:
		var d := starvation_hp_per_hour / 3600.0 * hunger_empty_time
		dmg += d
		damage(d, "starvation")
	if thirst_empty_time > 0.0:
		var d := dehydration_hp_per_hour / 3600.0 * thirst_empty_time
		dmg += d
		damage(d, "dehydration")
	# Temperature: the body is pulled toward 37 + (felt - comfort) * 0.25.
	var ambient := float(env.get("ambient", comfort_temp))
	var felt := ambient
	if bool(env.get("sheltered", false)):
		felt += 6.0 if ambient < comfort_temp else -3.0
	felt += 18.0 * clampf(float(env.get("heat_source", 0.0)), 0.0, 1.0)
	var target := 37.0 + (felt - comfort_temp) * 0.25
	temperature = move_toward(temperature, target, absf(target - temperature) * temp_drift_rate * dt_game)
	cold = temperature < cold_threshold
	hot = temperature > hot_threshold
	if temperature < cold_threshold - 2.0:
		var d := cold_hp_per_hour / 3600.0 * dt_game
		dmg += d
		damage(d, "hypothermia")
	elif temperature > hot_threshold + 1.5:
		var d := hot_hp_per_hour / 3600.0 * dt_game
		dmg += d
		damage(d, "heatstroke")
	return dmg


## Stamina over real seconds. `effort` 1 while sprinting, 0 otherwise.
func exert(dt: float, sprinting: bool, carry_factor: float = 1.0) -> void:
	if sprinting:
		stamina = maxf(0.0, stamina - sprint_drain * dt * carry_factor)
	else:
		var regen := stamina_regen * (0.5 if (hunger < 0.2 or thirst < 0.2) else 1.0)
		stamina = minf(1.0, stamina + regen * dt)
	exhausted = stamina <= 0.05


func can_sprint() -> bool:
	return stamina > 0.1 and not exhausted


## Apply a food/drink definition: {"hunger": +x, "thirst": +y, "temperature": +z}.
func consume(effect: Dictionary) -> void:
	hunger = clampf(hunger + float(effect.get("hunger", 0.0)), 0.0, 1.0)
	thirst = clampf(thirst + float(effect.get("thirst", 0.0)), 0.0, 1.0)
	temperature = clampf(temperature + float(effect.get("temperature", 0.0)), 30.0, 42.0)
	stamina = clampf(stamina + float(effect.get("stamina", 0.0)), 0.0, 1.0)


## Speed multiplier from hunger/thirst/temperature/exhaustion.
func speed_factor() -> float:
	var f := 1.0
	if starving:
		f *= 0.85
	if dehydrated:
		f *= 0.8
	if cold:
		f *= 0.9
	if exhausted:
		f *= 0.7
	return f


func damage(amount: float, cause: String) -> void:
	if not alive or amount <= 0.0:
		return
	last_damage_cause = cause
	if damage_sink.is_valid():
		damage_sink.call(amount, cause)
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		alive = false


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func to_dict() -> Dictionary:
	return {
		"oxygen": oxygen, "hunger": hunger, "thirst": thirst, "temperature": temperature,
		"stamina": stamina, "hp": hp, "max_hp": max_hp, "alive": alive, "suffocating": suffocating,
		"starving": starving, "dehydrated": dehydrated, "cold": cold, "hot": hot, "exhausted": exhausted,
	}


func from_dict(d: Dictionary) -> void:
	oxygen = float(d.get("oxygen", 1.0))
	hunger = float(d.get("hunger", 1.0))
	thirst = float(d.get("thirst", 1.0))
	temperature = float(d.get("temperature", 37.0))
	stamina = float(d.get("stamina", 1.0))
	hp = float(d.get("hp", hp))
	alive = bool(d.get("alive", true))
