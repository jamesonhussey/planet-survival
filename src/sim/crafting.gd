class_name Crafting
extends RefCounted
## Recipe resolution against an Equipment and the stations nearby. Pure.
## Recipe (data/recipes.json):
##   {"id": "planks", "name": "...", "in": [{"id": "log", "count": 1}],
##    "out": [{"id": "planks", "count": 4}], "station": "" | "campfire",
##    "time": 2.0, "desc": "..."}


static func can_craft(recipe: Dictionary, equipment: Equipment, stations: Array) -> Dictionary:
	var station := str(recipe.get("station", ""))
	if station != "" and not stations.has(station):
		return {"ok": false, "reason": "needs a %s nearby" % station}
	for inp in recipe.get("in", []):
		var need := int(inp.get("count", 1))
		var have := equipment.count_of(str(inp.get("id", "")))
		if have < need:
			return {"ok": false, "reason": "need %d %s (have %d)" % [need, str(inp.get("id", "")), have]}
	return {"ok": true, "reason": "", "time": float(recipe.get("time", 2.0))}


## Consume inputs and produce outputs. Outputs that do not fit are returned
## in "overflow" for the caller to drop into the world.
static func craft(recipe: Dictionary, equipment: Equipment, data: Node) -> Dictionary:
	for inp in recipe.get("in", []):
		equipment.consume(str(inp.get("id", "")), int(inp.get("count", 1)))
	var overflow: Array = []
	var made: Array = []
	for outp in recipe.get("out", []):
		var item: ItemInstance = data.make_item(str(outp.get("id", "")), int(outp.get("count", 1)))
		if item == null:
			continue
		item.examined = true
		made.append(item)
		if not equipment.add_item(item):
			overflow.append(item)
	return {"ok": true, "made": made, "overflow": overflow}


## Recipes sorted: craftable first, then by name.
static func sorted_recipes(recipes: Array, equipment: Equipment, stations: Array) -> Array:
	var list := recipes.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: bool = can_craft(a, equipment, stations)["ok"]
		var cb: bool = can_craft(b, equipment, stations)["ok"]
		if ca != cb:
			return ca
		return str(a.get("name", a.get("id", ""))) < str(b.get("name", b.get("id", ""))))
	return list
