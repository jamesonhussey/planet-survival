class_name PalmGenerator
extends RefCounted
## A leaning palm at 1/4-block voxels: curved trunk with ring texture,
## radial drooping fronds, a cluster of coconuts. Params: height [min,max]
## blocks, ramp (frond colours), bark.

const SCALE := 0.25


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var h_range: Array = params.get("height", [6, 10])
	var height_blocks := rng.randf_range(float(h_range[0]), float(h_range[1]))
	var vpb := 4
	var H := int(height_blocks * vpb)
	var R := 10
	var W := R * 2 + 8
	var m := VoxelModel.new(Vector3i(W, H + 8, W), SCALE)
	var leaf := VoxelArt.ramp(ctx, str(params.get("ramp", "leaf")), [Color("#2d5a2a"), Color("#4a8a3a"), Color("#78b05a"), Color("#a8d47e")])
	var bark := VoxelArt.ramp(ctx, str(params.get("bark", "bark")), [Color("#6a5a3a"), Color("#8a7a4a"), Color("#a89a6a"), Color("#c8b88a")])
	var l0 := m.add_ramp(leaf)
	var b0 := m.add_ramp(bark)
	var nut := m.add_color(Color("#5a3a1e"))
	var cx := W * 0.5
	var cz := W * 0.5
	m.pivot = Vector3(cx, 0, cz)
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.04, 0.12)
	var top := Vector3(cx, H, cz)
	for y in H + 1:
		var t := float(y) / float(H)
		var px := cx + lean.x * y * y * 0.12
		var pz := cz + lean.y * y * y * 0.12
		m.fill_column(px, pz, y, y, lerpf(0.55 * vpb, 0.3 * vpb, t), b0 + (0 if y % 3 == 0 else 1))
		if y == H:
			top = Vector3(px, y, pz)
	# Fronds: 6-8 arcs radiating from the top, drooping.
	var fronds := rng.randi_range(6, 8)
	for i in fronds:
		var a := TAU * float(i) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var len := rng.randf_range(7.0, 10.0)
		for s in int(len):
			var f := float(s) / len
			var px := top.x + cos(a) * s
			var pz := top.z + sin(a) * s
			var py := top.y + 2.0 - f * f * 6.0
			var ci := l0 + (1 if f < 0.5 else 2)
			m.set_voxel(int(px), int(py), int(pz), ci)
			if s > 1:
				# Leaflets left/right of the midrib.
				var side := Vector2(-sin(a), cos(a))
				m.set_voxel(int(px + side.x), int(py - 0.5), int(pz + side.y), l0 + 2)
				m.set_voxel(int(px - side.x), int(py - 0.5), int(pz - side.y), l0 + 3 if s % 2 == 0 else l0 + 2)
	# Coconuts
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		m.set_voxel(int(top.x + cos(a) * 1.5), int(top.y) - 1, int(top.z + sin(a) * 1.5), nut)
	var rig := PartRig.new()
	rig.add_part("palm", m)
	rig.height = (H + 2) * SCALE
	rig.collision_box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, H * SCALE, 0.6))
	return rig
