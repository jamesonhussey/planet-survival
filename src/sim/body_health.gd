class_name BodyHealth
extends RefCounted
## Tarkov-style per-part health. Seven parts with their own HP pools. Head or
## thorax at 0 = death. A blacked-out limb takes no further damage itself:
## incoming damage spreads to the other parts. Status effects live here with
## timers; meds are applied via apply_med() from data/items.json definitions.
## Pure logic, unit tested.

const PARTS: Array[String] = ["head", "thorax", "stomach", "left_arm", "right_arm", "left_leg", "right_leg"]
const LIMBS: Array[String] = ["left_arm", "right_arm", "left_leg", "right_leg"]
const DEFAULT_MAX := {"head": 35.0, "thorax": 85.0, "stomach": 70.0, "left_arm": 60.0, "right_arm": 60.0, "left_leg": 65.0, "right_leg": 65.0}
## Fraction of damage to a blacked part that spreads to the rest.
const BLACKOUT_SPREAD := 0.7
## Effects: type -> {dps (per part), duration (-1 = until treated)}
const EFFECT_DEFS := {
	"light_bleed": {"dps": 0.5, "duration": -1.0, "pain": 1.0},
	"heavy_bleed": {"dps": 1.6, "duration": -1.0, "pain": 2.0},
	"fracture": {"dps": 0.0, "duration": -1.0, "pain": 2.0},
	"burn": {"dps": 0.4, "duration": 30.0, "pain": 1.5},
	"pain": {"dps": 0.0, "duration": 60.0, "pain": 0.0},
	"painkillers": {"dps": 0.0, "duration": 180.0, "pain": 0.0},
	"suffocation": {"dps": 0.0, "duration": 2.0, "pain": 0.0},
	"dehydration": {"dps": 0.15, "duration": -1.0, "pain": 0.5},
	"poison": {"dps": 0.3, "duration": 90.0, "pain": 1.0},
}

var hp: Dictionary = {}
var max_hp: Dictionary = {}
var effects: Array = []     # [{type, part, time_left}]
var alive: bool = true
var death_cause: String = ""
var damage_log: Array = []  # last few (part, amount, kind) for UI/tests

signal part_changed(part: String, hp: float, max_hp: float)
signal effect_added(type: String, part: String)
signal effect_removed(type: String, part: String)
signal died(cause: String)


func _init(max_override: Dictionary = {}) -> void:
	for p in PARTS:
		max_hp[p] = float(max_override.get(p, DEFAULT_MAX[p]))
		hp[p] = max_hp[p]


func is_blacked(part: String) -> bool:
	return float(hp.get(part, 0.0)) <= 0.0


func total_hp() -> float:
	var t := 0.0
	for p in PARTS:
		t += float(hp[p])
	return t


func total_max() -> float:
	var t := 0.0
	for p in PARTS:
		t += float(max_hp[p])
	return t


func has_effect(type: String, part: String = "") -> bool:
	for e in effects:
		if e["type"] == type and (part == "" or e["part"] == part):
			return true
	return false


func effects_on(part: String) -> Array:
	var out: Array = []
	for e in effects:
		if e["part"] == part:
			out.append(e)
	return out


## Pain level 0..n from untreated effects, 0 while painkillers are active.
func pain() -> float:
	if has_effect("painkillers"):
		return 0.0
	var p := 0.0
	for e in effects:
		p += float(EFFECT_DEFS.get(e["type"], {}).get("pain", 0.0))
	return p


func add_effect(type: String, part: String = "thorax", duration: float = -2.0) -> void:
	if not EFFECT_DEFS.has(type):
		return
	if has_effect(type, part):
		# refresh timer
		for e in effects:
			if e["type"] == type and e["part"] == part:
				e["time_left"] = duration if duration > -2.0 else float(EFFECT_DEFS[type]["duration"])
		return
	var d := duration if duration > -2.0 else float(EFFECT_DEFS[type]["duration"])
	effects.append({"type": type, "part": part, "time_left": d})
	effect_added.emit(type, part)


func remove_effect(type: String, part: String = "") -> int:
	var n := 0
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		if e["type"] == type and (part == "" or e["part"] == part):
			effects.remove_at(i)
			effect_removed.emit(type, e["part"])
			n += 1
	return n


## Apply damage to one part. Damage to a blacked part spreads to the others.
## `kind` drives status effects: cut -> bleeds, blunt -> fractures, burn -> burn.
func damage(part: String, amount: float, kind: String = "generic", rng: RandomNumberGenerator = null) -> void:
	if not alive or amount <= 0.0 or not hp.has(part):
		return
	damage_log.append([part, amount, kind])
	if damage_log.size() > 32:
		damage_log.pop_front()
	if is_blacked(part):
		_spread(amount * BLACKOUT_SPREAD, part, kind)
		return
	var before: float = hp[part]
	hp[part] = maxf(0.0, before - amount)
	part_changed.emit(part, hp[part], max_hp[part])
	_roll_effects(part, amount, kind, rng)
	if hp[part] <= 0.0:
		if part == "head" or part == "thorax":
			_die(kind)
			return
		# A limb just blacked out: the overflow spreads.
		var overflow: float = amount - before
		if overflow > 0.0:
			_spread(overflow * BLACKOUT_SPREAD, part, kind)
		add_effect("pain", part)


func _spread(amount: float, from_part: String, kind: String) -> void:
	var targets: Array[String] = []
	for p in PARTS:
		if p != from_part and not is_blacked(p):
			targets.append(p)
	if targets.is_empty():
		_die(kind)
		return
	var each := amount / float(targets.size())
	for p in targets:
		hp[p] = maxf(0.0, float(hp[p]) - each)
		part_changed.emit(p, hp[p], max_hp[p])
		if hp[p] <= 0.0 and (p == "head" or p == "thorax"):
			_die(kind)
			return


## Damage split over the whole body (suffocation, poison, cold).
func damage_all(amount: float, kind: String, head_share: float = 0.3) -> void:
	damage("head", amount * head_share, kind)
	damage("thorax", amount * (1.0 - head_share), kind)


func _roll_effects(part: String, amount: float, kind: String, rng: RandomNumberGenerator) -> void:
	var roll := rng.randf() if rng != null else 0.5
	match kind:
		"cut", "bite":
			if amount >= 12.0 or roll < amount / 25.0:
				add_effect("heavy_bleed" if amount >= 20.0 else "light_bleed", part)
		"blunt", "fall", "crush":
			if LIMBS.has(part) and (amount >= 25.0 or roll < amount / 60.0):
				add_effect("fracture", part)
			if amount >= 8.0:
				add_effect("pain", part)
		"burn":
			add_effect("burn", part)
		"suffocation":
			add_effect("suffocation", "thorax", 2.0)
	if amount >= 15.0:
		add_effect("pain", part)


func _die(cause: String) -> void:
	if not alive:
		return
	alive = false
	death_cause = cause
	died.emit(cause)


## Advance timed effects and apply damage over time.
func tick(dt: float) -> void:
	if not alive:
		return
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		var d: Dictionary = EFFECT_DEFS[e["type"]]
		var dps := float(d["dps"])
		if dps > 0.0:
			var part: String = e["part"]
			if is_blacked(part):
				_spread(dps * dt * BLACKOUT_SPREAD, part, e["type"])
			else:
				hp[part] = maxf(0.0, float(hp[part]) - dps * dt)
				part_changed.emit(part, hp[part], max_hp[part])
				if hp[part] <= 0.0 and (part == "head" or part == "thorax"):
					_die(e["type"])
					return
		if float(e["time_left"]) >= 0.0:
			e["time_left"] = float(e["time_left"]) - dt
			if float(e["time_left"]) <= 0.0:
				effects.remove_at(i)
				effect_removed.emit(e["type"], e["part"])


## Movement/carry/aim penalties from the current state.
func penalties() -> Dictionary:
	var move := 1.0
	var carry := 1.0
	var shake := 0.0
	for leg in ["left_leg", "right_leg"]:
		if is_blacked(leg):
			move *= 0.55
		elif has_effect("fracture", leg):
			move *= 0.8
	for arm in ["left_arm", "right_arm"]:
		if is_blacked(arm):
			carry *= 0.7
			shake += 0.5
		elif has_effect("fracture", arm):
			carry *= 0.85
			shake += 0.25
	var p := pain()
	shake += minf(p * 0.15, 0.6)
	if p >= 3.0:
		move *= 0.9
	if is_blacked("stomach"):
		move *= 0.9
	return {"move_speed": move, "carry": carry, "aim_shake": shake, "pain": p}


## Check whether a med item (its data def) can be used on a part. Returns
## {"ok": bool, "reason": String, "use_time": float}.
func med_plan(def: Dictionary, part: String, uses_left: int, hp_pool: float) -> Dictionary:
	var kind := str(def.get("med", ""))
	var use_time := float(def.get("use_time", 2.0))
	if kind == "":
		return {"ok": false, "reason": "not a medical item", "use_time": 0.0}
	if uses_left <= 0 and kind != "medkit":
		return {"ok": false, "reason": "used up", "use_time": 0.0}
	if kind == "medkit" and hp_pool <= 0.0:
		return {"ok": false, "reason": "medkit empty", "use_time": 0.0}
	var treats: Array = def.get("treats", [])
	match kind:
		"bandage", "hemostat", "tourniquet", "splint":
			if kind == "tourniquet" and not LIMBS.has(part):
				return {"ok": false, "reason": "tourniquets only go on limbs", "use_time": 0.0}
			var found := false
			for t in treats:
				if has_effect(t, part):
					found = true
			if not found:
				return {"ok": false, "reason": "nothing to treat there", "use_time": 0.0}
		"medkit":
			if is_blacked(part):
				return {"ok": false, "reason": "part is destroyed; needs surgery", "use_time": 0.0}
			var bleeding := false
			for t in treats:
				if has_effect(t, part):
					bleeding = true
			if float(hp[part]) >= float(max_hp[part]) and not bleeding:
				return {"ok": false, "reason": "already at full health", "use_time": 0.0}
		"surgical":
			if not is_blacked(part):
				return {"ok": false, "reason": "surgery is for destroyed parts", "use_time": 0.0}
			if part == "head" or part == "thorax":
				return {"ok": false, "reason": "cannot operate there", "use_time": 0.0}
		"painkiller":
			if has_effect("painkillers"):
				return {"ok": false, "reason": "already medicated", "use_time": 0.0}
	return {"ok": true, "reason": "", "use_time": use_time}


## Apply a med after its use time elapsed. Returns a dictionary describing
## what happened; the caller decrements uses/hp_pool from it.
func apply_med(def: Dictionary, part: String, uses_left: int, hp_pool: float) -> Dictionary:
	var plan := med_plan(def, part, uses_left, hp_pool)
	if not plan["ok"]:
		return plan
	var kind := str(def.get("med", ""))
	var result := {"ok": true, "uses_consumed": 1, "pool_consumed": 0.0, "healed": 0.0, "removed": []}
	var treats: Array = def.get("treats", [])
	match kind:
		"bandage", "hemostat", "tourniquet", "splint":
			for t in treats:
				if remove_effect(t, part) > 0:
					result["removed"].append(t)
			if kind == "tourniquet":
				add_effect("pain", part)
		"medkit":
			var pool := hp_pool
			for t in treats:
				if pool >= 10.0 and remove_effect(t, part) > 0:
					result["removed"].append(t)
					pool -= 10.0
			var missing := float(max_hp[part]) - float(hp[part])
			var heal := minf(minf(missing, float(def.get("heal_per_use", 30.0))), pool)
			hp[part] = float(hp[part]) + heal
			pool -= heal
			part_changed.emit(part, hp[part], max_hp[part])
			result["healed"] = heal
			result["pool_consumed"] = hp_pool - pool
			result["uses_consumed"] = 0
		"surgical":
			max_hp[part] = maxf(1.0, float(max_hp[part]) * (1.0 - float(def.get("max_hp_penalty", 0.2))))
			hp[part] = minf(float(max_hp[part]), float(def.get("restore_hp", 1.0)))
			remove_effect("heavy_bleed", part)
			remove_effect("light_bleed", part)
			remove_effect("fracture", part)
			part_changed.emit(part, hp[part], max_hp[part])
			result["healed"] = hp[part]
		"painkiller":
			add_effect("painkillers", "thorax", float(def.get("duration", 180.0)))
	return result


func to_dict() -> Dictionary:
	return {"hp": hp.duplicate(), "max_hp": max_hp.duplicate(), "effects": effects.duplicate(true), "alive": alive}
