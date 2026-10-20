extends Node
## One survival run. Built entirely from code by Game.start_run(). Owns the
## PS1 pipeline (low-res viewport), the world, the authority (Session +
## WorldCommands), the streamer, the player and their kit (inventory +
## body health), the clock, hazards, vitals, telegraph/sound, pickups and
## the UI screens.

var planet_id: String = "04"
var mode_id: String = "standard"
var world_seed: int = 1337

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
var gas_renderer: GasRenderer
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
	# --hurt: pre-damage the body so the health screen has something to show.
	if Game.args.has("hurt"):
		kit.body.damage("left_leg", 30.0, "blunt", kit.rng)
		kit.body.damage("right_arm", 18.0, "cut", kit.rng)
		kit.body.add_effect("light_bleed", "right_arm")
		kit.body.add_effect("fracture", "left_leg")


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
	generator = ChunkGenerator.new(world_seed, planet.get("terrain", {}), Data.material_ids, world.world_height)
	world.generator = generator
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
	session.setup_local_host(commands)
	commands.block_dug.connect(func(_peer: int, pos: Vector3i, _id: int) -> void:
		_after_edit(pos)
		if sounds != null: sounds.play("dig"))
	commands.block_placed.connect(func(_peer: int, pos: Vector3i, _id: int) -> void:
		_after_edit(pos)
		if sounds != null: sounds.play("place"))
	commands.command_rejected.connect(func(_peer: int, _cmd: Dictionary, reason: String) -> void:
		if reason != "nothing to dig" and reason != "occupied":
			EventBus.toast.emit(reason, 1.0))
	commands.item_overflow.connect(func(_peer: int, pos: Vector3i, item: ItemInstance) -> void:
		spawn_pickup(item, Vector3(pos) + Vector3(0.5, 0.2, 0.5))
		EventBus.toast.emit("Inventory full: %s dropped" % item.display_name(), 1.5))


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


func _build_player() -> void:
	kit = PlayerKit.new(world_seed)
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
	var listener := AudioListener3D.new()
	player.camera.add_child(listener)
	listener.make_current()
	streamer.set_focus([spawn_point])
	vitals = Vitals.new()
	vitals.configure(planet.get("vitals", {}))
	vitals.damage_sink = func(amount: float, cause: String) -> void: kit.body.damage_all(amount, cause)
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
	})
	gas_hazard = hazards.get_module("limnic_eruption") as HeavyGasHazard
	if gas_hazard == null:
		for m in hazards.modules:
			if m is HeavyGasHazard:
				gas_hazard = m
				break


func _build_presentation() -> void:
	sounds = SoundBank.new()
	sounds.name = "Sounds"
	add_child(sounds)
	telegraph = Telegraph.new()
	telegraph.name = "Telegraph"
	view.add_child(telegraph)
	telegraph.setup(sounds, player, pipeline)
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
	props.setup(world, generator, planet, world_seed, pickup_material, MaterialFactory.voxel_model(Data.render, true))
	props.set_focus(spawn_point)

	hud = HUD.new()
	hud.name = "HUD"
	view.add_child(hud)
	hud.debug_provider = _debug_text
	player.hotbar_changed.connect(func(_i: int) -> void: _refresh_quick())
	kit.equipment.changed.connect(_refresh_quick)
	_refresh_quick()
	player.aim_changed.connect(func(h: VoxelRay.Hit) -> void:
		if _nearest_pickup != null:
			hud.set_aim_text("E: take %s" % _nearest_pickup.item.display_name())
		else:
			hud.set_aim_text(Data.block(world.get_block(h.pos)).display if h.hit else ""))

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

	EventBus.toast.emit("%s  -  %s" % [planet.get("name", ""), planet.get("tagline", "")], 5.0)
	EventBus.toast.emit("WASD move, LMB dig, RMB place, 1-6 quick slots, Q use, Tab inventory, H health, F5 eruption", 8.0)


# ---- screens ----

func _open_screen(screen: CanvasLayer, med: ItemInstance = null) -> void:
	if screen == health_ui:
		health_ui.open(med)
	else:
		(screen as InventoryUI).open()
	player.input_enabled = false
	hud.root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Warp the cursor to the screen centre so it is visible immediately.
	var win := get_viewport().get_visible_rect().size
	Input.warp_mouse(win * 0.5)


func _on_screen_closed() -> void:
	if inventory_ui.is_open or health_ui.is_open or ended:
		return
	hud.root.visible = true
	player.input_enabled = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func any_screen_open() -> bool:
	return inventory_ui.is_open or health_ui.is_open


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
	var p := ItemPickup.new()
	pickups_root.add_child(p)
	p.setup(item, pickup_material, world)
	p.global_position = pos
	pickups.append(p)
	return p


func nearby_pickups() -> Array:
	var out: Array = []
	for p in pickups:
		if is_instance_valid(p) and p.global_position.distance_to(player.global_position) < 2.4:
			out.append(p)
	return out


func take_pickup(p: ItemPickup) -> void:
	if not is_instance_valid(p):
		return
	if kit.equipment.add_item(p.item):
		EventBus.toast.emit("Took %s" % p.item.display_name(), 1.2)
		pickups.erase(p)
		p.queue_free()
		if sounds != null:
			sounds.play("ui_blip")
	else:
		EventBus.toast.emit("No room for %s" % p.item.display_name(), 1.2)


func _on_interact() -> void:
	if _nearest_pickup != null:
		take_pickup(_nearest_pickup)


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
	var dt := delta * clock.time_scale
	var exposure := 0.0
	if gas_hazard != null:
		exposure = gas_hazard.exposure_at(player.global_position)
	vitals.breathe(kit.filtered_gas(exposure, dt), dt)
	kit.tick(dt)
	var pen := kit.penalties()
	player.speed_multiplier = float(pen["move_speed"])
	player.aim_jitter = float(pen["aim_shake"])
	# Creatures obey the same rule (and die first on low ground: a warning sign).
	if gas_hazard != null and props != null and not gas_hazard.sim.cells.is_empty():
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
		EventBus.vitals_changed.emit(v)


func _finish(won: bool, cause: String = "") -> void:
	if ended:
		return
	ended = true
	player.input_enabled = false
	if inventory_ui.is_open:
		inventory_ui.close()
	if health_ui.is_open:
		health_ui.close()
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
	if ended:
		if Input.is_action_just_pressed("restart"):
			Game.start_run(planet_id, mode_id, world_seed + 1)
		return
	if Input.is_action_just_pressed("inventory"):
		if inventory_ui.is_open:
			inventory_ui.close()
		else:
			if health_ui.is_open:
				health_ui.close()
			_open_screen(inventory_ui)
	elif Input.is_action_just_pressed("health_screen"):
		if health_ui.is_open:
			health_ui.close()
		else:
			if inventory_ui.is_open:
				inventory_ui.close()
			_open_screen(health_ui)
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
		if any_screen_open():
			inventory_ui.close()
			health_ui.close()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
