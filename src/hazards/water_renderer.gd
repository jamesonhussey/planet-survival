class_name WaterRenderer
extends Node3D
## Draws the flood: one translucent quad per water-surface cell (wet cells
## with nothing wet above). Static sea blocks are part of the terrain mesh;
## this covers the rising part and the tide going out.

var sim: FluidSim
var multimesh: MultiMesh
var instance: MultiMeshInstance3D
var refresh_interval: float = 0.25
var max_instances: int = 40000
var color: Color = Color(0.25, 0.55, 0.7, 0.55)
var _accum: float = 0.0


func setup(fluid: FluidSim, water_color: Color) -> void:
	sim = fluid
	color = water_color
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	multimesh.mesh = quad
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
	var frac := clampf(sim.level - floor(sim.level), 0.05, 0.98)
	var wobble := sin(Time.get_ticks_msec() * 0.002) * 0.03
	for p in sim.surface_cells(max_instances):
		t.origin = Vector3(p) + Vector3(0.5, frac + wobble, 0.5)
		multimesh.set_instance_transform(i, t)
		multimesh.set_instance_color(i, color)
		i += 1
	multimesh.visible_instance_count = i
