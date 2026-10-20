class_name PlayerController
extends CharacterBody3D
## First-person controller. Movement is local (client predicted later);
## every world mutation goes through Session.submit(). Hosts the interactor
## (dig/place from the selected quick slot), a flashlight, camera shake and
## debug fly mode. Health/inventory live in `kit` (PlayerKit).

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0022
const EYE_HEIGHT := 1.62
const FLY_SPEED := 18.0

var session: Session = null
var world: WorldData = null
var streamer: ChunkStreamer = null
var kit: PlayerKit = null
var fly: bool = false
var hotbar_index: int = 0            # selected quick slot
var speed_multiplier: float = 1.0    # vitals / weight / injury penalties
var aim_jitter: float = 0.0          # from pain and blacked arms
var input_enabled: bool = true       # false while a UI screen is open or dead

var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var _collision: CollisionShape3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dig_cooldown: float = 0.0
var _place_cooldown: float = 0.0
var _aim: VoxelRay.Hit = VoxelRay.Hit.new()
var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_total: float = 1.0
var _was_on_floor: bool = true

signal aim_changed(hit: VoxelRay.Hit)
signal attack_requested(target: Node)
## Physics hit in front of the camera this frame: {"collider": Object, "position": Vector3, "distance": float} or {}.
var interact_hit: Dictionary = {}
var sprint_allowed: bool = true
## Dead in co-op: floats, watches, cannot touch the world.
var ghost: bool = false
## 0 dry, 1 wading/swimming, 2 head under water (set by the run from the flood sim).
var swim: int = 0
var sprinting: bool = false
var _attack_cooldown: float = 0.0
signal hotbar_changed(index: int)
signal landed(impact_speed: float)
signal use_requested(item: ItemInstance)
signal interact_requested


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_collision.shape = capsule
	_collision.position = Vector3(0, 0.9, 0)
	add_child(_collision)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 300.0
	head.add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 3.0
	flashlight.light_color = Color(1.0, 0.95, 0.8)
	flashlight.visible = false
	flashlight.position = Vector3(0.15, -0.1, 0.0)
	camera.add_child(flashlight)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure(s: Session, w: WorldData, st: ChunkStreamer, player_kit: PlayerKit) -> void:
	session = s
	world = w
	streamer = st
	kit = player_kit


func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = _yaw
	head.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENS, -1.5, 1.5)
		rotation.y = _yaw
		head.rotation.x = _pitch
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("debug_fly"):
		fly = not fly
		velocity = Vector3.ZERO
		EventBus.toast.emit("fly %s" % ("on" if fly else "off"), 1.5)
	elif event.is_action_pressed("hotbar_next"):
		_select_hotbar(hotbar_index + 1)
	elif event.is_action_pressed("hotbar_prev"):
		_select_hotbar(hotbar_index - 1)
	elif event.is_action_pressed("use_item"):
		if not ghost:
			use_requested.emit(selected_item())
	elif event.is_action_pressed("interact"):
		if not ghost:
			interact_requested.emit()
	elif event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_hotbar(hotbar_index - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_hotbar(hotbar_index + 1)
	else:
		for i in Equipment.QUICK_SLOTS:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				_select_hotbar(i)


func _select_hotbar(i: int) -> void:
	hotbar_index = posmod(i, Equipment.QUICK_SLOTS)
	hotbar_changed.emit(hotbar_index)


func selected_item() -> ItemInstance:
	if kit == null:
		return null
	return kit.equipment.quick_item(hotbar_index)


## Block id the selected quick slot would place, or 0.
func selected_block() -> int:
	var it := selected_item()
	if it == null or not it.is_block():
		return 0
	return Data.block_id(it.block_name())


func _physics_process(delta: float) -> void:
	_dig_cooldown = maxf(0.0, _dig_cooldown - delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if fly:
		var up := 0.0
		if input_enabled:
			up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
		var v := wish * FLY_SPEED + Vector3.UP * up * FLY_SPEED
		velocity = velocity.lerp(v, 0.25)
		move_and_slide()
		_was_on_floor = true
	else:
		var speed := WALK_SPEED
		sprinting = false
		if input_enabled and Input.is_action_pressed("sprint") and sprint_allowed and input_dir.length_squared() > 0.0:
			speed = SPRINT_SPEED
			sprinting = true
		elif input_enabled and Input.is_action_pressed("crouch"):
			speed = CROUCH_SPEED
		speed *= speed_multiplier
		if swim > 0:
			speed *= 0.55
			# Buoyancy: sink slowly, swim up while holding jump.
			var up := input_enabled and Input.is_action_pressed("jump")
			velocity.y = move_toward(velocity.y, (2.6 if up else (-0.6 if swim == 2 else -1.2)), 12.0 * delta)
		elif not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif input_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		var accel := 12.0 if is_on_floor() else 3.0
		velocity.x = move_toward(velocity.x, wish.x * speed, accel * speed * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, accel * speed * delta)
		var vy_before := velocity.y
		move_and_slide()
		var on_floor := is_on_floor()
		if on_floor and not _was_on_floor and vy_before < -1.0 and swim == 0:
			landed.emit(-vy_before)
		_was_on_floor = on_floor
		# Safety: never fall out of the world.
		if global_position.y < -8.0:
			global_position.y = float(world.world_height) if world != null else 80.0
			velocity = Vector3.ZERO
	_update_aim()
	_update_interact_hit()
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if input_enabled and not ghost:
		var creature_in_front: bool = not interact_hit.is_empty() and interact_hit["collider"] is Creature and (not _aim.hit or float(interact_hit["distance"]) < _aim.distance)
		if Input.is_action_pressed("dig") and creature_in_front and _attack_cooldown <= 0.0:
			_attack_cooldown = 0.5
			attack_requested.emit(interact_hit["collider"])
		elif Input.is_action_pressed("dig") and _dig_cooldown <= 0.0 and _aim.hit and not creature_in_front:
			_dig_cooldown = 0.22
			session.submit({"type": "dig", "pos": _aim.pos, "from": camera.global_position})
		if Input.is_action_pressed("place") and _place_cooldown <= 0.0 and _aim.hit and selected_block() > 0:
			_place_cooldown = 0.22
			var blocked := _cell_overlaps_body(_aim.prev)
			session.submit({"type": "place", "pos": _aim.prev, "block": selected_block(), "from": camera.global_position, "blocked_by_body": blocked})


func _update_aim() -> void:
	if world == null or camera == null:
		return
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	_aim = VoxelRay.cast(origin, dir, WorldCommands.REACH, func(c: Vector3i) -> bool: return world.is_solid(c))
	aim_changed.emit(_aim)


## Raycast against creatures (layer 4) and prop bodies (layers 1, 8).
func _update_interact_hit() -> void:
	interact_hit = {}
	if camera == null or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * 4.5
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8, [get_rid()])
	var r := space.intersect_ray(q)
	if r.is_empty():
		return
	var collider: Object = r["collider"]
	# Terrain chunks are StaticBodies without metadata; ignore them.
	if collider is Creature or (collider is Node and (collider as Node).has_meta("prop_node")):
		interact_hit = {"collider": collider, "position": r["position"], "distance": from.distance_to(r["position"])}


func _cell_overlaps_body(cell: Vector3i) -> bool:
	var feet := global_position
	var min_b := Vector3(feet.x - 0.35, feet.y, feet.z - 0.35)
	var max_b := Vector3(feet.x + 0.35, feet.y + 1.8, feet.z + 0.35)
	var cmin := Vector3(cell)
	var cmax := cmin + Vector3.ONE
	return (min_b.x < cmax.x and max_b.x > cmin.x) and (min_b.y < cmax.y and max_b.y > cmin.y) and (min_b.z < cmax.z and max_b.z > cmin.z)


func eye_position() -> Vector3:
	return camera.global_position if camera != null else global_position + Vector3.UP * EYE_HEIGHT


## Camera shake (telegraph tremors). Strength in metres of head offset.
func add_shake(strength: float, seconds: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, seconds)
	_shake_total = maxf(_shake_time, 0.01)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var offset := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := _shake_strength * clampf(_shake_time / _shake_total, 0.0, 1.0)
		offset += Vector3(sin(t * 37.0) * k * 0.6, sin(t * 53.0) * k, 0.0) * 0.1
		if _shake_time <= 0.0:
			_shake_strength = 0.0
	if aim_jitter > 0.0:
		offset += Vector3(sin(t * 9.3) * aim_jitter, sin(t * 7.1) * aim_jitter, 0.0) * 0.004
	camera.position = offset
