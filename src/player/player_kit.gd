class_name PlayerKit
extends RefCounted
## Everything a player *has*: equipment (inventory), body health, survival
## vitals, plus the timed actions on them (using a med, examining, eating,
## crafting, harvesting). Pure logic owned by the server-side player state;
## the UI only reads it and submits intents.

var equipment := Equipment.new()
var body := BodyHealth.new()
var vitals := Vitals.new()
var rng := RandomNumberGenerator.new()

## Current timed action:
## {"kind": "med"|"examine"|"eat"|"craft"|"harvest", "item", "part", "recipe", "target", "time_left", "total"}
var action: Dictionary = {}
var breather: ItemInstance = null
var breather_active: bool = false
var filter_seconds: float = 0.0
var data: Node = null   # DataRegistry (for item creation)

signal action_started(kind: String, total: float)
signal action_finished(kind: String, result: Dictionary)
signal action_cancelled(kind: String, reason: String)
signal message(text: String)


func _init(seed: int = 1, data_registry: Node = null) -> void:
	rng.seed = seed
	data = data_registry
	# Method callable (not a lambda): a lambda capturing self would form a
	# RefCounted cycle with vitals and leak.
	vitals.damage_sink = _body_damage


func _body_damage(amount: float, cause: String) -> void:
	body.damage_all(amount, cause)


## Starting loadout for a run (from the planet JSON "starting_kit").
func give_starting_kit(kit: Array, data_registry: Node) -> void:
	data = data_registry
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


func _begin(a: Dictionary) -> void:
	action = a
	action_started.emit(str(a["kind"]), float(a["total"]))


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
	_begin({"kind": "med", "item": item, "part": part, "time_left": float(plan["use_time"]), "total": float(plan["use_time"])})
	return plan


func start_examine(item: ItemInstance) -> bool:
	if busy() or item == null or item.examined:
		return false
	_begin({"kind": "examine", "item": item, "time_left": item.examine_time(), "total": item.examine_time()})
	return true


## Eat or drink a food item (canteens have uses).
func start_eat(item: ItemInstance) -> Dictionary:
	if busy():
		return {"ok": false, "reason": "busy"}
	if item == null or item.category() != "food":
		return {"ok": false, "reason": "not food"}
	if item.def.has("uses") and item.uses_left <= 0:
		message.emit("%s is empty." % item.display_name())
		return {"ok": false, "reason": "empty"}
	var food: Dictionary = item.def.get("food", {})
	var gives_food := float(food.get("hunger", 0.0)) > 0.0
	var gives_drink := float(food.get("thirst", 0.0)) > 0.0
	if gives_food and not gives_drink and vitals.hunger > 0.97:
		message.emit("Not hungry.")
		return {"ok": false, "reason": "not hungry"}
	if gives_drink and not gives_food and vitals.thirst > 0.97:
		message.emit("Not thirsty.")
		return {"ok": false, "reason": "not thirsty"}
	var t := float(item.def.get("use_time", 2.0))
	_begin({"kind": "eat", "item": item, "time_left": t, "total": t})
	return {"ok": true, "use_time": t}


func start_craft(recipe: Dictionary, stations: Array) -> Dictionary:
	if busy():
		return {"ok": false, "reason": "busy"}
	var plan := Crafting.can_craft(recipe, equipment, stations)
	if not plan["ok"]:
		message.emit(str(plan["reason"]))
		return plan
	_begin({"kind": "craft", "recipe": recipe, "time_left": float(plan["time"]), "total": float(plan["time"])})
	return plan


## Harvest a prop (tree, bush): `target` is an opaque reference the caller
## resolves when the action finishes; `cfg` is the prop's harvest config.
func start_harvest(target: Variant, cfg: Dictionary, label: String) -> bool:
	if busy():
		return false
	var t := float(cfg.get("time", 2.0))
	_begin({"kind": "harvest", "target": target, "cfg": cfg, "label": label, "time_left": t, "total": t})
	return true


func cancel_action(reason: String = "cancelled") -> void:
	if action.is_empty():
		return
	var kind: String = action["kind"]
	action = {}
	action_cancelled.emit(kind, reason)


## Advance timed actions, body effects and food spoilage.
## `dt` real seconds (time-scaled), `dt_game` game seconds.
func tick(dt: float, dt_game: float = 0.0) -> void:
	body.tick(dt)
	if dt_game > 0.0 and data != null:
		_spoil(dt_game)
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
		"eat":
			var item: ItemInstance = a["item"]
			var food: Dictionary = item.def.get("food", {})
			vitals.consume(food)
			var poisoned := false
			if rng.randf() < float(food.get("poison_chance", 0.0)):
				body.add_effect("poison", "stomach")
				poisoned = true
			if item.def.has("uses"):
				item.uses_left -= 1
			else:
				item.count -= 1
				if item.count <= 0:
					equipment.remove_item(item)
			item.examined = true
			equipment.changed.emit()
			action_finished.emit("eat", {"ok": true, "item": item, "poisoned": poisoned})
		"craft":
			var recipe: Dictionary = a["recipe"]
			var res := Crafting.craft(recipe, equipment, data)
			res["recipe"] = recipe
			action_finished.emit("craft", res)
		"harvest":
			action_finished.emit("harvest", {"ok": true, "target": a["target"], "cfg": a["cfg"], "label": a["label"]})


## Food loses freshness in game time; at zero it turns into spoiled food.
func _spoil(dt_game: float) -> void:
	var changed := false
	for it: ItemInstance in equipment.all_items():
		var hours := float(it.def.get("spoil_hours", 0.0))
		if hours <= 0.0:
			continue
		if it.freshness_hours < 0.0:
			it.freshness_hours = hours
		it.freshness_hours -= dt_game / 3600.0
		if it.freshness_hours <= 0.0:
			var spoiled: ItemInstance = data.make_item("spoiled_food", it.count)
			var grid := it.parent_grid
			var pos := grid.position_of(it) if grid != null else Vector2i(-1, -1)
			var name := it.display_name()
			equipment.remove_item(it)
			if spoiled != null:
				spoiled.examined = true
				if grid == null or not grid.place(spoiled, pos.x, pos.y, false):
					equipment.add_item(spoiled)
			message.emit("Your %s has spoiled." % name)
			changed = true
	if changed:
		equipment.changed.emit()


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


## Refill every refillable container (canteens) to full. Returns how many.
func refill_water() -> int:
	var n := 0
	for it: ItemInstance in equipment.all_items():
		if bool(it.def.get("refillable", false)) and it.def.has("uses") and it.uses_left < int(it.def["uses"]):
			it.uses_left = int(it.def["uses"])
			n += 1
	if n > 0:
		equipment.changed.emit()
	return n


func penalties() -> Dictionary:
	var p := body.penalties()
	# Weight: the comfortable limit is 30 kg, scaled down by arm injuries
	# (`carry`). Every kg over it costs 1.5% speed, down to 60% speed.
	var w := equipment.total_weight()
	var limit := 30.0 * maxf(float(p["carry"]), 0.1)
	var over := maxf(0.0, w - limit)
	var weight_mult := clampf(1.0 - over * 0.015, 0.6, 1.0)
	p["move_speed"] = float(p["move_speed"]) * weight_mult * vitals.speed_factor()
	p["weight"] = w
	p["weight_limit"] = limit
	p["overweight"] = w > limit
	return p


# ---- persistence ----

func to_dict() -> Dictionary:
	var pockets: Array = []
	for g in equipment.pockets:
		pockets.append(g.to_dict())
	return {
		"equipment": {
			"pockets": pockets,
			"rig": equipment.rig.to_dict() if equipment.rig != null else {},
			"backpack": equipment.backpack.to_dict() if equipment.backpack != null else {},
			"quick": equipment.quick.duplicate(),
		},
		"body": body.to_dict(),
		"vitals": vitals.to_dict(),
		"breather_active": breather_active,
		"filter_seconds": filter_seconds,
	}


## Rebuild from to_dict() output. Items are recreated from their defs.
func from_dict(d: Dictionary, data_registry: Node) -> void:
	data = data_registry
	var eq: Dictionary = d.get("equipment", {})
	var uid_map: Dictionary = {}   # old uid -> new item
	var pockets: Array = eq.get("pockets", [])
	for i in mini(pockets.size(), equipment.pockets.size()):
		_grid_from_dict(equipment.pockets[i], pockets[i], uid_map)
	if not (eq.get("rig", {}) as Dictionary).is_empty():
		var rig := _item_from_dict(eq["rig"], uid_map)
		if rig != null:
			equipment.equip(rig)
	if not (eq.get("backpack", {}) as Dictionary).is_empty():
		var bp := _item_from_dict(eq["backpack"], uid_map)
		if bp != null:
			equipment.equip(bp)
	var quick: Array = eq.get("quick", [])
	for i in mini(quick.size(), Equipment.QUICK_SLOTS):
		var old_uid := int(quick[i])
		equipment.quick[i] = uid_map[old_uid].uid if uid_map.has(old_uid) else 0
	var b: Dictionary = d.get("body", {})
	var hp_d: Dictionary = b.get("hp", {})
	var max_d: Dictionary = b.get("max_hp", {})
	for part in BodyHealth.PARTS:
		if hp_d.has(part):
			body.hp[part] = float(hp_d[part])
		if max_d.has(part):
			body.max_hp[part] = float(max_d[part])
	body.effects = (b.get("effects", []) as Array).duplicate(true)
	body.alive = bool(b.get("alive", true))
	vitals.from_dict(d.get("vitals", {}))
	breather_active = bool(d.get("breather_active", false))
	filter_seconds = float(d.get("filter_seconds", 0.0))
	if breather_active:
		breather = equipment.find_first(func(it: ItemInstance) -> bool: return it.id == "breather")
		if breather == null:
			breather_active = false
	equipment.changed.emit()


func _item_from_dict(d: Dictionary, uid_map: Dictionary) -> ItemInstance:
	var it: ItemInstance = data.make_item(str(d.get("id", "")), int(d.get("count", 1)))
	if it == null:
		return null
	it.rotated = bool(d.get("rotated", false))
	it.examined = bool(d.get("examined", it.examined))
	it.uses_left = int(d.get("uses_left", it.uses_left))
	it.hp_pool = float(d.get("hp_pool", it.hp_pool))
	it.durability = float(d.get("durability", 1.0))
	it.freshness_hours = float(d.get("freshness_hours", -1.0))
	it.data = (d.get("data", {}) as Dictionary).duplicate()
	var grids: Array = d.get("grids", [])
	for i in mini(grids.size(), it.grids.size()):
		_grid_from_dict(it.grids[i], grids[i], uid_map)
	if d.has("uid"):
		uid_map[int(d["uid"])] = it
	return it


func _grid_from_dict(g: InventoryGrid, d: Dictionary, uid_map: Dictionary) -> void:
	for entry in d.get("items", []):
		var it := _item_from_dict(entry, uid_map)
		if it == null:
			continue
		if not g.place(it, int(entry.get("x", 0)), int(entry.get("y", 0)), it.rotated):
			g.auto_place(it)
