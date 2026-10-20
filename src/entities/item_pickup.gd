class_name ItemPickup
extends Node3D
## An item lying in the world: a small spinning micro-voxel cube coloured by
## category. Picked up with E when nearby or from the inventory's NEARBY list.

var item: ItemInstance
var _mesh: MeshInstance3D
var _t: float = 0.0
var _vy: float = 0.0
var world: WorldData


func setup(it: ItemInstance, material: Material, world_data: WorldData) -> void:
	item = it
	world = world_data
	var m := VoxelModel.new(Vector3i(4, 4, 4), 0.08)
	var base: Color = GridView.CATEGORY_COLORS.get(it.category(), Color(0.5, 0.5, 0.5))
	var c0 := m.add_color(base)
	var c1 := m.add_color(base.lightened(0.25))
	var c2 := m.add_color(base.darkened(0.3))
	m.pivot = Vector3(2, 0, 2)
	for y in 4:
		for z in 4:
			for x in 4:
				var edge := (x == 0 or x == 3) and (z == 0 or z == 3)
				m.set_voxel(x, y, z, c2 if edge else (c1 if y == 3 else c0))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = VoxelMesher.build_mesh(m)
	_mesh.material_override = material
	add_child(_mesh)


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y = _t * 1.5
	_mesh.position.y = 0.15 + sin(_t * 2.0) * 0.05
	# Settle onto the ground (simple voxel gravity).
	if world != null:
		var below := Vector3i(Vector3(global_position.x, global_position.y - 0.05, global_position.z).floor())
		if not world.is_solid(below) and global_position.y > 0.0:
			_vy -= 15.0 * delta
			global_position.y += _vy * delta
		else:
			_vy = 0.0
			global_position.y = float(below.y + 1)
