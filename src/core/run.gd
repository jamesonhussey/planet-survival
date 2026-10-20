extends Node
## One survival run. Built entirely from code by Game.start_run(). Owns the
## PS1 pipeline (low-res viewport), the world, the authority (Session +
## WorldCommands), the streamer, the player, the clock, hazards, vitals,
## telegraph/sound and the HUD.

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
var clock: GameClock
var hazards: HazardDirector
var gas_hazard: HeavyGasHazard
var gas_renderer: GasRenderer
var telegraph: Telegraph
var props: PropSpawner
var sounds: SoundBank
var vitals: Vitals
var hud: HUD
var world_root: Node3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var spawn_point: Vector3
var ended: bool = false
var verbose: bool = false
var _frame: int = 0
var _vitals_accum: float = 0.0
var _hotbar_names: Array = []


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
	player = PlayerController.new()
	player.name = "Player"
	var hotbar: Array[int] = []
	_hotbar_names.clear()
	for n in ["planks", "stone", "brick", "glass", "thatch", "dirt", "clay"]:
		hotbar.append(Data.block_id(n))
		_hotbar_names.append(Data.block(Data.block_id(n)).display)
	player.configure(session, world, streamer, hotbar)
	view.add_child(player)
	player.global_position = spawn_point
	player.set_look(0.0, -0.15)
	var listener := AudioListener3D.new()
	player.camera.add_child(listener)
	listener.make_current()
	streamer.set_focus([spawn_point])
	vitals = Vitals.new()
	vitals.configure(planet.get("vitals", {}))


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
	props = PropSpawner.new()
	props.name = "Props"
	view.add_child(props)
	props.keep_clear = spawn_point
	props.setup(world, generator, planet, world_seed,
		MaterialFactory.voxel_model(Data.render, false),
		MaterialFactory.voxel_model(Data.render, true))
	props.set_focus(spawn_point)
	hud = HUD.new()
	hud.name = "HUD"
	view.add_child(hud)
	hud.set_hotbar(_hotbar_names, player.hotbar_index)
	hud.debug_provider = _debug_text
	player.hotbar_changed.connect(func(i: int, _b: int) -> void: hud.set_hotbar(_hotbar_names, i))
	player.aim_changed.connect(func(h: VoxelRay.Hit) -> void:
		hud.set_aim_text(Data.block(world.get_block(h.pos)).display if h.hit else ""))
	EventBus.toast.emit("%s  -  %s" % [planet.get("name", ""), planet.get("tagline", "")], 5.0)
	EventBus.toast.emit("WASD move, LMB dig, RMB place, 1-7 blocks, F flashlight, F5 eruption, F3 debug", 8.0)


func _debug_text() -> String:
	var phase := "none"
	var cells := 0
	var nxt := 0.0
	if gas_hazard != null:
		phase = HazardModule.Phase.keys()[gas_hazard.phase]
		cells = gas_hazard.sim.cells.size()
		nxt = hazards.seconds_until_next(gas_hazard)
	return "fps %d | pos %s | chunks %d/%d | gas %s cells %d next %ds | o2 %.2f hp %.0f" % [
		Engine.get_frames_per_second(), str(player.global_position.floor()), streamer.meshed_count(), streamer.loaded_count(),
		phase, cells, int(nxt), vitals.oxygen, vitals.hp]


func _on_day_changed(day: int) -> void:
	EventBus.toast.emit("Day %d" % day, 3.0)
	if not ended and day > int(mode.get("days", 100)):
		_finish(true)


func _physics_process(delta: float) -> void:
	if ended or player == null:
		return
	var exposure := 0.0
	if gas_hazard != null:
		exposure = gas_hazard.exposure_at(player.global_position)
	vitals.breathe(exposure, delta * clock.time_scale)
	# Creatures obey the same rule (and die first on low ground: a warning sign).
	if gas_hazard != null and props != null and not gas_hazard.sim.cells.is_empty():
		for cr in props.creatures:
			if is_instance_valid(cr) and not cr.dead:
				cr.breathe(gas_hazard.exposure_at(cr.global_position, 0.8), delta * clock.time_scale)
	_vitals_accum += delta
	if _vitals_accum >= 0.1:
		_vitals_accum = 0.0
		EventBus.vitals_changed.emit(vitals.to_dict())
	if not vitals.alive:
		_finish(false)


func _finish(won: bool) -> void:
	ended = true
	player.input_enabled = false
	if sounds != null:
		sounds.stop_all_loops()
		sounds.play("ui_low")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.end_run(won, clock.day)
	if not won:
		EventBus.player_died.emit(vitals.last_damage_cause)


func _exit_tree() -> void:
	if verbose and gas_hazard != null:
		var dead := 0
		for cr in props.creatures:
			if is_instance_valid(cr) and cr.dead:
				dead += 1
		print("[run] summary: gas events %d, peak gas cells %d (mass %.1f), props %d, creatures %d (%d dead), player o2 %.2f hp %.0f alive %s" % [
			gas_hazard.events_so_far, gas_hazard.peak_cells, gas_hazard.peak_mass, props.prop_count(), props.creatures.size(), dead, vitals.oxygen, vitals.hp, str(vitals.alive)])


func _process(_delta: float) -> void:
	_frame += 1
	if verbose and _frame % 20 == 0 and gas_hazard != null:
		print("[run] frame %d: %s | hazard %s t=%.1f cells=%d sources=%d | exposure %.2f o2 %.2f hp %.0f" % [
			_frame, clock.clock_text(), HazardModule.Phase.keys()[gas_hazard.phase], gas_hazard.phase_time,
			gas_hazard.sim.cells.size(), gas_hazard.sim.sources.size(), gas_hazard.exposure_at(player.global_position), vitals.oxygen, vitals.hp])
	if player != null and streamer != null:
		streamer.set_focus([player.global_position])
		if props != null:
			props.set_focus(player.global_position)
	if hud != null and clock != null:
		hud.set_clock_text(clock.clock_text())
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
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not ended:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if ended and Input.is_action_just_pressed("restart"):
		Game.start_run(planet_id, mode_id, world_seed + 1)
