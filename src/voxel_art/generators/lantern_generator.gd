class_name LanternGenerator
extends RefCounted
## A post lantern at 1/16-block voxels: post, arm, cage, glowing core
## (emissive part). Params: ramp (palette ramp: dark metal -> bright glow),
## height: [min,max] blocks, rust: 0..1 (more rust = darker speckles).

const SCALE := 1.0 / 16.0


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var h_range: Array = params.get("height", [2.2, 3.0])
	var rust := float(params.get("rust", 0.35))
	var vpb := 16
	var H := int(rng.randf_range(float(h_range[0]), float(h_range[1])) * vpb)
	var ramp := VoxelArt.ramp(ctx, str(params.get("ramp", "lantern")), [Color("#3a2a1a"), Color("#7a5a2a"), Color("#d8a040"), Color("#ffe08a")])
	var W := 14
	var post := VoxelModel.new(Vector3i(W, H + 4, W), SCALE)
	var c0 := post.add_ramp(ramp)
	var rust_c := post.add_color(ramp[0].darkened(0.4))
	var cx := W / 2.0
	post.pivot = Vector3(cx, 0, cx)
	# Post with a foot
	post.fill_column(cx, cx, 0, 2, 2.0, c0)
	for y in range(3, H):
		var ci := c0 if rng.randf() > rust * 0.25 else rust_c
		post.fill_column(cx, cx, y, y, 1.0, ci)
	# Arm out along +x
	for x in range(int(cx), W - 1):
		post.fill_box(Vector3i(x, H - 1, int(cx) - 1), Vector3i(x, H, int(cx)), c0)
	# Hook
	post.fill_box(Vector3i(W - 2, H - 4, int(cx) - 1), Vector3i(W - 1, H, int(cx)), c0)

	# Cage hanging from the hook (separate part so it can swing).
	var cage := VoxelModel.new(Vector3i(8, 10, 8), SCALE)
	var k0 := cage.add_ramp(ramp)
	cage.pivot = Vector3(4, 10, 4)
	cage.fill_box(Vector3i(1, 8, 1), Vector3i(6, 9, 6), k0)        # roof
	cage.fill_box(Vector3i(1, 0, 1), Vector3i(6, 0, 6), k0)        # floor
	for p in [Vector2i(1, 1), Vector2i(6, 1), Vector2i(1, 6), Vector2i(6, 6)]:
		cage.fill_box(Vector3i(p.x, 1, p.y), Vector3i(p.x, 7, p.y), k0 + 1)  # bars
	var core := VoxelModel.new(Vector3i(8, 10, 8), SCALE)
	var g0 := core.add_ramp(ramp)
	core.pivot = Vector3(4, 10, 4)
	core.fill_box(Vector3i(3, 2, 3), Vector3i(4, 6, 4), g0 + 3)
	core.fill_box(Vector3i(2, 3, 2), Vector3i(5, 5, 5), g0 + 2)
	core.fill_box(Vector3i(3, 3, 3), Vector3i(4, 5, 4), g0 + 3)

	var rig := PartRig.new()
	rig.add_part("post", post)
	var hook_pos := Vector3((W - 1.5 - cx) * SCALE, (H - 4) * SCALE, 0)
	rig.add_part("cage", cage, "post", hook_pos)
	rig.add_part("core", core, "cage", Vector3.ZERO, true)
	rig.height = H * SCALE
	rig.collision_box = AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, H * SCALE, 0.2))
	return rig
