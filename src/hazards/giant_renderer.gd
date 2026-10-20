class_name GiantRenderer
extends Node3D
## Shows the giant where the hazard says it is: a huge micro-voxel figure
## (voxel = half a block) walking the path, legs swinging with the step phase.
## Hidden while the hazard is idle.

var hazard: GiantHazard
var parts: Dictionary = {}
var body: Node3D
var _smooth_pos: Vector3 = Vector3.ZERO
var _have_pos: bool = false


func setup(giant: GiantHazard, material: Material, palette_id: String, seed: int) -> void:
	hazard = giant
	var rig := VoxelArt.rig("giant", {}, seed, palette_id)
	body = rig.instantiate(material)
	add_child(body)
	parts = PartRig.part_nodes(body)
	visible = false


func _process(delta: float) -> void:
	if hazard == null or hazard.is_idle():
		visible = false
		_have_pos = false
		return
	visible = true
	var target := hazard.giant_position()
	if not _have_pos:
		_smooth_pos = target
		_have_pos = true
	# Smooth the ground height (the body should not pop when the path crosses a bump).
	_smooth_pos.x = target.x
	_smooth_pos.z = target.z
	_smooth_pos.y = lerpf(_smooth_pos.y, target.y, minf(1.0, delta * 3.0))
	global_position = _smooth_pos
	var h := hazard.heading()
	rotation.y = atan2(-h.x, -h.y)
	# Legs: one step per step_interval, phase 0..1; feet alternate.
	var ph := hazard.step_phase()
	var swing := sin(ph * PI) * 0.55
	var l := swing if hazard.left_foot else -swing
	_rot_x("leg_l", l)
	_rot_x("leg_r", -l)
	_rot_x("arm_l", -l * 0.5)
	_rot_x("arm_r", l * 0.5)
	var torso: Node3D = parts.get("torso")
	if torso != null:
		torso.position.y = torso.position.y * 0.0 + 12 * 0.5 + absf(sin(ph * PI)) * 0.4
		torso.rotation.z = l * 0.08


func _rot_x(part: String, angle: float) -> void:
	var n: Node3D = parts.get(part)
	if n != null:
		n.rotation.x = angle
