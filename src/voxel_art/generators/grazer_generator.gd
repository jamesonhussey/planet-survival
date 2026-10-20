class_name GrazerGenerator
extends RefCounted
## A small four-legged grazing creature at 1/8-block voxels. Parts: body,
## head, four legs (pivoted at the hip so they swing), a tail. Params:
##   size: [min, max] scale multiplier   ramp: fur palette ramp

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var s_range: Array = params.get("size", [0.8, 1.3])
	var k := rng.randf_range(float(s_range[0]), float(s_range[1]))
	var fur := VoxelArt.ramp(ctx, str(params.get("ramp", "grazer")), [Color("#3a3028"), Color("#6a5a48"), Color("#9a8a70"), Color("#c8b89a")])
	var body_len := int(10 * k)
	var body_h := int(5 * k) + 1
	var body_w := int(5 * k) + 1
	var leg_h := int(5 * k) + 1

	var body := VoxelModel.new(Vector3i(body_len + 2, body_h + 2, body_w + 2), SCALE)
	var f0 := body.add_ramp(fur)
	var spots := body.add_color(fur[0].lightened(0.1))
	body.pivot = Vector3((body_len + 2) * 0.5, 0, (body_w + 2) * 0.5)
	var spot_seed := rng.randi()
	var pick := func(x: int, y: int, z: int) -> int:
		var n := _hash3(x, y, z, spot_seed)
		if y < 2:
			return f0 + 1
		if n < 0.12:
			return spots
		return f0 + 2 if n < 0.7 else f0 + 3
	body.fill_ellipsoid(Vector3((body_len + 2) * 0.5, body_h * 0.5 + 1, (body_w + 2) * 0.5), Vector3(body_len * 0.5, body_h * 0.5, body_w * 0.5), f0 + 2, pick)

	var head := VoxelModel.new(Vector3i(6, 6, 5), SCALE)
	var h0 := head.add_ramp(fur)
	var eye := head.add_color(Color(0.05, 0.05, 0.05))
	head.pivot = Vector3(0, 3, 2.5)
	head.fill_box(Vector3i(0, 1, 1), Vector3i(4, 4, 3), h0 + 2)
	head.fill_box(Vector3i(4, 1, 1), Vector3i(5, 2, 3), h0 + 1)  # snout
	head.set_voxel(3, 3, 0, eye)
	head.set_voxel(3, 3, 4, eye)
	head.fill_box(Vector3i(1, 5, 0), Vector3i(1, 5, 0), h0 + 1)  # ears
	head.fill_box(Vector3i(1, 5, 4), Vector3i(1, 5, 4), h0 + 1)

	var rig := PartRig.new()
	var body_y := leg_h * SCALE
	rig.add_part("body", body, "", Vector3(0, body_y, 0))
	rig.add_part("head", head, "body", Vector3((body_len * 0.5) * SCALE, (body_h + 1) * SCALE, 0))
	var leg_x := (body_len * 0.5 - 1.5) * SCALE
	var leg_z := (body_w * 0.5 - 0.5) * SCALE
	var i := 0
	for off in [Vector3(leg_x, 0, leg_z), Vector3(leg_x, 0, -leg_z), Vector3(-leg_x, 0, leg_z), Vector3(-leg_x, 0, -leg_z)]:
		var leg := VoxelModel.new(Vector3i(2, leg_h + 1, 2), SCALE)
		var l0 := leg.add_ramp(fur)
		leg.pivot = Vector3(1, leg_h + 1, 1)   # hip at top
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(1, leg_h, 1), l0 + 1)
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(1, 0, 1), l0)   # hoof
		rig.add_part(["leg_fl", "leg_fr", "leg_bl", "leg_br"][i], leg, "body", off + Vector3(0, 1 * SCALE, 0))
		i += 1
	var tail := VoxelModel.new(Vector3i(4, 2, 2), SCALE)
	var t0 := tail.add_ramp(fur)
	tail.pivot = Vector3(4, 1, 1)
	tail.fill_box(Vector3i(0, 0, 0), Vector3i(3, 1, 1), t0 + 1)
	rig.add_part("tail", tail, "body", Vector3(-(body_len * 0.5) * SCALE, (body_h * 0.6) * SCALE, 0))
	rig.height = (leg_h + body_h + 2) * SCALE
	rig.collision_box = AABB(Vector3(-body_len * 0.5 * SCALE, 0, -body_w * 0.5 * SCALE), Vector3(body_len * SCALE, rig.height, body_w * SCALE))
	return rig


static func _hash3(x: int, y: int, z: int, seed: int) -> float:
	var h := x * 374761393 + y * 668265263 + z * 2147483647 + seed * 97
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
