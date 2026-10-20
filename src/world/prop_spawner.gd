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
				if creatures.size() >= max_creatures:
					continue
				var cr := Creature.new()
				cr.name = "%s_%d_%d" % [gen_name, x, z]
				creatures_root.add_child(cr)
				cr.setup(rig, material, rng.randi(), gen_name)
				cr.global_position = pos + Vector3(0, 0.2, 0)
				cr.rotation.y = rng.randf() * TAU
				creatures.append(cr)
				nodes.append(cr)
			else:
				var n := rig.instantiate(material, emissive_material)
				n.name = "%s_%d_%d" % [gen_name, x, z]
				n.position = pos
				n.rotation.y = rng.randf() * TAU
				add_child(n)
				if rig.collision_box.size.length_squared() > 0.0:
					var body := StaticBody3D.new()
					body.collision_layer = 1
					var cs := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = rig.collision_box.size
					cs.shape = box
					cs.position = rig.collision_box.position + rig.collision_box.size * 0.5
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
