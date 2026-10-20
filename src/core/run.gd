extends Node
## One survival run. Built entirely from code by Game.start_run(). Owns the
## PS1 pipeline (low-res viewport), the world, the authority (Session +
## WorldCommands), the streamer, the player and their kit (inventory +
## body health), the clock, hazards, vitals, telegraph/sound, pickups and
## the UI screens.

var planet_id: String = "04"
var mode_id: String = "standard"
var world_seed: int = 1337
var save_data: Dictionary = {}
var pause_menu: PauseMenu
var autosave_interval: float = 180.0
var _autosave_accum: float = 0.0
# --- co-op ---
var replicator: Replicator
var remote_players: Dictionary = {}     # peer -> RemotePlayer
var pickups_by_id: Dictionary = {}      # id -> ItemPickup
var next_pickup_id: int = 1
var rituals: Array = []                 # Array[Ritual] (server)
var revives: Dictionary = {}            # peer -> count (server)
var ghost: bool = false
var _net_accum: float = 0.0
var _clock_accum: float = 0.0
var _gas_accum: float = 0.0
var _creature_accum: float = 0.0
var _ritual_accum: float = 0.0

var planet: Dictionary = {}
var mode: Dictionary = {}
var pipeline: PS1Pipeline
var view: SubViewport
var world: WorldData
var generator: ChunkGenerator
var atlas: BlockTextureGen
var mesher: ChunkMesher
var streamer: ChunkStreamer
var session: Session
var commands: WorldCommands
var player: PlayerController
var kit: PlayerKit
var clock: GameClock
var hazards: HazardDirector
var gas_hazard: HeavyGasHazard
var eclipse_hazard: EclipseHazard
var flood_hazard: FloodHazard
var gas_renderer: GasRenderer
var water_renderer: WaterRenderer
var swarm_renderer: SwarmRenderer
var eclipse_visuals: EclipseVisuals
var static_sun: bool = false
var _burning: bool = false
var _bitten_timer: float = 0.0
var _params_accum: float = 0.0
var _swarm_accum: float = 0.0
var _fire_accum: float = 0.0
var telegraph: Telegraph
var props: PropSpawner
var sounds: SoundBank
var vitals: Vitals
var hud: HUD
var inventory_ui: InventoryUI
var health_ui: HealthScreen
var pickups_root: Node3D
var pickups: Array[ItemPickup] = []
var pickup_material: Material
var crafting_ui: CraftingUI
var recipes: Array = []
var campfire_lights: Dictionary = {}   # Vector3i -> OmniLight3D
var base_sky_top: Color
var base_sky_horizon: Color
var base_fog: Color
var base_ambient_energy: float = 0.55
var base_sun_energy: float = 1.0
var night_darkness: float = 0.85
var _connected_creatures: Dictionary = {}
var world_root: Node3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var spawn_point: Vector3
var ended: bool = false
var verbose: bool = false
var _frame: int = 0
var _vitals_accum: float = 0.0
var _nearest_pickup: ItemPickup = null


func _ready() -> void:
	planet = Data.planet(planet_id)
	mode = Data.mode(mode_id)
	if planet.is_empty():
		push_error("[run] unknown planet '%s'" % planet_id)
		return
	print("[run] planet %s (%s), mode %s (%d days), seed %d" % [planet_id, planet.get("name", "?"), mode_id, int(mode.get("days", 100)), world_seed])
	var t0 := Time.get_ticks_msec()
	_build_pipeline()
	_build_world()
	var t1 := Time.get_ticks_msec()
	_build_environment()
	_build_authority()
	_build_player()
	_build_clock()
	_build_hazards()
	_build_presentation()
	if not save_data.is_empty():
		_apply_save(save_data)
	streamer.verbose = Game.smoke_frames_left >= 0
	verbose = streamer.verbose
	print("[run] ready in %d ms (world %d ms): %d chunks loaded, %d meshed, spawn %s" % [Time.get_ticks_msec() - t0, t1 - t0, streamer.loaded_count(), streamer.meshed_count(), str(spawn_point)])
	# --trigger [--timescale=N]: fire the first hazard immediately (smoke/screenshot runs).
	if Game.args.has("trigger"):
		clock.time_scale = float(Game.args.get("timescale", "8"))
		hazards.debug_trigger_any()
	# --eye=dx,dy,dz (offset from spawn) --yaw=rad --pitch=rad: debug camera in fly mode.
	if Game.args.has("eye"):
		var parts := str(Game.args["eye"]).split(",")
		if parts.size() == 3:
			player.fly = true
			player.global_position = spawn_point + Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			player.set_look(float(Game.args.get("yaw", "0")), float(Game.args.get("pitch", "-0.15")))
	# --ui=inventory|health: open a screen at boot (screenshots).
	match str(Game.args.get("ui", "")):
		"inventory": _open_screen(inventory_ui)
		"health": _open_screen(health_ui)
	# --campfire: place a lit campfire two blocks from spawn (screenshots/tests).
	if Game.args.has("campfire"):
		var cx := int(floor(spawn_point.x)) + 2
		var cz := int(floor(spawn_point.z)) + 2
		var cy := world.surface_y(cx, cz) + 1
		if world.set_block(Vector3i(cx, cy, cz), Data.block_id("campfire")):
			_after_edit(Vector3i(cx, cy, cz))
	if Game.args.has("hour"):
		clock.day_fraction = clampf(float(Game.args["hour"]) / 24.0, 0.0, 0.999)
	if str(Game.args.get("ui", "")) == "crafting":
		_open_screen(crafting_ui)
	# --hurt: pre-damage the body so the health screen has something to show.
	if Game.args.has("hurt"):
		kit.body.damage("left_leg", 30.0, "blunt", kit.rng)
		kit.body.damage("right_arm", 18.0, "cut", kit.rng)
		kit.body.add_effect("light_bleed", "right_arm")
		kit.body.add_effect("fracture", "left_leg")
		kit.vitals.hunger = 0.3
		kit.vitals.thirst = 0.5
		kit.vitals.temperature = 34.0


func _build_pipeline() -> void:
	pipeline = PS1Pipeline.new()
	pipeline.name = "PS1"
	add_child(pipeline)
	view = pipeline.build(Data.render)


func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	view.add_child(world_root)
	world = WorldData.new(int(planet.get("world_size", 1024)), int(planet.get("world_height", 128)), Data.materials)
	generator = ChunkGenerator.new(world_seed, planet.get("terrain", {}), Data.material_ids, world.world_height, planet.get("structures", []))
	world.generator = generator
	if not save_data.is_empty():
		world.saved_chunks = SaveSystem.read_chunks()
		print("[save] %d edited chunks queued" % world.saved_chunks.size())
	atlas = BlockTextureGen.new().build(Data.materials, world_seed)
	mesher = ChunkMesher.new(Data.materials, atlas)
	streamer = ChunkStreamer.new()
	streamer.name = "Streamer"
	streamer.setup(world, mesher,
		MaterialFactory.terrain_opaque(atlas.texture, Data.render),
		MaterialFactory.terrain_transparent(atlas.texture, Data.render))
	world_root.add_child(streamer)
	spawn_point = _find_spawn()
	streamer.preload_around(spawn_point, 1)


## Spawn on high ground near a lake so the first eruption is readable.
func _find_spawn() -> Vector3:
	var cfg: Dictionary = planet.get("spawn", {})
	var min_above := int(cfg.get("min_height_above_lake", 6))
	var radius := int(cfg.get("search_radius", 96))
	match str(cfg.get("mode", "high_ground_near_lake")):
		"flat":
			for r in range(0, radius, 4):
				for z in range(-r, r + 1, 4):
					for x in range(-r, r + 1, 4):
						if generator.is_structure_column(x, z) or generator.is_lake_column(x, z):
							continue
						var h := generator.height_at(x, z)
						if absi(generator.height_at(x + 2, z) - h) <= 1 and absi(generator.height_at(x, z + 2) - h) <= 1:
							return Vector3(x + 0.5, h + 1.1, z + 0.5)
			return Vector3(0.5, generator.height_at(0, 0) + 1.1, 0.5)
		"beach":
			var coast := int(planet.get("terrain", {}).get("coast_z", 0))
			for z in range(coast + 14, coast + radius, 3):
				for x in range(-8, 9, 4):
					if not generator.is_lake_column(x, z) and generator.height_at(x, z) >= generator.lake_level + min_above:
						return Vector3(x + 0.5, generator.height_at(x, z) + 1.1, z + 0.5)
			return Vector3(0.5, generator.height_at(0, coast + 20) + 1.1, coast + 20.5)
	var best := Vector2i.ZERO
	var best_score := -INF
	var lake_level := generator.lake_level
	for z in range(-radius, radius + 1, 6):
		for x in range(-radius, radius + 1, 6):
			if generator.is_lake_column(x, z):
				continue
			var h := generator.height_at(x, z)
			if h < lake_level + min_above:
				continue
			var near_lake := false
			for d in [Vector2i(24, 0), Vector2i(-24, 0), Vector2i(0, 24), Vector2i(0, -24), Vector2i(40, 0), Vector2i(-40, 0), Vector2i(0, 40), Vector2i(0, -40)]:
				if generator.is_lake_column(x + d.x, z + d.y):
					near_lake = true
					break
			var score := (10.0 if near_lake else 0.0) - Vector2(x, z).length() * 0.02 - absf(float(h - lake_level - min_above - 4)) * 0.3
			if score > best_score:
				best_score = score
				best = Vector2i(x, z)
	var y := generator.height_at(best.x, best.y) + 1
	return Vector3(best.x + 0.5, y + 0.1, best.y + 0.5)


func _build_environment() -> void:
	var mood: Dictionary = planet.get("mood", {})
	env = WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color.html(str(mood.get("sky_top", "#7fae7a")))
	sky_mat.sky_horizon_color = Color.html(str(mood.get("sky_horizon", "#d8e3b4")))
	sky_mat.ground_bottom_color = Color.html(str(mood.get("fog_color", "#b9cfa6"))).darkened(0.3)
	sky_mat.ground_horizon_color = Color.html(str(mood.get("fog_color", "#b9cfa6")))
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.2
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.html(str(mood.get("ambient_color", "#4f6a4c")))
	e.ambient_light_energy = float(mood.get("ambient_energy", 0.55))
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color.html(str(mood.get("fog_color", "#b9cfa6")))
	e.fog_depth_begin = float(mood.get("fog_start", Data.render.get("fog_start", 10.0)))
	e.fog_depth_end = float(mood.get("fog_end", Data.render.get("fog_end", 64.0)))
	e.fog_depth_curve = 1.0
	e.fog_density = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	view.add_child(env)
	base_sky_top = sky_mat.sky_top_color
	base_sky_horizon = sky_mat.sky_horizon_color
	base_fog = e.fog_light_color
	base_ambient_energy = e.ambient_light_energy
	base_sun_energy = float(mood.get("sun_energy", 1.0))
	night_darkness = float(mood.get("night_darkness", 0.85))
	static_sun = bool(mood.get("static_sun", false))

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color.html(str(mood.get("sun_color", "#f2f0d8")))
	sun.light_energy = float(mood.get("sun_energy", 1.0))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.rotation_degrees = Vector3(-float(mood.get("sun_elevation_degrees", 48)), 35.0, 0.0)
	view.add_child(sun)


func _build_authority() -> void:
	session = Session.new()
	session.name = "Session"
	commands = WorldCommands.new()
	commands.name = "Commands"
	commands.setup(world)
	commands.kit_lookup = func(_peer: int) -> PlayerKit: return kit
	add_child(session)
	add_child(commands)
	session.setup(commands)
	replicator = Replicator.new()
	replicator.name = "Replicator"
	add_child(replicator)
	replicator.setup(self, world)
	session.replicator = replicator
	commands.kit_lookup = func(peer: int) -> PlayerKit: return kit if peer == session.local_peer_id else null
	commands.block_dug.connect(func(peer: int, pos: Vector3i, id: int) -> void:
		_after_edit(pos)
		if sounds != null: sounds.play("dig")
		if session.is_online():
			replicator.broadcast_block(pos, 0, peer)
			if peer != session.local_peer_id:
				var drop := Data.block(id).drop
				if drop != "":
					replicator.grant(peer, drop, 1, Vector3(pos)))
	commands.block_placed.connect(func(peer: int, pos: Vector3i, id: int) -> void:
		_after_edit(pos)
		if sounds != null: sounds.play("place")
		if session.is_online():
			replicator.broadcast_block(pos, id, peer))
	_wire_replication()
	commands.command_rejected.connect(func(_peer: int, _cmd: Dictionary, reason: String) -> void:
		if reason != "nothing to dig" and reason != "occupied":
			EventBus.toast.emit(reason, 1.0))
	commands.item_overflow.connect(func(_peer: int, pos: Vector3i, item: ItemInstance) -> void:
		spawn_pickup(item, Vector3(pos) + Vector3(0.5, 0.2, 0.5))
		EventBus.toast.emit("Inventory full: %s dropped" % item.display_name(), 1.5))
	world.block_changed.connect(_on_block_changed_lights)


func _wire_replication() -> void:
	# Server side: commands and requests from clients.
	replicator.client_command.connect(func(cmd: Dictionary) -> void: commands.handle(cmd))
	replicator.client_take_pickup.connect(_on_client_take_pickup)
	replicator.client_drop.connect(func(_peer: int, item: Dictionary, pos: Vector3) -> void:
		var it := kit._item_from_dict(item, {})
		if it != null:
			spawn_pickup(it, pos))
	replicator.client_harvest.connect(_on_client_harvest)
	replicator.client_attack.connect(func(peer: int, creature_id: int) -> void:
		var cr: Creature = props.creatures_by_id.get(creature_id)
		var st: Dictionary = replicator.peer_states.get(peer, {})
		if cr != null and not cr.dead:
			cr.hit(12.0, st.get("pos", cr.global_position + Vector3(1, 0, 0)), "blunt"))
	replicator.client_died.connect(_on_client_died)
	replicator.client_place_tag.connect(_on_client_place_tag)
	# Client side: state from the server.
	replicator.remote_block_set.connect(func(pos: Vector3i, id: int, actor: int) -> void:
		var old := world.get_block(pos)
		if world.set_block(pos, id):
			_after_edit(pos)
			if sounds != null and pos.distance_to(Vector3i(player.global_position.floor())) < 24:
				sounds.play("dig" if id == 0 else "place")
		if actor == session.local_peer_id and id != 0 and not session.is_server():
			var item_id := str(Data.block_items.get(Data.block(id).name, ""))
			if item_id != "":
				kit.equipment.consume(item_id, 1)
		if old == id:
			pass)
	replicator.remote_grant.connect(func(item_id: String, count: int, pos: Vector3) -> void:
		var it := Data.make_item(item_id, count)
		if it == null:
			return
		it.examined = true
		if kit.equipment.add_item(it):
			EventBus.toast.emit("+%d %s" % [count, it.display_name()], 1.2)
		else:
			replicator.send_drop(it.to_dict(), pos + Vector3(0.5, 0.5, 0.5))
			EventBus.toast.emit("No room for %s" % it.display_name(), 1.2))
	replicator.remote_peer_state.connect(_on_remote_peer_state)
	replicator.remote_peer_left.connect(func(peer: int) -> void:
		var rp: RemotePlayer = remote_players.get(peer)
		if rp != null:
			rp.queue_free()
			remote_players.erase(peer)
		EventBus.toast.emit("A survivor left.", 2.0))
	replicator.remote_pickup_spawn.connect(func(id: int, item: Dictionary, pos: Vector3) -> void:
		if pickups_by_id.has(id):
			return
		var it := kit._item_from_dict(item, {})
		if it != null:
			_make_pickup(it, pos, id))
	replicator.remote_pickup_remove.connect(func(id: int) -> void:
		var p: ItemPickup = pickups_by_id.get(id)
		if p != null:
			pickups.erase(p)
			pickups_by_id.erase(id)
			p.queue_free())
	replicator.remote_prop_harvested.connect(func(cell: Vector2i, regrow_at: float, removed: bool) -> void:
		props.apply_remote_harvest(cell, regrow_at, removed))
	replicator.remote_revive.connect(_revive_at)
	replicator.remote_damage.connect(func(amount: float, kind: String) -> void:
		var limb: String = BodyHealth.LIMBS[kit.rng.randi_range(0, 3)]
		kit.body.damage(limb, amount, kind, kit.rng)
		if kind == "bite":
			_bitten_timer = 1.5
			player.add_shake(0.06, 0.2))
	replicator.remote_ritual.connect(func(state: Dictionary) -> void:
		if bool(state.get("complete", false)):
			EventBus.toast.emit("The vigil is complete. %s returns." % str(state.get("owner_name", "Someone")), 4.0)
		elif bool(state.get("failed", false)):
			EventBus.toast.emit("The vigil failed: %s." % str(state.get("reason", "")), 4.0)
		elif int(state.get("owner", 0)) == session.local_peer_id and ghost:
			hud.set_status("GHOST  vigil %d%%%s" % [int(float(state.get("progress", 0.0)) * 100.0), "" if bool(state.get("fire", false)) else "  (no fire!)"]))
	if session.is_online() and session.is_server():
		Net.peer_run_ready.connect(_on_peer_run_ready)
		Net.peer_left.connect(func(id: int) -> void:
			replicator.broadcast_peer_left(id)
			var rp: RemotePlayer = remote_players.get(id)
			if rp != null:
				rp.queue_free()
				remote_players.erase(id)
			EventBus.toast.emit("%s left." % str(Net.peer_names.get(id, "A survivor")), 2.0))


func _on_peer_run_ready(peer: int) -> void:
	var edited: Dictionary = {}
	for c in world.edited_chunks():
		edited[c.cpos] = c.blocks
	var hz: Array = []
	if gas_hazard != null:
		hz = [gas_hazard.id, gas_hazard.phase, gas_hazard.intensity]
	var pk: Array = []
	for id in pickups_by_id:
		var p: ItemPickup = pickups_by_id[id]
		if is_instance_valid(p):
			pk.append([id, p.item.to_dict(), p.global_position])
	var rs: Array = []
	for r in rituals:
		rs.append(_ritual_state(r))
	replicator.send_initial_state(peer, edited, hz, pk, props.harvested_state(), rs)
	EventBus.toast.emit("%s joined." % str(Net.peer_names.get(peer, "A survivor")), 3.0)


func _on_remote_peer_state(peer: int, pname: String, pos: Vector3, yaw: float, pitch: float, moving: bool, is_ghost: bool) -> void:
	if peer == session.local_peer_id:
		return
	var rp: RemotePlayer = remote_players.get(peer)
	if rp == null:
		rp = RemotePlayer.new()
		rp.name = "peer_%d" % peer
		view.add_child(rp)
		rp.setup(peer, pname, pickup_material, peer)
		rp.global_position = pos
		remote_players[peer] = rp
	rp.apply_state(pos, yaw, pitch, moving, is_ghost)


func _on_client_take_pickup(peer: int, id: int) -> void:
	var p: ItemPickup = pickups_by_id.get(id)
	if p == null or not is_instance_valid(p):
		return
	var st: Dictionary = replicator.peer_states.get(peer, {})
	var ppos: Vector3 = st.get("pos", p.global_position)
	if ppos.distance_to(p.global_position) > 4.0:
		return
	var item := p.item
	_remove_pickup(p)
	replicator.grant(peer, item.id, item.count, p.global_position)


func _on_client_harvest(peer: int, cell: Vector2i) -> void:
	var prop := props.prop_by_cell(cell)
	if prop == null:
		return
	var cfg := props.harvest_config(prop)
	if cfg.is_empty():
		return
	var at := prop.global_position
	props.harvest(prop)
	replicator.broadcast_prop_harvested(cell, float(props.regrow_at.get(cell, 0.0)), props.removed.has(cell))
	for entry in [cfg, cfg.get("extra", {})]:
		if (entry as Dictionary).is_empty():
			continue
		var cr: Array = entry.get("count", [1, 1])
		var n := kit.rng.randi_range(int(cr[0]), int(cr[1]))
		if n > 0:
			replicator.grant(peer, str(entry.get("id", "")), n, at)


func _on_client_died(peer: int, pos: Vector3, items: Array) -> void:
	for d in items:
		var it := kit._item_from_dict(d, {})
		if it != null:
			spawn_pickup(it, pos + Vector3(kit.rng.randf_range(-0.6, 0.6), 0.5, kit.rng.randf_range(-0.6, 0.6)))
	replicator.ghosts[peer] = true
	var who := str(Net.peer_names.get(peer, "A survivor"))
	if peer != session.local_peer_id:
		EventBus.toast.emit("%s died. Their tag lies where they fell." % who, 4.0)
	replicator.broadcast_toast("%s died. Their tag lies where they fell." % who, 4.0)


func _on_client_place_tag(_peer: int, cairn_pos: Vector3i, owner: int, owner_name: String) -> void:
	if Data.block(world.get_block(cairn_pos)).name != "cairn":
		return
	for r in rituals:
		if (r as Ritual).cairn_pos == cairn_pos:
			return
	var r := Ritual.new(cairn_pos, owner, clock.day_time(), int(revives.get(owner, 0)))
	r.set_meta("owner_name", owner_name)
	rituals.append(r)
	var text := "A vigil begins for %s. Keep a fire by the cairn through the night." % owner_name
	EventBus.toast.emit(text, 4.0)
	replicator.broadcast_toast(text, 4.0)


func _ritual_state(r: Ritual) -> Dictionary:
	return {"owner": r.tag_owner, "owner_name": str(r.get_meta("owner_name", "")), "progress": r.progress(), "fire": r.fire_present,
		"complete": r.complete, "failed": r.failed, "reason": r.fail_reason, "pos": r.cairn_pos}


func _tick_rituals(dt_days: float) -> void:
	for r in rituals.duplicate():
		var rr := r as Ritual
		var fire := false
		for p in _blocks_near(Vector3(rr.cairn_pos) + Vector3(0.5, 0.5, 0.5), 3, func(m: MaterialProps) -> bool: return m.heat > 0.0):
			fire = true
			break
		var intact := Data.block(world.get_block(rr.cairn_pos)).name == "cairn"
		rr.tick(dt_days, clock.is_night(), fire, intact)
		var state := _ritual_state(rr)
		replicator.broadcast_ritual(state)
		replicator.remote_ritual.emit(state)
		if rr.complete:
			revives[rr.tag_owner] = int(revives.get(rr.tag_owner, 0)) + 1
			replicator.revive(rr.tag_owner, Vector3(rr.cairn_pos) + Vector3(0.5, 1.2, 0.5))
			rituals.erase(r)
		elif rr.failed:
			rituals.erase(r)


## Dead in co-op: become a ghost instead of ending the run.
func _become_ghost(cause: String) -> void:
	ghost = true
	player.ghost = true
	player.fly = true
	var items: Array = []
	for it in kit.equipment.all_items():
		if it.parent_grid != null and (it.parent_grid.owner_item == null or not kit.equipment.all_items().has(it.parent_grid.owner_item)):
			items.append(it.to_dict())
	for holder in [kit.equipment.rig, kit.equipment.backpack]:
		if holder != null:
			items.append(holder.to_dict())
	var tag := Data.make_item("player_tag")
	if tag != null:
		tag.data = {"owner": session.local_peer_id, "owner_name": Net.my_name}
		items.append(tag.to_dict())
	replicator.send_died(player.global_position, items)
	kit.equipment = Equipment.new()
	kit.equipment.changed.connect(_refresh_quick)
	inventory_ui.kit = kit
	inventory_ui._rebuild()
	_refresh_quick()
	hud.set_status("GHOST  a friend must set your tag on a cairn and keep a fire through a night")
	EventBus.toast.emit("You died (%s). You can watch. Your tag lies where you fell." % cause.replace("_", " "), 6.0)
	if sounds != null:
		sounds.stop_all_loops()
		sounds.play("ui_low")


func _revive_at(pos: Vector3) -> void:
	ghost = false
	player.ghost = false
	player.fly = false
	var rs := Ritual.revive_state()
	kit.body = BodyHealth.new()
	for part in BodyHealth.PARTS:
		kit.body.max_hp[part] = float(BodyHealth.DEFAULT_MAX[part]) * float(rs["max_hp_factor"])
		kit.body.hp[part] = kit.body.max_hp[part] * float(rs["hp_factor"]) / float(rs["max_hp_factor"])
	kit.body.died.connect(func(cause: String) -> void: _finish(false, cause))
	kit.vitals.hunger = float(rs["hunger"])
	kit.vitals.thirst = float(rs["thirst"])
	kit.vitals.oxygen = 1.0
	kit.vitals.alive = true
	player.global_position = pos
	player.velocity = Vector3.ZERO
	hud.set_status("")
	EventBus.toast.emit("You come back. Weak, empty-handed, alive.", 5.0)


func _net_tick(delta: float) -> void:
	if not session.is_online():
		return
	_net_accum += delta
	if _net_accum >= 0.1:
		_net_accum = 0.0
		var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.3
		replicator.send_my_state(Net.my_name, player.global_position, player._yaw, player._pitch, moving, ghost)
	if not session.is_server():
		return
	_clock_accum += delta
	if _clock_accum >= 1.0:
		_clock_accum = 0.0
		replicator.broadcast_clock(clock.day, clock.day_fraction, clock.time_scale)
	_gas_accum += delta
	if _gas_accum >= 0.5 and gas_hazard != null:
		_gas_accum = 0.0
		replicator.broadcast_gas(gas_hazard.sim.cells)
	_creature_accum += delta
	if _creature_accum >= 0.2:
		_creature_accum = 0.0
		var states: Array = []
		for cr in props.creatures:
			if not is_instance_valid(cr):
				continue
			var near := false
			for st in replicator.peer_states.values():
				if (st["pos"] as Vector3).distance_to(cr.global_position) < 80.0:
					near = true
					break
			if near:
				states.append([cr.net_id, cr.kind, props.creature_seed(cr), cr.global_position, cr.rotation.y, cr.moving, cr.dead])
		if not states.is_empty():
			replicator.broadcast_creatures(states)
	_params_accum += delta
	if _params_accum >= 0.5:
		_params_accum = 0.0
		for m in hazards.modules:
			if m.has_method("net_params") and not m.is_idle():
				replicator.broadcast_hazard_params(m.id, m.call("net_params"))
	_swarm_accum += delta
	if _swarm_accum >= 0.2 and flood_hazard != null:
		_swarm_accum = 0.0
		if flood_hazard.swarm.count_alive() > 0:
			replicator.broadcast_swarm(flood_hazard.swarm.positions())
	_ritual_accum += delta
	if _ritual_accum >= 1.0:
		_ritual_accum = 0.0
		if not rituals.is_empty():
			_tick_rituals(1.0 * clock.time_scale / (clock.minutes_per_day * 60.0))


func _after_edit(pos: Vector3i) -> void:
	var cpos := WorldData.chunk_pos_of(pos)
	streamer.remesh_now(cpos)
	var l := WorldData.local_of(pos)
	for d in ChunkMesher.DIRS:
		var touches := (l.x == 0 and d.x < 0) or (l.x == Chunk.SIZE - 1 and d.x > 0) \
			or (l.y == 0 and d.y < 0) or (l.y == Chunk.SIZE - 1 and d.y > 0) \
			or (l.z == 0 and d.z < 0) or (l.z == Chunk.SIZE - 1 and d.z > 0)
		if touches:
			streamer.remesh_now(cpos + d)


## Light sources (campfires) follow block edits.
func _on_block_changed_lights(pos: Vector3i, old_id: int, new_id: int) -> void:
	if Data.block(old_id).light > 0.0 and campfire_lights.has(pos):
		(campfire_lights[pos] as OmniLight3D).queue_free()
		campfire_lights.erase(pos)
	var mp := Data.block(new_id)
	if mp.light > 0.0:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.35)
		light.light_energy = 2.2
		light.omni_range = mp.light
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.position = Vector3(pos) + Vector3(0.5, 0.9, 0.5)
		view.add_child(light)
		campfire_lights[pos] = light


## Blocks with a station/heat near a position (radius in blocks).
func _blocks_near(pos: Vector3, radius: int, pred: Callable) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var c := Vector3i(pos.floor())
	for dy in range(-2, 3):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var p := c + Vector3i(dx, dy, dz)
				if pred.call(Data.block(world.get_block(p))):
					out.append(p)
	return out


func stations_near_player() -> Array:
	var out: Array = []
	for p in _blocks_near(player.global_position, 3, func(m: MaterialProps) -> bool: return m.station != ""):
		var st := Data.block(world.get_block(p)).station
		if not out.has(st):
			out.append(st)
	return out


func heat_near_player() -> float:
	var best := 0.0
	for p in _blocks_near(player.global_position, 4, func(m: MaterialProps) -> bool: return m.heat > 0.0):
		var d := (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(player.global_position)
		best = maxf(best, Data.block(world.get_block(p)).heat * clampf(1.0 - d / 5.0, 0.0, 1.0))
	return best


## Roof overhead within 6 blocks counts as shelter.
func is_sheltered() -> bool:
	var c := Vector3i(player.global_position.floor())
	for dy in range(2, 8):
		if world.is_solid(c + Vector3i(0, dy, 0)):
			return true
	return false


func ambient_temperature() -> float:
	var mood: Dictionary = planet.get("mood", {})
	return lerpf(float(mood.get("temp_night", 8.0)), float(mood.get("temp_day", 22.0)), clock.daylight())


func _update_day_night() -> void:
	var dl := clock.daylight()
	var elev := clock.sun_elevation()
	sun.rotation_degrees = Vector3(-maxf(elev, 2.0), 35.0 + clock.day_fraction * 60.0, 0.0)
	sun.light_energy = base_sun_energy * dl
	sun.shadow_enabled = dl > 0.15
	var e := env.environment
	var dark := 1.0 - night_darkness
	e.ambient_light_energy = lerpf(base_ambient_energy * dark, base_ambient_energy, dl)
	var sky := e.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = base_sky_top.darkened(1.0 - lerpf(dark * 0.4, 1.0, dl))
	sky.sky_horizon_color = base_sky_horizon.darkened(1.0 - lerpf(dark * 0.6, 1.0, dl))
	var fog := base_fog.darkened(1.0 - lerpf(dark * 0.5, 1.0, dl))
	e.fog_light_color = fog
	sky.ground_horizon_color = fog
	sky.ground_bottom_color = fog.darkened(0.3)


func _build_player() -> void:
	kit = PlayerKit.new(world_seed, Data)
	kit.give_starting_kit(planet.get("starting_kit", []), Data)
	kit.message.connect(func(t: String) -> void: EventBus.toast.emit(t, 2.0))
	kit.body.died.connect(func(cause: String) -> void: _finish(false, cause))
	kit.action_finished.connect(_on_action_finished)
	player = PlayerController.new()
	player.name = "Player"
	player.configure(session, world, streamer, kit)
	view.add_child(player)
	player.global_position = spawn_point
	player.set_look(0.0, -0.15)
	player.landed.connect(_on_landed)
	player.use_requested.connect(_on_use_item)
	player.interact_requested.connect(_on_interact)
	player.attack_requested.connect(_on_attack)
	var listener := AudioListener3D.new()
	player.camera.add_child(listener)
	listener.make_current()
	streamer.set_focus([spawn_point])
	vitals = kit.vitals
	vitals.configure(planet.get("vitals", {}))
	pickups_root = Node3D.new()
	pickups_root.name = "Pickups"
	view.add_child(pickups_root)


func _build_clock() -> void:
	clock = GameClock.new()
	clock.name = "Clock"
	clock.setup(planet.get("clock", {}))
	add_child(clock)
	EventBus.day_changed.connect(_on_day_changed)


func _build_hazards() -> void:
	hazards = HazardDirector.new()
	hazards.name = "Hazards"
	add_child(hazards)
	hazards.setup(planet, world, clock, {
		"player_position": func() -> Vector3: return player.global_position,
		"player_positions": _all_player_positions,
	})
	for m in hazards.modules:
		if m is HeavyGasHazard and gas_hazard == null:
			gas_hazard = m
		elif m is EclipseHazard and eclipse_hazard == null:
			eclipse_hazard = m
		elif m is FloodHazard and flood_hazard == null:
			flood_hazard = m
	if session.is_online() and not session.is_server():
		hazards.enabled = false
		for m in hazards.modules:
			m.client_mode = true
	elif session.is_online():
		EventBus.hazard_phase_changed.connect(func(id: String, phase: int, intensity: float) -> void:
			replicator.broadcast_hazard_phase(id, phase, intensity))


func _all_player_positions() -> Array:
	var out: Array = [player.global_position]
	if replicator != null:
		for peer in replicator.peer_states:
			if peer != session.local_peer_id and not bool(replicator.peer_states[peer].get("ghost", false)):
				out.append(replicator.peer_states[peer]["pos"])
	return out


## Planet 01: permanent twilight, brightening when the moon slides.
func _update_eclipse_lighting() -> void:
	var f := eclipse_hazard.light_factor if eclipse_hazard != null else 0.0
	var dir := eclipse_hazard.sun_dir() if eclipse_hazard != null else Vector3(0.3, 1, 0.2).normalized()
	sun.look_at_from_position(dir * 10.0, Vector3.ZERO, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_energy = base_sun_energy + f * 3.2
	sun.light_color = Color.html(str(planet.get("mood", {}).get("sun_color", "#c9b8ff"))).lerp(Color(1.0, 0.97, 0.85), f)
	sun.shadow_enabled = true
	var e := env.environment
	e.ambient_light_energy = base_ambient_energy + f * 0.9
	var sky := e.sky.sky_material as ProceduralSkyMaterial
	var bright := Color(1.0, 0.95, 0.8)
	sky.sky_top_color = base_sky_top.lerp(bright.darkened(0.3), f * 0.8)
	sky.sky_horizon_color = base_sky_horizon.lerp(bright, f * 0.9)
	var fog := base_fog.lerp(bright, f * 0.7)
	e.fog_light_color = fog
	sky.ground_horizon_color = fog
	if eclipse_visuals != null:
		eclipse_visuals.update(dir, f)


func _build_presentation() -> void:
	sounds = SoundBank.new()
	sounds.name = "Sounds"
	add_child(sounds)
	telegraph = Telegraph.new()
	telegraph.name = "Telegraph"
	view.add_child(telegraph)
	telegraph.setup(sounds, player, pipeline)
	telegraph.hazards = hazards
	if eclipse_hazard != null:
		eclipse_visuals = EclipseVisuals.new()
		eclipse_visuals.name = "EclipseSky"
		view.add_child(eclipse_visuals)
		eclipse_visuals.setup(player.camera)
	if flood_hazard != null:
		water_renderer = WaterRenderer.new()
		water_renderer.name = "Water"
		view.add_child(water_renderer)
		water_renderer.setup(flood_hazard.sim, Data.palette_color(str(planet.get("palette", "02")), "haze", Color(0.3, 0.6, 0.75)).lerp(Color(0.2, 0.5, 0.7), 0.5) * Color(1, 1, 1, 0.6))
		swarm_renderer = SwarmRenderer.new()
		swarm_renderer.name = "Swarm"
		view.add_child(swarm_renderer)
		swarm_renderer.setup(MaterialFactory.voxel_model(Data.render, false), str(planet.get("palette", "02")))
	if gas_hazard != null:
		gas_renderer = GasRenderer.new()
		gas_renderer.name = "GasHaze"
		view.add_child(gas_renderer)
		gas_renderer.setup(gas_hazard.sim, Data.palette_color(str(planet.get("palette", "04")), "haze", Color(0.78, 0.86, 0.62)))
	pickup_material = MaterialFactory.voxel_model(Data.render, false)
	props = PropSpawner.new()
	props.name = "Props"
	view.add_child(props)
	props.keep_clear = spawn_point
	props.clock = clock
	props.spawn_creatures = not (session.is_online() and not session.is_server())
	props.creature_spawned.connect(_on_creature_spawned)
	props.setup(world, generator, planet, world_seed, pickup_material, MaterialFactory.voxel_model(Data.render, true))
	props.set_focus(spawn_point)
	for cr in props.creatures:
		_on_creature_spawned(cr)

	hud = HUD.new()
	hud.name = "HUD"
	view.add_child(hud)
	hud.debug_provider = _debug_text
	player.hotbar_changed.connect(func(_i: int) -> void: _refresh_quick())
	kit.equipment.changed.connect(_refresh_quick)
	_refresh_quick()
	player.aim_changed.connect(_update_aim_text)

	inventory_ui = InventoryUI.new()
	inventory_ui.name = "InventoryUI"
	view.add_child(inventory_ui)
	inventory_ui.setup(kit)
	inventory_ui.nearby_provider = nearby_pickups
	inventory_ui.take_pickup = take_pickup
	inventory_ui.drop_item = func(item: ItemInstance) -> void:
		spawn_pickup(item, player.global_position + (-player.global_transform.basis.z) * 1.0 + Vector3(0, 0.5, 0))
	inventory_ui.open_health = func(item: ItemInstance) -> void:
		inventory_ui.close()
		_open_screen(health_ui, item)
	inventory_ui.closed.connect(_on_screen_closed)
	health_ui = HealthScreen.new()
	health_ui.name = "HealthUI"
	view.add_child(health_ui)
	health_ui.setup(kit)
	health_ui.closed.connect(_on_screen_closed)
	recipes = Data.load_json("res://data/recipes.json").get("recipes", [])
	crafting_ui = CraftingUI.new()
	crafting_ui.name = "CraftingUI"
	view.add_child(crafting_ui)
	crafting_ui.setup(kit, recipes)
	crafting_ui.stations_provider = stations_near_player
	crafting_ui.closed.connect(_on_screen_closed)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	view.add_child(pause_menu)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.save_quit_requested.connect(func() -> void:
		save_game()
		Game.return_to_orbit())
	pause_menu.quit_requested.connect(func() -> void:
		if not ended:
			save_game()
		get_tree().quit())

	EventBus.toast.emit("%s  -  %s" % [planet.get("name", ""), planet.get("tagline", "")], 5.0)
	EventBus.toast.emit("LMB dig/hit, RMB place, E take/harvest/drink, Q use, Tab inventory, H health, C craft, F5 eruption", 8.0)


# ---- screens ----

func _open_screen(screen: CanvasLayer, med: ItemInstance = null) -> void:
	if screen == health_ui:
		health_ui.open(med)
	elif screen == crafting_ui:
		crafting_ui.open()
	else:
		(screen as InventoryUI).open()
	player.input_enabled = false
	hud.root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Warp the cursor to the screen centre so it is visible immediately.
	var win := get_viewport().get_visible_rect().size
	Input.warp_mouse(win * 0.5)


func _on_screen_closed() -> void:
	if inventory_ui.is_open or health_ui.is_open or crafting_ui.is_open or pause_menu.is_open or ended:
		return
	hud.root.visible = true
	player.input_enabled = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func any_screen_open() -> bool:
	return inventory_ui.is_open or health_ui.is_open or crafting_ui.is_open or pause_menu.is_open


func _open_pause() -> void:
	_close_all_screens()
	pause_menu.open("%s  |  %s  |  autosaves every %d s" % [str(planet.get("name", "")), clock.clock_text(), int(autosave_interval)])
	player.input_enabled = false
	hud.root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)


func _close_pause() -> void:
	pause_menu.close()
	_on_screen_closed()


# ---- save / load ----

func save_game() -> Error:
	if ended:
		return ERR_UNAVAILABLE
	var pk: Array = []
	for p in pickups:
		if is_instance_valid(p):
			pk.append({"item": p.item.to_dict(), "pos": [p.global_position.x, p.global_position.y, p.global_position.z]})
	var removed: Array = []
	for c in props.removed.keys():
		removed.append([c.x, c.y])
	var regrow: Array = []
	for c in props.regrow_at.keys():
		regrow.append([c.x, c.y, float(props.regrow_at[c])])
	var meta := {
		"planet_id": planet_id, "mode_id": mode_id, "seed": world_seed,
		"clock": {"day": clock.day, "day_fraction": clock.day_fraction},
		"player": {"pos": [player.global_position.x, player.global_position.y, player.global_position.z], "yaw": player._yaw, "pitch": player._pitch, "quick": player.hotbar_index},
		"kit": kit.to_dict(),
		"hazards": hazards.next_event_day.duplicate(),
		"hazard_events": gas_hazard.events_so_far if gas_hazard != null else 0,
		"props": {"removed": removed, "regrow": regrow},
		"pickups": pk,
	}
	if Game.args.has("savetest"):
		var cp := Vector3i(int(floor(spawn_point.x)) + 3, world.surface_y(int(floor(spawn_point.x)) + 3, int(floor(spawn_point.z))) + 1, int(floor(spawn_point.z)))
		world.set_block(cp, Data.block_id("brick"))
		kit.vitals.hunger = 0.42
		meta["kit"] = kit.to_dict()
		meta["debug_check"] = [cp.x, cp.y, cp.z, Data.block_id("brick")]
	var err := SaveSystem.write(meta, world)
	EventBus.toast.emit("Saved." if err == OK else "Save failed: %s" % error_string(err), 1.5)
	return err


func _apply_save(meta: Dictionary) -> void:
	var c: Dictionary = meta.get("clock", {})
	clock.day = int(c.get("day", 1))
	clock.day_fraction = float(c.get("day_fraction", clock.day_fraction))
	var pl: Dictionary = meta.get("player", {})
	if pl.has("pos"):
		var p: Array = pl["pos"]
		player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		streamer.set_focus([player.global_position])
		streamer.preload_around(player.global_position, 1)
		props.keep_clear = Vector3(INF, INF, INF)
		player.set_look(float(pl.get("yaw", 0.0)), float(pl.get("pitch", -0.15)))
		player.hotbar_index = int(pl.get("quick", 0))
	# Replace the starting kit with the saved one.
	kit.equipment = Equipment.new()
	kit.equipment.changed.connect(_refresh_quick)
	kit.from_dict(meta.get("kit", {}), Data)
	inventory_ui.kit = kit
	inventory_ui._rebuild()
	for h in meta.get("hazards", {}):
		hazards.next_event_day[h] = float(meta["hazards"][h])
	if gas_hazard != null:
		gas_hazard.events_so_far = int(meta.get("hazard_events", 0))
	var pr: Dictionary = meta.get("props", {})
	for r in pr.get("removed", []):
		props.removed[Vector2i(int(r[0]), int(r[1]))] = true
	for r in pr.get("regrow", []):
		props.regrow_at[Vector2i(int(r[0]), int(r[1]))] = float(r[2])
	# Re-populate columns so removed trees vanish and bushes shrink.
	for col in props._columns.keys():
		for n in props._columns[col]:
			if is_instance_valid(n):
				if n is Creature:
					props.creatures.erase(n)
				n.queue_free()
	props._columns.clear()
	props.set_focus(player.global_position)
	for cr in props.creatures:
		_on_creature_spawned(cr)
	for entry in meta.get("pickups", []):
		var it := kit._item_from_dict(entry.get("item", {}), {})
		var pos: Array = entry.get("pos", [0, 0, 0])
		if it != null:
			spawn_pickup(it, Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
	_refresh_quick()
	EventBus.toast.emit("Loaded save: %s" % clock.clock_text(), 3.0)
	if meta.has("debug_check"):
		var dc: Array = meta["debug_check"]
		var p := Vector3i(int(dc[0]), int(dc[1]), int(dc[2]))
		world.get_or_generate_chunk(WorldData.chunk_pos_of(p))
		print("[savetest] block at %s = %d (expected %d) | hunger %.2f (expected 0.42) | day %d | items %d" % [str(p), world.get_block(p), int(dc[3]), kit.vitals.hunger, clock.day, kit.equipment.all_items().size()])


func _close_all_screens() -> void:
	if pause_menu != null and pause_menu.is_open:
		pause_menu.close()
	for s in [inventory_ui, health_ui, crafting_ui]:
		if s.is_open:
			s.close()


func _toggle_screen(screen: CanvasLayer) -> void:
	if screen.is_open:
		screen.close()
	else:
		_close_all_screens()
		_open_screen(screen)


func _update_aim_text(h: VoxelRay.Hit) -> void:
	if _nearest_pickup != null:
		hud.set_aim_text("E: take %s" % _nearest_pickup.item.display_name())
		return
	var ih := player.interact_hit
	if not ih.is_empty() and (not h.hit or float(ih["distance"]) < h.distance + 0.5):
		var col: Object = ih["collider"]
		if col is Creature:
			hud.set_aim_text("%s%s  (LMB hit)" % [str((col as Creature).kind).capitalize(), " (dead)" if (col as Creature).dead else ""])
			return
		var prop := props.prop_from_collider(col)
		if prop != null:
			var cfg := props.harvest_config(prop)
			var gname := str(prop.get_meta("generator", "prop")).replace("_", " ")
			hud.set_aim_text("%s  (E: harvest %s)" % [gname.capitalize(), str(cfg.get("id", ""))] if not cfg.is_empty() else gname.capitalize())
			return
	if h.hit:
		var mp := Data.block(world.get_block(h.pos))
		hud.set_aim_text(mp.display + ("  (E: drink / refill)" if mp.fluid else ""))
	else:
		hud.set_aim_text("")


# ---- kit / items ----

func _refresh_quick() -> void:
	var items: Array = []
	for i in Equipment.QUICK_SLOTS:
		items.append(kit.equipment.quick_item(i))
	hud.set_quick_slots(items, player.hotbar_index)


func _on_use_item(item: ItemInstance) -> void:
	if item == null:
		EventBus.toast.emit("Empty slot", 0.8)
		return
	if item.id == "breather":
		kit.toggle_breather()
		return
	if item.category() == "medical":
		if not item.examined:
			if kit.start_examine(item):
				EventBus.toast.emit("Examining...", 1.0)
			return
		# Pick the part that needs it most.
		var best := ""
		var best_score := -1.0
		for part in BodyHealth.PARTS:
			var plan := kit.body.med_plan(item.def, part, item.uses_left, item.hp_pool)
			if not plan["ok"]:
				continue
			var score := 1.0
			for e in kit.body.effects_on(part):
				score += 2.0
			score += (1.0 - float(kit.body.hp[part]) / maxf(float(kit.body.max_hp[part]), 1.0)) * 3.0
			if score > best_score:
				best_score = score
				best = part
		if best == "":
			EventBus.toast.emit("Nothing for %s to treat" % item.display_name(), 1.5)
			return
		var plan := kit.start_med(item, best)
		if plan["ok"]:
			EventBus.toast.emit("Using %s on %s" % [item.display_name(), HealthScreen.PART_NAMES[best]], 1.5)
		return
	if item.category() == "food":
		var plan := kit.start_eat(item)
		if plan["ok"]:
			EventBus.toast.emit("%s..." % ("Drinking" if float((item.def.get("food", {}) as Dictionary).get("thirst", 0.0)) > 0.0 else "Eating"), 1.0)
		return
	if item.is_block():
		EventBus.toast.emit("Right-click to place %s" % item.display_name(), 1.0)
		return
	if not item.examined:
		kit.start_examine(item)
		EventBus.toast.emit("Examining...", 1.0)


func _on_action_finished(kind: String, result: Dictionary) -> void:
	match kind:
		"med":
			var healed := float(result.get("healed", 0.0))
			var removed: Array = result.get("removed", [])
			var bits: PackedStringArray = []
			if healed > 0.0:
				bits.append("+%d hp" % int(round(healed)))
			for r in removed:
				bits.append("stopped %s" % str(r).replace("_", " "))
			if bits.is_empty():
				bits.append("done")
			EventBus.toast.emit(", ".join(bits), 2.0)
			if sounds != null:
				sounds.play("ui_blip")
		"examine":
			var it: ItemInstance = result.get("item")
			if it != null:
				EventBus.toast.emit("It's a %s." % it.display_name(), 2.0)
		"eat":
			EventBus.toast.emit("That was bad." if bool(result.get("poisoned", false)) else "Better.", 1.5)
		"craft":
			var made: Array = result.get("made", [])
			var names: PackedStringArray = []
			for m in made:
				names.append("%s x%d" % [(m as ItemInstance).display_name(), (m as ItemInstance).count])
			EventBus.toast.emit("Made %s" % ", ".join(names), 2.0)
			for o in result.get("overflow", []):
				spawn_pickup(o, player.global_position + Vector3(0, 0.5, 0))
			if sounds != null:
				sounds.play("ui_blip")
		"harvest":
			var target: Node3D = result.get("target")
			var cfg: Dictionary = result.get("cfg", {})
			if target == null or not is_instance_valid(target):
				return
			if session.is_online() and not session.is_server():
				replicator.send_harvest(target.get_meta("cell"))
				return
			var at := target.global_position
			var cell: Vector2i = target.get_meta("cell")
			props.harvest(target)
			if session.is_online():
				replicator.broadcast_prop_harvested(cell, float(props.regrow_at.get(cell, 0.0)), props.removed.has(cell))
			_give_or_drop(str(cfg.get("id", "")), cfg.get("count", [1, 1]), at)
			if cfg.has("extra"):
				var ex: Dictionary = cfg["extra"]
				_give_or_drop(str(ex.get("id", "")), ex.get("count", [1, 1]), at)
			if sounds != null:
				sounds.play("dig")


## Swinging at the ground where roaches are kills a few (server side).
func _swat_roaches() -> void:
	if flood_hazard == null or not session.is_server():
		return
	var cells: Array[Vector3i] = [Vector3i(player.global_position.floor()), Vector3i(player.global_position.floor()) + Vector3i(0, 1, 0)]
	if player._aim.hit:
		cells.append(player._aim.prev)
	var killed := 0
	for c in cells:
		killed += flood_hazard.swarm.kill_in_cell(c, 3)
	if killed > 0:
		flood_hazard.swarm.prune_dead()
		EventBus.toast.emit("Squashed %d" % killed, 0.8)
		if kit.rng.randf() < 0.3 * killed:
			_give_or_drop("roach_meat", 1, player.global_position)


func _roaches_vs_fire() -> void:
	var sw := flood_hazard.swarm
	var any := false
	for a in sw.agents:
		if not a.alive:
			continue
		for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
			if Data.block(world.get_block(a.cell + d)).heat > 0.0:
				a.alive = false
				any = true
				break
	if any:
		sw.prune_dead()


func _give_or_drop(id: String, count_range: Variant, at: Vector3) -> void:
	var n := 1
	if count_range is Array and (count_range as Array).size() == 2:
		n = kit.rng.randi_range(int(count_range[0]), int(count_range[1]))
	elif count_range is int or count_range is float:
		n = int(count_range)
	if n <= 0 or id == "":
		return
	var item := Data.make_item(id, n)
	if item == null:
		return
	item.examined = true
	if kit.equipment.add_item(item):
		EventBus.toast.emit("+%d %s" % [n, item.display_name()], 1.5)
	else:
		spawn_pickup(item, at + Vector3(0, 0.5, 0))
		EventBus.toast.emit("%s dropped (no room)" % item.display_name(), 1.5)


func _on_creature_spawned(cr: Creature) -> void:
	if _connected_creatures.has(cr.get_instance_id()):
		return
	_connected_creatures[cr.get_instance_id()] = true
	cr.died.connect(_on_creature_died)


func _on_creature_died(cr: Creature, cause: String) -> void:
	if cause == "suffocation":
		return  # corpses from the gas stay as warning signs; no loot
	for d in cr.drops:
		var id := str(d.get("id", ""))
		var n := kit.rng.randi_range(int(d.get("count", [1, 1])[0]), int(d.get("count", [1, 1])[1]))
		if n > 0 and id != "":
			var item := Data.make_item(id, n)
			if item != null:
				item.examined = true
				spawn_pickup(item, cr.global_position + Vector3(0, 0.4, 0))


func _on_attack(target: Node) -> void:
	if target is Creature:
		var cr := target as Creature
		if cr.dead:
			return
		if session.is_online() and not session.is_server():
			replicator.send_attack(cr.net_id)
			player.add_shake(0.08, 0.15)
			return
		var died := cr.hit(12.0, player.global_position, "blunt")
		player.add_shake(0.08, 0.15)
		if sounds != null:
			sounds.play("dig")
		EventBus.toast.emit("Killed %s" % cr.kind if died else "Hit %s" % cr.kind, 0.8)


func _on_landed(impact: float) -> void:
	if impact <= 11.0 or player.fly:
		return
	var dmg := (impact - 11.0) * 4.5
	kit.body.damage("left_leg", dmg * 0.5, "fall", kit.rng)
	kit.body.damage("right_leg", dmg * 0.5, "fall", kit.rng)
	player.add_shake(0.3, 0.4)
	EventBus.toast.emit("Hard landing (-%d)" % int(dmg), 1.5)
	if sounds != null:
		sounds.play("heartbeat")


func spawn_pickup(item: ItemInstance, pos: Vector3) -> ItemPickup:
	if session.is_online() and not session.is_server():
		replicator.send_drop(item.to_dict(), pos)
		return null
	var id := next_pickup_id
	next_pickup_id += 1
	var p := _make_pickup(item, pos, id)
	if session.is_online():
		replicator.broadcast_pickup_spawn(id, item.to_dict(), pos)
	return p


func _make_pickup(item: ItemInstance, pos: Vector3, id: int) -> ItemPickup:
	var p := ItemPickup.new()
	pickups_root.add_child(p)
	p.setup(item, pickup_material, world)
	p.global_position = pos
	p.set_meta("net_id", id)
	pickups.append(p)
	pickups_by_id[id] = p
	return p


func _remove_pickup(p: ItemPickup) -> void:
	var id := int(p.get_meta("net_id", 0))
	pickups.erase(p)
	pickups_by_id.erase(id)
	p.queue_free()
	if session.is_online() and session.is_server():
		replicator.broadcast_pickup_remove(id)


func nearby_pickups() -> Array:
	var out: Array = []
	for p in pickups:
		if is_instance_valid(p) and p.global_position.distance_to(player.global_position) < 2.4:
			out.append(p)
	return out


func take_pickup(p: ItemPickup) -> void:
	if not is_instance_valid(p):
		return
	if session.is_online() and not session.is_server():
		replicator.send_take_pickup(int(p.get_meta("net_id", 0)))
		return
	if kit.equipment.add_item(p.item):
		EventBus.toast.emit("Took %s" % p.item.display_name(), 1.2)
		_remove_pickup(p)
		if sounds != null:
			sounds.play("ui_blip")
	else:
		EventBus.toast.emit("No room for %s" % p.item.display_name(), 1.2)


func _on_interact() -> void:
	if _nearest_pickup != null:
		take_pickup(_nearest_pickup)
		return
	if kit.busy():
		EventBus.toast.emit("Busy", 0.6)
		return
	var ih := player.interact_hit
	if not ih.is_empty():
		var prop := props.prop_from_collider(ih["collider"])
		if prop != null:
			var cfg := props.harvest_config(prop)
			if cfg.is_empty():
				EventBus.toast.emit("Nothing to take here yet", 1.0)
				return
			if kit.start_harvest(prop, cfg, str(prop.get_meta("generator", "prop"))):
				EventBus.toast.emit("Harvesting...", 1.0)
			return
	# A tag set on a cairn starts a vigil (co-op revival).
	var aim := player._aim
	if aim.hit and Data.block(world.get_block(aim.pos)).name == "cairn":
		var tag := player.selected_item()
		if tag != null and tag.id == "player_tag":
			replicator.send_place_tag(aim.pos, int(tag.data.get("owner", 0)), str(tag.data.get("owner_name", "someone")))
			kit.equipment.remove_item(tag)
			return
		EventBus.toast.emit("Select a Survivor's Tag and press E to start the vigil.", 2.0)
		return
	# Water: drink and refill canteens.
	if aim.hit and Data.block(world.get_block(aim.pos)).fluid:
		kit.vitals.consume({"thirst": 0.25})
		var n := kit.refill_water()
		EventBus.toast.emit("You drink.%s" % ("  Canteen refilled." if n > 0 else ""), 1.5)
		if sounds != null:
			sounds.play("ui_low")


func _debug_text() -> String:
	var phase := "none"
	var cells := 0
	var nxt := 0.0
	if gas_hazard != null:
		phase = HazardModule.Phase.keys()[gas_hazard.phase]
		cells = gas_hazard.sim.cells.size()
		nxt = hazards.seconds_until_next(gas_hazard)
	return "fps %d | pos %s | chunks %d/%d | gas %s cells %d next %ds | o2 %.2f hp %.0f/%.0f | %.1f kg | items %d" % [
		Engine.get_frames_per_second(), str(player.global_position.floor()), streamer.meshed_count(), streamer.loaded_count(),
		phase, cells, int(nxt), vitals.oxygen, kit.body.total_hp(), kit.body.total_max(), kit.equipment.total_weight(), kit.equipment.all_items().size()]


func _on_day_changed(day: int) -> void:
	EventBus.toast.emit("Day %d" % day, 3.0)
	if not ended and day > int(mode.get("days", 100)):
		_finish(true)


func _physics_process(delta: float) -> void:
	if ended or player == null:
		return
	_net_tick(delta)
	var dt := delta * clock.time_scale
	if ghost:
		return
	var exposure := 0.0
	if gas_hazard != null:
		exposure = gas_hazard.exposure_at(player.global_position)
	# Planet 02: water and roaches.
	player.swim = 0
	if flood_hazard != null:
		player.swim = flood_hazard.submersion(player.global_position)
		if player.swim == 2:
			exposure = 1.0  # no air under water
		if session.is_server():
			for b in flood_hazard.take_bites():
				var cell: Vector3i = b[0]
				var count := int(b[1])
				var hit_local := cell == Vector3i(player.global_position.floor()) or cell == Vector3i(player.global_position.floor()) + Vector3i(0, 1, 0)
				if hit_local and not ghost:
					replicator.remote_damage.emit(flood_hazard.swarm.bite_damage * count, "bite")
				elif session.is_online():
					for peer in replicator.peer_states:
						if peer == session.local_peer_id:
							continue
						var pp: Vector3 = replicator.peer_states[peer]["pos"]
						if Vector3i(pp.floor()) == cell or Vector3i(pp.floor()) + Vector3i(0, 1, 0) == cell:
							replicator.damage_peer(peer, flood_hazard.swarm.bite_damage * count, "bite")
			_fire_accum += delta
			if _fire_accum >= 0.5:
				_fire_accum = 0.0
				_roaches_vs_fire()
		if swarm_renderer != null:
			swarm_renderer.update(flood_hazard.swarm_positions())
	if _bitten_timer > 0.0:
		_bitten_timer -= delta
	# Planet 01: sunlight burns exposed skin.
	_burning = false
	if eclipse_hazard != null and not ghost:
		var sun_exp := eclipse_hazard.exposure_at(player.global_position)
		if sun_exp > 0.0:
			_burning = true
			var dps := eclipse_hazard.burn_damage_per_second() * sun_exp
			kit.body.damage("head", dps * dt * 0.3, "burn", kit.rng)
			kit.body.damage("left_arm", dps * dt * 0.2, "burn", kit.rng)
			kit.body.damage("right_arm", dps * dt * 0.2, "burn", kit.rng)
			kit.body.damage("thorax", dps * dt * 0.3, "burn", kit.rng)
		if session.is_server() and props != null and eclipse_hazard.phase == HazardModule.Phase.ACTIVE:
			for cr in props.creatures:
				if is_instance_valid(cr) and not cr.dead and eclipse_hazard.sim.exposure(cr.global_position, 0.8) >= eclipse_hazard.sim.burn_threshold:
					cr.vitals.damage(eclipse_hazard.burn_damage_per_second() * dt * 0.8, "burn")
					if not cr.vitals.alive:
						cr.die("burn")
	vitals.breathe(kit.filtered_gas(exposure, dt), dt)
	var dt_game := dt * clock.game_seconds_per_second()
	vitals.metabolize(dt_game, {"ambient": ambient_temperature(), "sheltered": is_sheltered(), "heat_source": heat_near_player()})
	vitals.exert(dt, player.sprinting)
	player.sprint_allowed = vitals.can_sprint()
	kit.tick(dt, dt_game)
	var pen := kit.penalties()
	player.speed_multiplier = float(pen["move_speed"])
	player.aim_jitter = float(pen["aim_shake"])
	# Creatures obey the same rule (and die first on low ground: a warning sign).
	if session.is_server() and gas_hazard != null and props != null and not gas_hazard.sim.cells.is_empty():
		for cr in props.creatures:
			if is_instance_valid(cr) and not cr.dead:
				cr.breathe(gas_hazard.exposure_at(cr.global_position, 0.8), dt)
	# Nearest pickup for the E prompt.
	_nearest_pickup = null
	var best := 2.4
	for p in pickups:
		if is_instance_valid(p):
			var d := p.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				_nearest_pickup = p
	_vitals_accum += delta
	if _vitals_accum >= 0.1:
		_vitals_accum = 0.0
		var v := vitals.to_dict()
		v["hp"] = kit.body.total_hp()
		v["max_hp"] = kit.body.total_max()
		v["action_kind"] = str(kit.action.get("kind", "")) if kit.busy() else ""
		v["action_progress"] = kit.action_progress()
		v["pain"] = pen["pain"]
		v["overweight"] = pen["overweight"]
		v["bleeding"] = kit.body.has_effect("light_bleed") or kit.body.has_effect("heavy_bleed")
		v["fracture"] = kit.body.has_effect("fracture")
		v["breather"] = kit.breather_active
		v["filter"] = kit.filter_seconds
		v["poisoned"] = kit.body.has_effect("poison")
		v["burning"] = _burning
		v["swim"] = player.swim
		v["bitten"] = _bitten_timer > 0.0
		EventBus.vitals_changed.emit(v)


func _finish(won: bool, cause: String = "") -> void:
	if ended:
		return
	if not won and session.is_online() and not ghost:
		_become_ghost(cause)
		return
	ended = true
	player.input_enabled = false
	_close_all_screens()
	hud.root.visible = true
	if sounds != null:
		sounds.stop_all_loops()
		sounds.play("ui_low")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.end_run(won, clock.day)
	if not won:
		hud.set_death_cause(cause if cause != "" else vitals.last_damage_cause)
		EventBus.player_died.emit(cause)


func _exit_tree() -> void:
	if verbose and gas_hazard == null and hazards != null and not hazards.modules.is_empty():
		var m := hazards.modules[0]
		var extra := ""
		if eclipse_hazard != null:
			extra = "burned blocks %d" % eclipse_hazard.burned_total
		elif flood_hazard != null:
			extra = "peak level %.1f (base %.1f), wet cells %d, roaches %d alive, bites %d" % [flood_hazard.peak_level, flood_hazard.sim.base_level, flood_hazard.sim.wet.size(), flood_hazard.swarm.count_alive(), flood_hazard.bites_total]
		print("[run] summary: hazard %s events %d phase %s | %s | props %d, creatures %d | body %.0f/%.0f alive %s" % [m.id, m.events_so_far, HazardModule.Phase.keys()[m.phase], extra, props.prop_count(), props.creatures.size(), kit.body.total_hp(), kit.body.total_max(), str(kit.body.alive)])
	if verbose and gas_hazard != null:
		var dead := 0
		for cr in props.creatures:
			if is_instance_valid(cr) and cr.dead:
				dead += 1
		print("[run] summary: gas events %d, peak gas cells %d (mass %.1f), props %d, creatures %d (%d dead), items %d (%.1f kg), body %.0f/%.0f, o2 %.2f alive %s" % [
			gas_hazard.events_so_far, gas_hazard.peak_cells, gas_hazard.peak_mass, props.prop_count(), props.creatures.size(), dead,
			kit.equipment.all_items().size(), kit.equipment.total_weight(), kit.body.total_hp(), kit.body.total_max(), vitals.oxygen, str(kit.body.alive)])


func _process(_delta: float) -> void:
	_frame += 1
	if pause_menu != null and pause_menu.is_open:
		if Input.is_action_just_pressed("pause"):
			_close_pause()
		return
	if verbose and Game.args.has("nettest"):
		var cp := Vector3i(int(floor(spawn_point.x)) + 2, generator.height_at(int(floor(spawn_point.x)) + 2, int(floor(spawn_point.z)) + 2), int(floor(spawn_point.z)) + 2)
		if not session.is_server() and _frame == 150:
			session.submit({"type": "dig", "pos": cp, "from": Vector3(cp) + Vector3(0.5, 2.5, 0.5)})
			print("[nettest] client: dig requested at %s" % str(cp))
		if _frame % 100 == 0:
			print("[nettest] %s: block %s = %d | remote players %d | peers %s | gas cells %d | day %d %s" % ["host" if session.is_server() else "client", str(cp), world.get_block(cp), remote_players.size(), str(Net.peer_ids()), gas_hazard.sim.cells.size() if gas_hazard != null else -1, clock.day, clock.clock_text()])
	if verbose and Game.args.has("savetest") and _frame == 30:
		clock.day = 2
		print("[savetest] save -> %s" % error_string(save_game()))
	if verbose and _frame % 20 == 0 and gas_hazard == null and hazards != null and not hazards.modules.is_empty():
		var m := hazards.modules[0]
		var extra := ""
		if eclipse_hazard != null:
			extra = "light %.2f exposure %.2f burned %d" % [eclipse_hazard.light_factor, eclipse_hazard.exposure_at(player.global_position), eclipse_hazard.burned_total]
		elif flood_hazard != null:
			extra = "level %.1f wet %d swim %d roaches %d bites %d" % [flood_hazard.sim.level, flood_hazard.sim.wet.size(), player.swim, flood_hazard.swarm.count_alive(), flood_hazard.bites_total]
		print("[run] frame %d: %s | %s %s t=%.1f | %s | hp %.0f" % [_frame, clock.clock_text(), m.id, HazardModule.Phase.keys()[m.phase], m.phase_time, extra, kit.body.total_hp()])
	if verbose and _frame % 20 == 0 and gas_hazard != null:
		print("[run] frame %d: %s | hazard %s t=%.1f cells=%d sources=%d | exposure %.2f o2 %.2f hp %.0f" % [
			_frame, clock.clock_text(), HazardModule.Phase.keys()[gas_hazard.phase], gas_hazard.phase_time,
			gas_hazard.sim.cells.size(), gas_hazard.sim.sources.size(), gas_hazard.exposure_at(player.global_position), vitals.oxygen, kit.body.total_hp()])
	if player != null and streamer != null:
		streamer.set_focus([player.global_position])
		if props != null:
			props.set_focus(player.global_position)
	if hud != null and clock != null:
		hud.set_clock_text(clock.clock_text())
	if sun != null and clock != null:
		if static_sun:
			_update_eclipse_lighting()
		else:
			_update_day_night()
	if ended:
		if Input.is_action_just_pressed("restart"):
			Game.start_run(planet_id, mode_id, world_seed + 1)
		elif Input.is_action_just_pressed("pause"):
			Game.return_to_orbit()
		return
	if Input.is_action_just_pressed("inventory"):
		_toggle_screen(inventory_ui)
	elif Input.is_action_just_pressed("health_screen"):
		_toggle_screen(health_ui)
	elif Input.is_action_just_pressed("crafting"):
		_toggle_screen(crafting_ui)
	if Input.is_action_just_pressed("dig") and player.input_enabled and not ghost and flood_hazard != null:
		_swat_roaches()
	if Input.is_action_just_pressed("debug_time_scale") and clock != null:
		clock.time_scale = 1.0 if clock.time_scale > 1.0 else 20.0
		EventBus.toast.emit("time x%d" % int(clock.time_scale), 1.5)
	if Input.is_action_just_pressed("debug_trigger_hazard") and hazards != null:
		hazards.debug_trigger_any()
	if Input.is_action_just_pressed("debug_overlay") and hud != null:
		hud.set_debug_visible(not hud.debug_label.visible)
	if Input.is_action_just_pressed("debug_reload_render"):
		var s := Data.reload_render_settings()
		pipeline.apply_settings(s)
		for m in [streamer.opaque_material, streamer.transparent_material]:
			if m is ShaderMaterial:
				MaterialFactory.apply_settings(m, s)
		EventBus.toast.emit("render settings reloaded", 1.5)
	if Input.is_action_just_pressed("pause"):
		if pause_menu.is_open:
			_close_pause()
		elif any_screen_open():
			_close_all_screens()
		else:
			_open_pause()
	_autosave_accum += _delta
	if _autosave_accum >= autosave_interval and not ended and not pause_menu.is_open and not (session.is_online() and not session.is_server()):
		_autosave_accum = 0.0
		save_game()
