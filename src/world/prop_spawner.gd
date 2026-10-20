class_name PropSpawner
extends Node3D
## Places procedural props (trees, lanterns) and creatures per chunk column
## from the planet's "props" list, deterministically from the world seed.
## Columns populate when they come within range of the focus and are freed
## when they leave it. Props share cached rig meshes.

var world: WorldData
var generator: ChunkGenerator
var planet: Dictionary
var world_seed: int = 1
var palette_id: String = "04"
var radius_chunks: int = 4
var variants: int = 5
var max_creatures: int = 20
var material: Material
var emissive_material: Material
var creatures_root: Node3D
var creatures: Array[Creature] = []
var _columns: Dictionary = {}     # Vector2i -> Array[Node]
var _focus_col := Vector2i(1 << 20, 0)
var _frame: int = 0
var _light_budget: int = 6
var _lights: Array[OmniLight3D] = []
## No props within this distance of the spawn point (the player must not
## wake up inside a tree).
var keep_clear: Vector3 = Vector3(INF, INF, INF)
var keep_clear_radius: float = 5.0
## Harvest bookkeeping (deterministic world => keyed by cell).
var removed: Dictionary = {}        # Vector2i cell -> true (trees cut down)
var regrow_at: Dictionary = {}      # Vector2i cell -> game day_time when a bush regrows
var clock: GameClock = null

signal creature_spawned(creature: Creature)
## Clients get creatures from the server instead of spawning their own.
var spawn_creatures: bool = true
var next_creature_id: int = 1
var creatures_by_id: Dictionary = {}


func setup(world_data: WorldData, gen: ChunkGenerator, planet_cfg: Dictionary, seed: int, mat: Material, emissive: Material) -> void:
	world = world_data
	generator = gen
	planet = planet_cfg
	world_seed = seed
	palette_id = str(planet.get("palette", "04"))
	material = mat
	emissive_material = emissive
	creatures_root = Node3D.new()
	creatures_root.name = "Creatures"
	add_child(creatures_root)
	_prebuild_variants()


func _prebuild_variants() -> void:
	var t0 := Time.get_ticks_msec()
	for p in planet.get("props", []):
		var gen_name := str(p.get("generator", ""))
		for v in variants:
			VoxelArt.rig(gen_name, p.get("params", {}), world_seed * 1000 + gen_name.hash() % 1000 + v, palette_id)
	print("[props] prebuilt %d rig variants in %d ms" % [VoxelArt.stats_built, Time.get_ticks_msec() - t0])


func set_focus(pos: Vector3) -> void:
	_frame += 1
	var col := Vector2i(WorldData.floor_div(int(floor(pos.x)), Chunk.SIZE), WorldData.floor_div(int(floor(pos.z)), Chunk.SIZE))
	if col == _focus_col and _frame % 20 != 0:
		return
	_focus_col = col
	# Populate columns in range whose terrain is loaded.
	for dz in range(-radius_chunks, radius_chunks + 1):
		for dx in range(-radius_chunks, radius_chunks + 1):
			var c := col + Vector2i(dx, dz)
			if _columns.has(c):
				continue
			if not _column_loaded(c):
				continue
			_populate(c)
	# Free columns out of range.
	for c in _columns.keys():
		if absi(c.x - col.x) > radius_chunks + 2 or absi(c.y - col.y) > radius_chunks + 2:
			for n in _columns[c]:
				if is_instance_valid(n):
					if n is Creature:
						creatures.erase(n)
						creatures_by_id.erase((n as Creature).net_id)
					n.queue_free()
			_columns.erase(c)


func _column_loaded(c: Vector2i) -> bool:
	# The surface chunk of the column's centre must be loaded.
	var h := generator.height_at(c.x * Chunk.SIZE + 8, c.y * Chunk.SIZE + 8)
	return world.is_loaded(Vector3i(c.x, WorldData.floor_div(h, Chunk.SIZE), c.y))


func _populate(c: Vector2i) -> void:
	var nodes: Array = []
	_columns[c] = nodes
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, c.x, c.y])
	var ox := c.x * Chunk.SIZE
	var oz := c.y * Chunk.SIZE
	for p in planet.get("props", []):
		var gen_name := str(p.get("generator", ""))
		var density := float(p.get("per_chunk", 0.5))
		var count := int(floor(density))
		if rng.randf() < density - floor(density):
			count += 1
		var allowed: Array = p.get("on", [])
		var is_creature := bool(p.get("creature", false))
		for i in count:
			var x := ox + rng.randi_range(0, Chunk.SIZE - 1)
			var z := oz + rng.randi_range(0, Chunk.SIZE - 1)
			if generator.is_lake_column(x, z):
				continue
			if Vector2(x + 0.5 - keep_clear.x, z + 0.5 - keep_clear.z).length() < keep_clear_radius:
				continue
			if removed.has(Vector2i(x, z)):
				continue
			var y := world.surface_y(x, z)
			if y < 0:
				continue
			var surf := Data.block(world.get_block(Vector3i(x, y, z))).name
			if not allowed.is_empty() and not allowed.has(surf):
				continue
			if world.is_solid(Vector3i(x, y + 1, z)):
				continue
			var vseed := world_seed * 1000 + gen_name.hash() % 1000 + rng.randi_range(0, variants - 1)
			var rig := VoxelArt.rig(gen_name, p.get("params", {}), vseed, palette_id)
			if rig == null:
				continue
			var pos := Vector3(x + 0.5, y + 1.0, z + 0.5)
			if is_creature:
				if not spawn_creatures or creatures.size() >= max_creatures:
					continue
				var cr := Creature.new()
				cr.name = "%s_%d_%d" % [gen_name, x, z]
				creatures_root.add_child(cr)
				cr.set_meta("variant_seed", vseed)
				cr.setup(rig, material, rng.randi(), gen_name)
				cr.net_id = next_creature_id
				next_creature_id += 1
				creatures_by_id[cr.net_id] = cr
				cr.drops = p.get("drops", [])
				cr.global_position = pos + Vector3(0, 0.2, 0)
				cr.rotation.y = rng.randf() * TAU
				creatures.append(cr)
				nodes.append(cr)
				creature_spawned.emit(cr)
			else:
				var n := rig.instantiate(material, emissive_material)
				n.name = "%s_%d_%d" % [gen_name, x, z]
				n.position = pos
				n.rotation.y = rng.randf() * TAU
				n.set_meta("prop", p)
				n.set_meta("cell", Vector2i(x, z))
				n.set_meta("generator", gen_name)
				add_child(n)
				_apply_regrow_state(n)
				if rig.collision_box.size.length_squared() > 0.0 or p.has("harvest"):
					var body := StaticBody3D.new()
					body.collision_layer = 1 if rig.collision_box.size.length_squared() > 0.0 else 8
					body.set_meta("prop_node", n.get_path())
					var cs := CollisionShape3D.new()
					var box := BoxShape3D.new()
					var cb := rig.collision_box if rig.collision_box.size.length_squared() > 0.0 else AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, maxf(rig.height, 0.6), 1.2))
					box.size = cb.size
					cs.shape = box
					cs.position = cb.position + cb.size * 0.5
					body.add_child(cs)
					n.add_child(body)
				if gen_name == "lantern" and _lights.size() < _light_budget:
					var light := OmniLight3D.new()
					light.light_color = Color(1.0, 0.8, 0.45)
					light.light_energy = 1.6
					light.omni_range = 7.0
					light.position = Vector3(0.4, rig.height - 0.5, 0)
					light.shadow_enabled = false
					n.add_child(light)
					_lights.append(light)
				nodes.append(n)


func prop_count() -> int:
	var n := 0
	for arr in _columns.values():
		n += arr.size()
	return n


## The prop node a physics body belongs to (bodies carry "prop_node" meta).
func prop_from_collider(collider: Object) -> Node3D:
	if collider == null or not collider.has_meta("prop_node"):
		return null
	return get_node_or_null(collider.get_meta("prop_node")) as Node3D


func harvest_config(prop: Node3D) -> Dictionary:
	if prop == null or not prop.has_meta("prop"):
		return {}
	var cfg: Dictionary = (prop.get_meta("prop") as Dictionary).get("harvest", {})
	if cfg.is_empty():
		return {}
	var cell: Vector2i = prop.get_meta("cell")
	if regrow_at.has(cell) and clock != null and clock.day_time() < float(regrow_at[cell]):
		return {}  # still regrowing
	return cfg


## Apply a harvest: trees are removed for good, bushes shrink until regrown.
func harvest(prop: Node3D) -> void:
	var cfg := harvest_config(prop)
	if cfg.is_empty():
		return
	var cell: Vector2i = prop.get_meta("cell")
	if bool(cfg.get("remove", false)):
		removed[cell] = true
		for arr in _columns.values():
			arr.erase(prop)
		prop.queue_free()
	else:
		var hours := float(cfg.get("regrow_hours", 24.0))
		if clock != null:
			regrow_at[cell] = clock.day_time() + hours / 24.0
		_apply_regrow_state(prop)


func _apply_regrow_state(prop: Node3D) -> void:
	var cell: Vector2i = prop.get_meta("cell")
	var growing := regrow_at.has(cell) and clock != null and clock.day_time() < float(regrow_at[cell])
	var rig := prop.get_node_or_null("Rig") as Node3D
	if rig != null:
		rig.scale = Vector3(0.45, 0.45, 0.45) if growing else Vector3.ONE


func _process(_delta: float) -> void:
	# Regrow check every couple of seconds.
	if clock == null or regrow_at.is_empty() or Engine.get_process_frames() % 120 != 0:
		return
	for arr in _columns.values():
		for n in arr:
			if n is Node3D and not (n is Creature) and n.has_meta("cell") and regrow_at.has(n.get_meta("cell")):
				_apply_regrow_state(n)


## Client side: create or update a mirrored creature from a server state.
func apply_remote_creature(id: int, kind: String, seed: int, pos: Vector3, yaw: float, is_moving: bool, is_dead: bool) -> void:
	var cr: Creature = creatures_by_id.get(id)
	if cr == null:
		var cfg: Dictionary = {}
		for p in planet.get("props", []):
			if str(p.get("generator", "")) == kind:
				cfg = p
				break
		var rig := VoxelArt.rig(kind, cfg.get("params", {}), seed, palette_id)
		if rig == null:
			return
		cr = Creature.new()
		cr.name = "%s_remote_%d" % [kind, id]
		cr.remote = true
		cr.net_id = id
		creatures_root.add_child(cr)
		cr.setup(rig, material, seed, kind)
		cr.global_position = pos
		cr._remote_target = pos
		creatures.append(cr)
		creatures_by_id[id] = cr
	cr.apply_remote(pos, yaw, is_moving, is_dead)


## Variant seed a creature was built with (for replication).
func creature_seed(cr: Creature) -> int:
	return int(cr.rng.seed) if cr.has_meta("variant_seed") == false else int(cr.get_meta("variant_seed"))


func prop_by_cell(cell: Vector2i) -> Node3D:
	for arr in _columns.values():
		for n in arr:
			if n is Node3D and not (n is Creature) and n.has_meta("cell") and n.get_meta("cell") == cell:
				return n
	return null


## Client side: mirror a harvest decided by the server.
func apply_remote_harvest(cell: Vector2i, regrow: float, was_removed: bool) -> void:
	if was_removed:
		removed[cell] = true
	elif regrow > 0.0:
		regrow_at[cell] = regrow
	var n := prop_by_cell(cell)
	if n == null:
		return
	if was_removed:
		for arr in _columns.values():
			arr.erase(n)
		n.queue_free()
	else:
		_apply_regrow_state(n)


func harvested_state() -> Array:
	var out: Array = []
	for c in removed.keys():
		out.append([c.x, c.y, 0.0, true])
	for c in regrow_at.keys():
		out.append([c.x, c.y, float(regrow_at[c]), false])
	return out
