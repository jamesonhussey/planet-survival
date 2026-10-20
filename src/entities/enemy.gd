class_name Enemy
extends Creature
## A planet enemy driven by data/enemies.json: chases the nearest target it
## can see, attacks in melee, and obeys its planet's rule through flags:
##   hunts_in: "gas" | "dark" | "any"   flee: "light" | "water" | ""   burns
## The run feeds it perception (targets, light/gas/water at its position).

var cfg: Dictionary = {}
var damage: float = 6.0
var attack_interval: float = 1.4
var sight: float = 20.0
var _attack_cooldown: float = 0.0
var target_pos: Vector3 = Vector3.ZERO
var has_target: bool = false
var hostile: bool = true
## Perception set by the run each tick.
var env_gas: float = 0.0
var env_light: float = 0.0     # 0 dark .. 1 burning sun
var env_wet: bool = false
var env_dry_dir: Vector3 = Vector3.ZERO

signal attacked(target_pos: Vector3, amount: float)


func setup_enemy(enemy_cfg: Dictionary) -> void:
	cfg = enemy_cfg
	damage = float(cfg.get("damage", 6.0))
	attack_interval = float(cfg.get("attack_interval", 1.4))
	sight = float(cfg.get("sight", 20.0))
	speed = float(cfg.get("speed", 3.0))
	breathes = bool(cfg.get("breathes", true))
	vitals.hp = float(cfg.get("hp", 30.0))
	vitals.max_hp = vitals.hp
	drops = cfg.get("drops", [])


func perceive(targets: Array, gas: float, light: float, wet: bool) -> void:
	env_gas = gas
	env_light = light
	env_wet = wet
	has_target = false
	var best := sight
	for t in targets:
		var d := (t as Vector3).distance_to(global_position)
		if d < best:
			best = d
			target_pos = t
			has_target = true


func _brain(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var flee := str(cfg.get("flee", ""))
	# Rule-driven retreat beats hunting.
	if flee == "light" and env_light > 0.3:
		# Run from the light: away from the target (toward wherever is darker
		# is unknown here; the run despawns us when fully exposed).
		if has_target:
			var away := global_position - target_pos
			away.y = 0.0
			wander_dir = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
			moving = true
			return
	if flee == "water" and env_wet:
		if env_dry_dir.length_squared() > 0.0:
			wander_dir = env_dry_dir
			moving = true
			return
	var hunts := str(cfg.get("hunts_in", "any"))
	var may_hunt := true
	if hunts == "gas" and env_gas < 0.05:
		may_hunt = false
	if hunts == "dark" and env_light > 0.3:
		may_hunt = false
	if has_target and may_hunt and hostile:
		var d := target_pos - global_position
		d.y = 0.0
		if d.length() <= 1.6:
			moving = false
			wander_dir = d.normalized()
			rotation.y = lerp_angle(rotation.y, atan2(-wander_dir.z, wander_dir.x), 10.0 * delta)
			if _attack_cooldown <= 0.0:
				_attack_cooldown = attack_interval
				attacked.emit(target_pos, damage)
			return
		go_toward(target_pos, 1.4)
		return
	super._brain(delta)


func _on_hit(_from: Vector3) -> void:
	# Enemies do not flee when hit; they turn on you.
	flee_timer = 0.0
