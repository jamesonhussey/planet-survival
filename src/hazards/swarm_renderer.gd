class_name SwarmRenderer
extends Node3D
## Roach swarm as a MultiMesh of one generated roach mesh, oriented along
## each agent's movement with a scuttle wobble.

var multimesh: MultiMesh
var instance: MultiMeshInstance3D
var max_instances: int = 400
var _last: PackedVector3Array = PackedVector3Array()


func setup(material: Material, palette_id: String) -> void:
	var rig := VoxelArt.rig("roach", {}, 4242, palette_id)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	var mesh := rig.parts[0].mesh
	mesh.surface_set_material(0, material)
	multimesh.mesh = mesh
	multimesh.instance_count = max_instances
	multimesh.visible_instance_count = 0
	instance = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.custom_aabb = AABB(Vector3(-2048, -64, -2048), Vector3(4096, 512, 4096))
	add_child(instance)


func update(positions: PackedVector3Array) -> void:
	var n := mini(positions.size(), max_instances)
	var t := Time.get_ticks_msec() * 0.001
	for i in n:
		var p := positions[i]
		var dir := Vector3(1, 0, 0)
		if i < _last.size():
			var d := p - _last[i]
			d.y = 0.0
			if d.length_squared() > 1e-5:
				dir = d.normalized()
		var basis := Basis.looking_at(dir, Vector3.UP)
		var wobble := sin(t * 25.0 + float(i)) * 0.08
		var xf := Transform3D(basis.rotated(Vector3.UP, wobble + PI * 0.5), p)
		multimesh.set_instance_transform(i, xf)
	multimesh.visible_instance_count = n
	_last = positions
