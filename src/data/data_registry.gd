extends Node
## Autoload "Data". Loads and validates every JSON data file once at boot.
## Everything tunable lives in data/, so this is the only place that knows
## file names. Validation errors are pushed with file + key so they show up
## in headless runs (the smoke test fails on them).

const MATERIALS_PATH := "res://data/materials.json"
const PALETTES_PATH := "res://data/palettes.json"
const RENDER_PATH := "res://data/render_settings.json"
const MODES_PATH := "res://data/modes.json"
const PLANETS_DIR := "res://data/planets"
const ITEMS_PATH := "res://data/items.json"

var materials: Array[MaterialProps] = []
var material_ids: Dictionary = {}  # name -> id
var palettes: Dictionary = {}  # palette id -> Dictionary
var render: Dictionary = {}
var modes: Dictionary = {}  # mode id -> Dictionary
var planets: Dictionary = {}  # planet id -> Dictionary
var items: Dictionary = {}  # item id -> Dictionary
var block_items: Dictionary = {}  # material name -> item id that places it
var loaded: bool = false
var errors: PackedStringArray = []


func load_all() -> void:
	errors.clear()
	_load_materials()
	_load_palettes()
	render = load_json(RENDER_PATH)
	_load_modes()
	_load_planets()
	_load_items()
	loaded = true
	for e in errors:
		push_error(e)
	if errors.is_empty():
		print("[data] loaded %d materials, %d palettes, %d modes, %d planets, %d items" % [materials.size(), palettes.size(), modes.size(), planets.size(), items.size()])


func item_def(id: String) -> Dictionary:
	return items.get(id, {})


## New ItemInstance from an item id (null if unknown).
func make_item(id: String, count: int = 1) -> ItemInstance:
	var d := item_def(id)
	if d.is_empty():
		push_error("[data] unknown item '%s'" % id)
		return null
	return ItemInstance.new(d, count)


## The item that drops when a block is dug (by material name), or "".
func drop_item_for(material_name: String) -> String:
	var id := block_id(material_name)
	var drop := block(id).drop
	if drop != "" and items.has(drop):
		return drop
	return ""


func _load_items() -> void:
	items.clear()
	block_items.clear()
	var doc := load_json(ITEMS_PATH)
	for entry in doc.get("items", []):
		if not (entry is Dictionary) or not entry.has("id"):
			errors.append("%s: item without id" % ITEMS_PATH)
			continue
		var id := str(entry["id"])
		if items.has(id):
			errors.append("%s: duplicate item id %s" % [ITEMS_PATH, id])
		var size: Array = entry.get("size", [1, 1])
		if size.size() != 2 or int(size[0]) < 1 or int(size[1]) < 1:
			errors.append("%s: item %s has invalid size" % [ITEMS_PATH, id])
		if entry.has("block") and not material_ids.has(str(entry["block"])):
			errors.append("%s: item %s places unknown material %s" % [ITEMS_PATH, id, entry["block"]])
		if entry.has("block"):
			block_items[str(entry["block"])] = id
		if entry.has("med") and not entry.has("use_time"):
			errors.append("%s: medical item %s needs use_time" % [ITEMS_PATH, id])
		for g in entry.get("grids", []):
			if not (g is Array) or g.size() != 2:
				errors.append("%s: item %s has invalid grid" % [ITEMS_PATH, id])
		items[id] = entry
	# Every material drop must exist as an item (or be empty).
	for m in materials:
		if m.drop != "" and not items.has(m.drop):
			errors.append("%s: material %s drops unknown item '%s'" % [MATERIALS_PATH, m.name, m.drop])


func reload_render_settings() -> Dictionary:
	render = load_json(RENDER_PATH)
	EventBus.render_settings_reloaded.emit(render)
	return render


## Returns the props for a block id; unknown ids map to air (id 0).
func block(id: int) -> MaterialProps:
	if id < 0 or id >= materials.size():
		return materials[0]
	return materials[id]


func block_id(name: String) -> int:
	return int(material_ids.get(name, 0))


func planet(id: String) -> Dictionary:
	return planets.get(id, {})


func palette(id: String) -> Dictionary:
	return palettes.get(id, {})


func palette_color(palette_id: String, key: String, fallback: Color = Color.MAGENTA) -> Color:
	var p: Dictionary = palette(palette_id)
	if p.has(key) and p[key] is String:
		return Color.html(p[key])
	return fallback


func palette_ramp(palette_id: String, ramp: String) -> Array[Color]:
	var out: Array[Color] = []
	var p: Dictionary = palette(palette_id)
	var ramps: Dictionary = p.get("ramps", {})
	for hex in ramps.get(ramp, ["#ff00ff", "#ff00ff", "#ff00ff", "#ff00ff"]):
		out.append(Color.html(hex))
	return out


func mode(id: String) -> Dictionary:
	return modes.get(id, modes.get("standard", {"id": "standard", "name": "Standard", "days": 100}))


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[data] missing file %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[data] %s:%d parse error: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("[data] %s: top level must be an object" % path)
		return {}
	return json.data


func _load_materials() -> void:
	materials.clear()
	material_ids.clear()
	var doc := load_json(MATERIALS_PATH)
	var list: Array = doc.get("materials", [])
	if list.is_empty():
		errors.append("%s: no materials" % MATERIALS_PATH)
		return
	var by_id: Dictionary = {}
	var max_id := 0
	for entry in list:
		if not (entry is Dictionary):
			errors.append("%s: material entry is not an object" % MATERIALS_PATH)
			continue
		var m := MaterialProps.from_dict(entry)
		if by_id.has(m.id):
			errors.append("%s: duplicate material id %d (%s)" % [MATERIALS_PATH, m.id, m.name])
		if material_ids.has(m.name):
			errors.append("%s: duplicate material name %s" % [MATERIALS_PATH, m.name])
		for key in ["waterproof", "airtight", "opacity", "heat_resistance", "flammability", "strength", "buoyancy", "weight"]:
			if not entry.has(key):
				errors.append("%s: material %s missing property '%s'" % [MATERIALS_PATH, m.name, key])
		by_id[m.id] = m
		material_ids[m.name] = m.id
		max_id = maxi(max_id, m.id)
	if not by_id.has(0) or by_id[0].name != "air":
		errors.append("%s: id 0 must be 'air'" % MATERIALS_PATH)
	if max_id > 255:
		errors.append("%s: material ids must fit in a byte (max 255)" % MATERIALS_PATH)
	materials.resize(max_id + 1)
	for i in max_id + 1:
		materials[i] = by_id.get(i, by_id.get(0, MaterialProps.new()))


func _load_palettes() -> void:
	palettes = load_json(PALETTES_PATH).get("palettes", {})
	if palettes.is_empty():
		errors.append("%s: no palettes" % PALETTES_PATH)


func _load_modes() -> void:
	modes.clear()
	for m in load_json(MODES_PATH).get("modes", []):
		if m is Dictionary and m.has("id") and m.has("days"):
			modes[str(m["id"])] = m
		else:
			errors.append("%s: mode needs id and days" % MODES_PATH)


func _load_planets() -> void:
	planets.clear()
	var dir := DirAccess.open(PLANETS_DIR)
	if dir == null:
		errors.append("missing directory %s" % PLANETS_DIR)
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := PLANETS_DIR.path_join(f)
		var p := load_json(path)
		if p.is_empty():
			continue
		_validate_planet(path, p)
		planets[str(p.get("id", f))] = p


func _validate_planet(path: String, p: Dictionary) -> void:
	for key in ["id", "name", "palette", "world_size", "world_height", "mood", "terrain", "hazards", "clock", "vitals"]:
		if not p.has(key):
			errors.append("%s: missing '%s'" % [path, key])
	if p.has("palette") and not palettes.has(str(p["palette"])):
		errors.append("%s: unknown palette '%s'" % [path, p["palette"]])
	var terrain: Dictionary = p.get("terrain", {})
	for key in ["surface", "subsurface", "deep", "shore", "lake_fluid"]:
		if terrain.has(key) and not material_ids.has(str(terrain[key])):
			errors.append("%s: terrain.%s refers to unknown material '%s'" % [path, key, terrain[key]])
	for h in p.get("hazards", []):
		if not (h is Dictionary):
			errors.append("%s: hazard entry is not an object" % path)
			continue
		for key in ["id", "module", "warning_time", "active_time", "interval_days", "intensity"]:
			if not h.has(key):
				errors.append("%s: hazard %s missing '%s'" % [path, h.get("id", "?"), key])
		if float(h.get("warning_time", 0)) <= 0.0:
			errors.append("%s: hazard %s must telegraph (warning_time > 0)" % [path, h.get("id", "?")])
