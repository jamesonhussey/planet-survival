class_name RemotePlayer
extends Node3D
## Another peer's avatar: a humanoid part rig moved by replicated state
## (position, yaw, pitch, moving flag) with simple interpolation and a walk
## cycle. Ghosts render translucent and float.

var peer_id: int = 0
var display_name: String = ""
var rig_root: Node3D
var parts: Dictionary = {}
var target_pos: Vector3
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var moving: bool = false
var ghost: bool = false
var anim_t: float = 0.0
var name_label: Label3D
var _ghost_material: Material = null
var _material: Material = null


func setup(id: int, pname: String, material: Material, seed: int) -> void:
	peer_id = id
	display_name = pname
	_material = material
	var rig := VoxelArt.rig("humanoid", {"cloth": ["#3a5a6a", "#6a3a3a", "#3a6a44", "#6a5a2a"][seed % 4]}, 500 + seed, "04")
	rig_root = rig.instantiate(material)
	add_child(rig_root)
	parts = PartRig.part_nodes(rig_root)
	name_label = Label3D.new()
	name_label.text = pname
	name_label.font = PixelFont.get_font(1)
	name_label.font_size = 9
	name_label.pixel_size = 0.02
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.outline_size = 0
	name_label.position = Vector3(0, rig.height + 0.35, 0)
	add_child(name_label)
	target_pos = global_position


func apply_state(pos: Vector3, yaw: float, pitch: float, is_moving: bool, is_ghost: bool) -> void:
	target_pos = pos
	target_yaw = yaw
	target_pitch = pitch
	moving = is_moving
	if is_ghost != ghost:
		ghost = is_ghost
		_apply_ghost_look()


func _apply_ghost_look() -> void:
	for n in parts.values():
		var mi := (n as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mi == null:
			continue
		if ghost:
			if _ghost_material == null:
				var m := StandardMaterial3D.new()
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(0.7, 0.9, 1.0, 0.35)
				m.vertex_color_use_as_albedo = true
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_ghost_material = m
			mi.material_override = _ghost_material
		else:
			mi.material_override = _material
	name_label.text = display_name + ("  (ghost)" if ghost else "")


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_pos, minf(1.0, delta * 12.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 12.0))
	var head: Node3D = parts.get("head")
	if head != null:
		head.rotation.x = lerp(head.rotation.x, -target_pitch * 0.6, minf(1.0, delta * 10.0))
	anim_t += delta * (8.0 if moving else 2.0)
	var swing := sin(anim_t) * (0.6 if moving else 0.0)
	_rot("leg_l", swing)
	_rot("leg_r", -swing)
	_rot("arm_l", -swing * 0.7)
	_rot("arm_r", swing * 0.7)
	if ghost and rig_root != null:
		rig_root.position.y = 0.3 + sin(anim_t * 0.5) * 0.1


func _rot(part: String, angle: float) -> void:
	var n: Node3D = parts.get(part)
	if n != null:
		n.rotation.x = angle
