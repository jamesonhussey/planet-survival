class_name Creature
extends CharacterBody3D
## Base creature: a PartRig body with rigid-part animation and a tiny
## wander brain. Creatures obey the same hazard rules as the player: this
## one breathes, so it suffocates in gas and ends up as a dead-animal warning
## sign on low ground. Server-side logic; presentation is local.

var rig_root: Node3D
var parts: Dictionary = {}
var breathes: bool = true
var vitals := Vitals.new()
var speed: float = 1.4
var wander_timer: float = 0.0
var wander_dir: Vector3 = Vector3.ZERO
var moving: bool = false
var dead: bool = false
var anim_t: float = 0.0
var rng := RandomNumberGenerator.new()
var kind: String = "grazer"
var _dead_tilt: float = 0.0


func setup(rig: PartRig, material: Material, seed: int, creature_kind: String = "grazer") -> void:
	kind = creature_kind
	rng.seed = seed
	rig_root = rig.instantiate(material)
	add_child(rig_root)
	parts = PartRig.part_nodes(rig_root)
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(rig.collision_box.size.x, 0.4), maxf(rig.height, 0.4), maxf(rig.collision_box.size.z, 0.4))
	cs.shape = box
	cs.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(cs)
	vitals.configure({"oxygen_seconds": 18.0, "suffocation_dps": 25.0, "gas_threshold": 0.2})
	vitals.hp = 30.0
	vitals.max_hp = 30.0
	wander_timer = rng.randf_range(0.5, 3.0)


## Called by the run each physics step with the gas concentration here.
func breathe(gas: float, dt: float) -> void:
	if dead or not breathes:
		return
	vitals.breathe(gas, dt)
	if not vitals.alive:
		die("suffocation")


func die(_cause: String) -> void:
	if dead:
		return
	dead = true
	moving = false
	velocity = Vector3.ZERO
	# Grey the fur so the corpse reads at a distance.
	for n in parts.values():
		var mi := (n as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mi != null:
			var mat := mi.material_override
			if mat is ShaderMaterial:
				var dup := (mat as ShaderMaterial).duplicate() as ShaderMaterial
				dup.set_shader_parameter("desaturate", 0.8)
				mi.material_override = dup


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if dead:
		_dead_tilt = move_toward(_dead_tilt, PI * 0.5, delta * 3.0)
		if rig_root != null:
			rig_root.rotation.z = _dead_tilt
			rig_root.position.y = sin(_dead_tilt) * 0.25
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	wander_timer -= delta
	if wander_timer <= 0.0:
		moving = not moving if rng.randf() < 0.6 else moving
		wander_timer = rng.randf_range(1.5, 5.0)
		if moving:
			var a := rng.randf() * TAU
			wander_dir = Vector3(cos(a), 0, sin(a))
	# Flee uphill when the air goes bad: pick the higher neighbouring direction.
	if vitals.suffocating:
		moving = true
	var target := wander_dir * speed * (1.8 if vitals.suffocating else 1.0) if moving else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target.x, 6.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 6.0 * delta)
	if moving and wander_dir.length_squared() > 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(-wander_dir.z, wander_dir.x), 5.0 * delta)
	move_and_slide()
	if is_on_wall() and moving:
		wander_dir = -wander_dir
	_animate(delta)


func _animate(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	anim_t += delta * (6.0 + horizontal * 4.0)
	var swing := sin(anim_t) * (0.5 if horizontal > 0.2 else 0.0)
	_rot("leg_fl", swing)
	_rot("leg_br", swing)
	_rot("leg_fr", -swing)
	_rot("leg_bl", -swing)
	var head: Node3D = parts.get("head")
	if head != null:
		head.rotation.z = -0.35 - 0.25 * sin(anim_t * 0.3) if horizontal < 0.2 else -0.1
	var tail: Node3D = parts.get("tail")
	if tail != null:
		tail.rotation.y = sin(anim_t * 1.7) * 0.4
	var body: Node3D = parts.get("body")
	if body != null and horizontal < 0.2:
		body.position.y = body.position.y + sin(anim_t * 0.5) * 0.0005


func _rot(part: String, angle: float) -> void:
	var n: Node3D = parts.get(part)
	if n != null:
		n.rotation.z = angle
