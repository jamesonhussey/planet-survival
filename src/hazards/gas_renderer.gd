class_name GasRenderer
extends Node3D
## Makes the invisible visible: draws every gas cell as a translucent, unlit
## haze cube whose alpha follows concentration. With the dither pass this
## reads as a shimmering fog layer hugging the ground.

var sim: GasSim
var multimesh: MultiMesh
var instance: MultiMeshInstance3D
var refresh_interval: float = 0.12
var max_instances: int = 24000
var haze_color: Color = Color(0.78, 0.86, 0.62)
var _accum: float = 0.0


func setup(gas_sim: GasSim, color: Color) -> void:
	sim = gas_sim
	haze_color = color
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	box.material = mat
	multimesh.mesh = box
	multimesh.instance_count = max_instances
	multimesh.visible_instance_count = 0
	instance = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-2048, -64, -2048), Vector3(4096, 512, 4096))
	add_child(instance)


func _process(delta: float) -> void:
	if sim == null:
		return
	_accum += delta
	if _accum < refresh_interval:
		return
	_accum = 0.0
	var i := 0
	var t := Transform3D()
	for p in sim.cells:
		if i >= max_instances:
			break
		var c: float = sim.cells[p]
		if c < 0.03:
			continue
		t.origin = Vector3(p) + Vector3(0.5, 0.5, 0.5)
		multimesh.set_instance_transform(i, t)
		var a := clampf(c * 0.75, 0.04, 0.7)
		multimesh.set_instance_color(i, Color(haze_color.r, haze_color.g, haze_color.b, a))
		i += 1
	multimesh.visible_instance_count = i
