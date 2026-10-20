class_name Population
extends Node
## Server-side people and monsters. Villagers spawn from the structures the
## generator placed (deterministic), shelter at home during hazard warnings,
## and die to the same rules as the player. Enemies spawn by their planet's
## rules (data/enemies.json + the planet's `enemies` list), hunt players and
## despawn when their condition ends. Everything registers with PropSpawner
## so the existing creature replication carries it to clients.

var run: Node
var world: WorldData
var props: PropSpawner
var generator: ChunkGenerator
var planet: Dictionary
var clock: GameClock
var material: Material
var npc_defs: Dictionary = {}
var enemy_defs: Dictionary = {}
var villagers: Dictionary = {}        # npc_id -> Villager
var villager_state: Dictionary = {}   # npc_id -> {"dead": bool}   (persisted)
var enemies: Array = []               # Array[Enemy]
var _spawned_structures: Dictionary = {}  # key -> Array[npc_id]
var _villager_accum: float = 0.0
var _enemy_accum: float = 0.0
var radius_chunks: int = 4
var rng := RandomNumberGenerator.new()
var hazard_phase: int = 0
var sheltering: bool = false

signal enemy_attack(target_pos: Vector3, amount: float, enemy: Enemy)
signal villager_spawned(v: Villager)


func setup(run_node: Node, mat: Material) -> void:
	run = run_node
	world = run.world
	props = run.props
	generator = run.generator
	planet = run.planet
	clock = run.clock
	material = mat
	rng.seed = int(run.world_seed) + 77
	npc_defs = Data.load_json("res://data/npcs/villagers.json").get("kinds", {})
	enemy_defs = Data.load_json("res://data/enemies.json").get("kinds", {})
	fill_registry(props)
	EventBus.hazard_phase_changed.connect(_on_hazard_phase)


## Teach a PropSpawner how to build villager and enemy bodies. Clients call
## this too (they have no Population) so replicated creatures get the right rig.
static func fill_registry(spawner: PropSpawner) -> void:
	var npcs: Dictionary = Data.load_json("res://data/npcs/villagers.json").get("kinds", {})
	var foes: Dictionary = Data.load_json("res://data/enemies.json").get("kinds", {})
	for k in npcs:
		spawner.kind_registry[k] = {"generator": "humanoid", "params": {"cloth": ["#5a4a3a", "#3a5a6a", "#6a3a3a", "#3a6a44"][absi(str(k).hash()) % 4]}}
	for k in foes:
		spawner.kind_registry[k] = {"generator": str(foes[k].get("generator", "grazer")), "params": foes[k].get("params", {})}


func _on_hazard_phase(_id: String, phase: int, _intensity: float) -> void:
	hazard_phase = phase
	var shelter := phase == HazardModule.Phase.WARNING or phase == HazardModule.Phase.ACTIVE
	if shelter != sheltering:
		sheltering = shelter
		for v in villagers.values():
			if is_instance_valid(v):
				(v as Villager).set_sheltering(shelter)


func _process(delta: float) -> void:
	if run.player == null:
		return
	_villager_accum += delta
	if _villager_accum >= 1.0:
		_villager_accum = 0.0
		_spawn_villagers_near(run.player.global_position)
	_enemy_accum += delta
	if _enemy_accum >= 3.0:
		_enemy_accum = 0.0
		_enemy_rules()


# ---------------- villagers ----------------

func _spawn_villagers_near(pos: Vector3) -> void:
	var cc := Vector2i(WorldData.floor_div(int(floor(pos.x)), Chunk.SIZE), WorldData.floor_div(int(floor(pos.z)), Chunk.SIZE))
	var seen: Dictionary = {}
	for dz in range(-radius_chunks, radius_chunks + 1):
		for dx in range(-radius_chunks, radius_chunks + 1):
			for st in generator.structures_near_chunk(cc.x + dx, cc.y + dz):
				var key := str(st.get("key", ""))
				if key == "" or seen.has(key):
					continue
				seen[key] = true
				var pts: Array = st.get("npcs", [])
				if pts.is_empty() or _spawned_structures.has(key):
					continue
				# Only when the structure's ground is loaded.
				var rect: Rect2i = st["rect"]
				if not world.is_loaded(Vector3i(WorldData.floor_div(rect.position.x, Chunk.SIZE), 0, WorldData.floor_div(rect.position.y, Chunk.SIZE))):
					continue
				_spawn_structure_villagers(key, str(st.get("npc_kind", "")), pts)
	# Unload villagers of structures that went out of range.
	for key in _spawned_structures.keys():
		if seen.has(key):
			continue
		for npc_id in _spawned_structures[key]:
			var v: Villager = villagers.get(npc_id)
			if v != null and is_instance_valid(v):
				props.unregister_creature(v)
				v.queue_free()
			villagers.erase(npc_id)
		_spawned_structures.erase(key)


func _spawn_structure_villagers(key: String, npc_kind: String, pts: Array) -> void:
	var def: Dictionary = npc_defs.get(npc_kind, {})
	if def.is_empty():
		return
	var ids: Array = []
	var names: Array = def.get("names", ["Settler"])
	for i in pts.size():
		var npc_id := "%s#%d" % [key, i]
		ids.append(npc_id)
		var st: Dictionary = villager_state.get(npc_id, {})
		if bool(st.get("dead", false)):
			continue
		var p: Dictionary = pts[i]
		var home: Vector3i = p["home"]
		var reg: Dictionary = props.kind_registry[npc_kind]
		var seed := hash([npc_id])
		var rig_seed := 500 + (seed % 1000)
		var rig := VoxelArt.rig(str(reg["generator"]), reg["params"], rig_seed, str(planet.get("palette", "04")))
		var v := Villager.new()
		v.name = "villager_%d" % (seed % 100000)
		props.creatures_root.add_child(v)
		v.setup(rig, material, seed, npc_kind)
		v.setup_villager(npc_id, str(names[(seed % names.size() + names.size()) % names.size()]), npc_kind, Vector3(home) + Vector3(0.5, 0.0, 0.5))
		# Spawn at home, one block up so they fall onto the floor.
		v.global_position = Vector3(p["pos"]) + Vector3(0.5, 0.6, 0.5)
		v.set_sheltering(sheltering)
		props.register_creature(v, npc_kind, rig_seed)
		v.died.connect(func(c: Creature, _cause: String) -> void:
			villager_state[(c as Villager).npc_id] = {"dead": true})
		villagers[npc_id] = v
		villager_spawned.emit(v)
	_spawned_structures[key] = ids


func villager_from_collider(col: Object) -> Villager:
	return col as Villager if col is Villager else null


# ---------------- enemies ----------------

func _condition_met(when: String) -> bool:
	match when:
		"always": return true
		"night": return clock.is_night()
		"hazard_warning": return hazard_phase == HazardModule.Phase.WARNING
		"hazard_active": return hazard_phase == HazardModule.Phase.ACTIVE
		"hazard_recovery": return hazard_phase == HazardModule.Phase.RECOVERY
		"hazard_idle": return hazard_phase == HazardModule.Phase.IDLE
	return false


func _enemy_rules() -> void:
	var players: Array = run._all_player_positions()
	if players.is_empty():
		return
	for e in planet.get("enemies", []):
		var kind := str(e.get("kind", ""))
		var def: Dictionary = enemy_defs.get(kind, {})
		if def.is_empty():
			continue
		var spawn: Dictionary = e.get("spawn", {})
		var alive := 0
		for en in enemies:
			if is_instance_valid(en) and not (en as Enemy).dead and (en as Enemy).kind == kind:
				alive += 1
		var despawn := str(def.get("despawn_when", ""))
		if despawn != "" and _condition_met(despawn):
			for en in enemies.duplicate():
				if is_instance_valid(en) and (en as Enemy).kind == kind:
					_remove_enemy(en)
			continue
		if alive >= int(e.get("max", 2)) or not _condition_met(str(spawn.get("when", "always"))):
			continue
		var pos := _pick_spawn_spot(spawn, players)
		if pos == Vector3.INF:
			continue
		_spawn_enemy(kind, def, pos)
	# Cull the dead after a while and anything far from every player.
	for en in enemies.duplicate():
		if not is_instance_valid(en):
			enemies.erase(en)
			continue
		var far := true
		for p in players:
			if (p as Vector3).distance_to((en as Enemy).global_position) < 90.0:
				far = false
		if far:
			_remove_enemy(en)


func _pick_spawn_spot(spawn: Dictionary, players: Array) -> Vector3:
	var near := str(spawn.get("near", "player"))
	var r: Array = spawn.get("radius", [16, 32])
	var center: Vector3 = players[rng.randi_range(0, players.size() - 1)]
	for attempt in 12:
		var a := rng.randf() * TAU
		var d := rng.randf_range(float(r[0]), float(r[1]))
		var x := int(floor(center.x + cos(a) * d))
		var z := int(floor(center.z + sin(a) * d))
		var y := world.surface_y(x, z)
		if y < 0:
			continue
		var cell := Vector3i(x, y + 1, z)
		if world.is_solid(cell) or Data.block(world.get_block(Vector3i(x, y, z))).fluid:
			continue
		if near == "gas":
			if run.gas_hazard == null or run.gas_hazard.sim.concentration_at(cell) < 0.15:
				continue
		return Vector3(cell) + Vector3(0.5, 0.2, 0.5)
	return Vector3.INF


func _spawn_enemy(kind: String, def: Dictionary, pos: Vector3) -> void:
	var reg: Dictionary = props.kind_registry[kind]
	var seed := rng.randi()
	var rig_seed := 700 + (seed % 1000)
	var rig := VoxelArt.rig(str(reg["generator"]), reg["params"], rig_seed, str(planet.get("palette", "04")))
	var en := Enemy.new()
	en.name = "%s_%d" % [kind, seed % 100000]
	props.creatures_root.add_child(en)
	en.setup(rig, material, seed, kind)
	en.setup_enemy(def)
	en.global_position = pos
	en.attacked.connect(func(target_pos: Vector3, amount: float) -> void: enemy_attack.emit(target_pos, amount, en))
	props.register_creature(en, kind, rig_seed)
	enemies.append(en)


func _remove_enemy(en: Enemy) -> void:
	enemies.erase(en)
	if is_instance_valid(en):
		props.unregister_creature(en)
		en.queue_free()


## Feed perception to every live enemy (called by the run each physics tick).
func perceive(targets: Array, gas_at: Callable, light_at: Callable, wet_at: Callable) -> void:
	for en in enemies:
		if not is_instance_valid(en) or (en as Enemy).dead:
			continue
		var e := en as Enemy
		e.perceive(targets, float(gas_at.call(e.global_position)), float(light_at.call(e.global_position)), bool(wet_at.call(e.global_position)))
		if e.env_wet and e.has_target:
			var d := e.target_pos - e.global_position
			d.y = 0.0
			e.env_dry_dir = d.normalized() if d.length() > 0.01 else Vector3.ZERO


func to_dict() -> Dictionary:
	return {"villagers": villager_state.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	villager_state = (d.get("villagers", {}) as Dictionary).duplicate(true)
