class_name PlayerKit
extends RefCounted
## Everything a player *has*: equipment (inventory) and body health, plus the
## timed actions on them (using a med, examining an item). Pure logic owned
## by the server-side player state; the UI only reads it and submits intents.

var equipment := Equipment.new()
var body := BodyHealth.new()
var rng := RandomNumberGenerator.new()

## Current timed action: {"kind": "med"|"examine", "item": ItemInstance, "part": String, "time_left": float, "total": float}
var action: Dictionary = {}
## Breather state
var breather: ItemInstance = null
var breather_active: bool = false
var filter_seconds: float = 0.0

signal action_started(kind: String, total: float)
signal action_finished(kind: String, result: Dictionary)
signal action_cancelled(kind: String, reason: String)
signal message(text: String)


func _init(seed: int = 1) -> void:
	rng.seed = seed


## Starting loadout for a run (from the planet JSON "starting_kit" or defaults).
func give_starting_kit(kit: Array, data: Node) -> void:
	for entry in kit:
		var id := str(entry.get("id", ""))
		var count := int(entry.get("count", 1))
		var item: ItemInstance = data.make_item(id, count)
		if item == null:
			continue
		if bool(entry.get("examined", false)):
			item.examined = true
		if item.def.has("slot") and bool(entry.get("equip", true)):
			if equipment.equip(item):
				continue
		if not equipment.add_item(item):
			push_warning("[kit] no room for starting item %s" % id)
	equipment.auto_assign_quick()


func busy() -> bool:
	return not action.is_empty()


func action_progress() -> float:
	if action.is_empty():
		return 0.0
	return 1.0 - float(action["time_left"]) / maxf(float(action["total"]), 0.01)


## Begin using a medical item on a body part.
func start_med(item: ItemInstance, part: String) -> Dictionary:
	if busy():
		return {"ok": false, "reason": "busy"}
	if item == null or item.category() != "medical":
		return {"ok": false, "reason": "not a medical item"}
	var plan := body.med_plan(item.def, part, item.uses_left, item.hp_pool)
	if not plan["ok"]:
		message.emit(str(plan["reason"]))
		return plan
	action = {"kind": "med", "item": item, "part": part, "time_left": float(plan["use_time"]), "total": float(plan["use_time"])}
	action_started.emit("med", float(plan["use_time"]))
	return plan


func start_examine(item: ItemInstance) -> bool:
	if busy() or item == null or item.examined:
		return false
	action = {"kind": "examine", "item": item, "part": "", "time_left": item.examine_time(), "total": item.examine_time()}
	action_started.emit("examine", item.examine_time())
	return true


func cancel_action(reason: String = "cancelled") -> void:
	if action.is_empty():
		return
	var kind: String = action["kind"]
	action = {}
	action_cancelled.emit(kind, reason)


## Advance timed actions and body effects.
func tick(dt: float) -> void:
	body.tick(dt)
	if filter_seconds > 0.0 and breather_active:
		pass  # drained in breathe()
	if action.is_empty():
		return
	action["time_left"] = float(action["time_left"]) - dt
	if float(action["time_left"]) > 0.0:
		return
	var a := action
	action = {}
	match str(a["kind"]):
		"med":
			var item: ItemInstance = a["item"]
			var res := body.apply_med(item.def, a["part"], item.uses_left, item.hp_pool)
			if res["ok"]:
				item.uses_left -= int(res.get("uses_consumed", 0))
				item.hp_pool -= float(res.get("pool_consumed", 0.0))
				item.examined = true
				var used_up := (item.def.has("uses") and item.uses_left <= 0) or (str(item.def.get("med", "")) == "medkit" and item.hp_pool <= 0.01)
				if used_up:
					equipment.remove_item(item)
				equipment.changed.emit()
			action_finished.emit("med", res)
		"examine":
			var item: ItemInstance = a["item"]
			item.examined = true
			equipment.changed.emit()
			action_finished.emit("examine", {"ok": true, "item": item})


## Filtered concentration the player actually breathes, draining the filter.
func filtered_gas(gas: float, dt: float) -> float:
	if not breather_active or breather == null:
		return gas
	if filter_seconds <= 0.0:
		breather_active = false
		message.emit("Breather filter spent.")
		return gas
	if gas > 0.01:
		filter_seconds -= dt
	return gas * (1.0 - float(breather.def.get("filter_efficiency", 0.85)))


func toggle_breather() -> bool:
	if breather == null:
		var found := equipment.find_first(func(it: ItemInstance) -> bool: return it.id == "breather")
		if found == null:
			message.emit("No breather mask.")
			return false
		breather = found
		filter_seconds = float(found.def.get("filter_seconds", 90.0))
		found.examined = true
	breather_active = not breather_active
	if breather_active and filter_seconds <= 0.0:
		var f := equipment.find_first(func(it: ItemInstance) -> bool: return it.id == "filter")
		if f == null:
			message.emit("Filter spent. No spare filter.")
			breather_active = false
			return false
		filter_seconds = float(f.def.get("filter_seconds", 90.0))
		equipment.consume("filter", 1)
		message.emit("New filter fitted.")
	message.emit("Breather %s." % ("on" if breather_active else "off"))
	return breather_active


func penalties() -> Dictionary:
	var p := body.penalties()
	# Weight: the comfortable limit is 30 kg, scaled down by arm injuries
	# (`carry`). Every kg over it costs 1.5% speed, down to 60% speed.
	var w := equipment.total_weight()
	var limit := 30.0 * maxf(float(p["carry"]), 0.1)
	var over := maxf(0.0, w - limit)
	var weight_mult := clampf(1.0 - over * 0.015, 0.6, 1.0)
	p["move_speed"] = float(p["move_speed"]) * weight_mult
	p["weight"] = w
	p["weight_limit"] = limit
	p["overweight"] = w > limit
	return p
