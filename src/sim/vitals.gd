class_name Vitals
extends RefCounted
## Survival stats as pure logic. Milestone 1 wires oxygen (and a simple HP
## pool so suffocation can kill). Hunger/thirst/temperature/stamina fields
## exist so UI and data can target them; their drains land in Milestone 3,
## and Milestone 2 replaces `hp` with per-body-part health.

var oxygen: float = 1.0          # 0..1
var hunger: float = 1.0
var thirst: float = 1.0
var temperature: float = 37.0
var stamina: float = 1.0
var hp: float = 100.0
var max_hp: float = 100.0
var alive: bool = true
var suffocating: bool = false

var oxygen_seconds: float = 40.0        # full -> empty in clean air deprivation
var oxygen_recover_seconds: float = 8.0
var suffocation_dps: float = 7.0
var gas_threshold: float = 0.22          # concentration where breathing stops working

var last_damage_cause: String = ""


func configure(cfg: Dictionary) -> void:
	oxygen_seconds = float(cfg.get("oxygen_seconds", oxygen_seconds))
	oxygen_recover_seconds = float(cfg.get("oxygen_recover_seconds", oxygen_recover_seconds))
	suffocation_dps = float(cfg.get("suffocation_dps", suffocation_dps))
	gas_threshold = float(cfg.get("gas_threshold", gas_threshold))


## `gas` is the breathed concentration (0..1). Returns damage dealt this step.
func breathe(gas: float, dt: float) -> float:
	if not alive:
		return 0.0
	var dmg := 0.0
	var was_empty := oxygen <= 0.0
	if gas >= gas_threshold:
		# Thicker gas empties the lungs faster (up to 2x at full concentration).
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


func damage(amount: float, cause: String) -> void:
	if not alive or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	last_damage_cause = cause
	if hp <= 0.0:
		alive = false


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func to_dict() -> Dictionary:
	return {
		"oxygen": oxygen, "hunger": hunger, "thirst": thirst, "temperature": temperature,
		"stamina": stamina, "hp": hp, "max_hp": max_hp, "alive": alive, "suffocating": suffocating,
	}
