class_name PartRig
extends RefCounted
## A model made of named rigid parts (body, head, legs, lantern cage...).
## Each part is its own VoxelModel with a pivot, so animation is just
## rotating/translating part nodes. instantiate() builds the Node3D tree.


class Part:
	var name: String
	var model: VoxelModel
	var parent: String = ""           # "" = root
	var offset: Vector3 = Vector3.ZERO  # metres, in parent's space (the part's pivot position)
	var emissive: bool = false
	var mesh: ArrayMesh = null         # filled by bake()


var parts: Array[Part] = []
var id: String = ""                  # cache key (generator + params + seed)
var collision_box: AABB = AABB()     # optional static collision (metres)
var height: float = 0.0              # approximate total height in metres


func add_part(name: String, model: VoxelModel, parent: String = "", offset: Vector3 = Vector3.ZERO, emissive: bool = false) -> Part:
	var p := Part.new()
	p.name = name
	p.model = model
	p.parent = parent
	p.offset = offset
	p.emissive = emissive
	parts.append(p)
	return p


func get_part(name: String) -> Part:
	for p in parts:
		if p.name == name:
			return p
	return null


## Mesh every part once (cached on the Part).
func bake() -> void:
	for p in parts:
		if p.mesh == null:
			p.mesh = VoxelMesher.build_mesh(p.model)


## Builds the node tree. Returns the root Node3D; part nodes are named after
## parts and the root has metadata "parts" (name -> Node3D) for animators.
func instantiate(material: Material, emissive_material: Material = null) -> Node3D:
	bake()
	var root := Node3D.new()
	root.name = "Rig"
	var nodes: Dictionary = {}
	# Parents first: simple repeated pass (rigs are tiny).
	var pending := parts.duplicate()
	var guard := 0
	while not pending.is_empty() and guard < 16:
		guard += 1
		for p in pending.duplicate():
			var parent_node: Node3D = root if p.parent == "" else nodes.get(p.parent)
			if parent_node == null:
				continue
			var n := Node3D.new()
			n.name = p.name
			n.position = p.offset
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = p.mesh
			mi.material_override = emissive_material if (p.emissive and emissive_material != null) else material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			n.add_child(mi)
			parent_node.add_child(n)
			nodes[p.name] = n
			pending.erase(p)
	root.set_meta("parts", nodes)
	return root


static func part_nodes(rig_root: Node3D) -> Dictionary:
	return rig_root.get_meta("parts", {})
