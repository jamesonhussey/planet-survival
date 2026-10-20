class_name StructureGen
extends RefCounted
## Deterministic block structures stamped into terrain at generation time
## (farmhouses, barns). build() returns {Vector3i: block id} in world
## coordinates for a structure whose floor sits at origin.y; id 0 entries
## clear terrain. Everything here is ordinary blocks, so the hazards read
## the same properties the player's own builds have.


static func build(kind: String, origin: Vector3i, rng: RandomNumberGenerator, ids: Dictionary, heights: Callable) -> Dictionary:
	match kind:
		"farmhouse":
			return _farmhouse(origin, rng, ids, heights)
		"barn":
			return _barn(origin, rng, ids, heights)
		"hilltop_camp":
			return _hilltop_camp(origin, rng, ids, heights)
		"stilt_village":
			return _stilt_village(origin, rng, ids, heights)
	return {}


## NPC spawn/home points for a structure: [{"pos": Vector3i, "home": Vector3i}]
## in world coordinates. The farmhouse cellar, the camp huts, the stilt huts.
static func npc_points(kind: String, origin: Vector3i) -> Array:
	var o := origin
	match kind:
		"farmhouse":
			var cx := o.x + 8 - 4
			var cz := o.z + 7 - 4
			return [{"pos": Vector3i(cx + 1, o.y - 3, cz + 1), "home": Vector3i(cx + 1, o.y - 3, cz + 1)}]
		"hilltop_camp":
			var out: Array = []
			for h in _camp_huts(o):
				out.append({"pos": Vector3i(h.x + 1, o.y + 1, h.z + 1), "home": Vector3i(h.x + 1, o.y + 1, h.z + 1)})
			return out
		"stilt_village":
			var out2: Array = []
			for h in _stilt_huts(o):
				out2.append({"pos": Vector3i(h.x + 1, o.y + 7, h.z + 1), "home": Vector3i(h.x + 1, o.y + 7, h.z + 1)})
			return out2
	return []


## Footprint (x,z size) so the generator can reserve space and the prop
## spawner can keep clear.
static func footprint(kind: String) -> Vector2i:
	match kind:
		"farmhouse": return Vector2i(8, 7)
		"barn": return Vector2i(12, 9)
		"hilltop_camp": return Vector2i(16, 16)
		"stilt_village": return Vector2i(20, 14)
	return Vector2i(1, 1)


static func _camp_huts(o: Vector3i) -> Array[Vector3i]:
	return [Vector3i(o.x + 1, o.y, o.z + 1), Vector3i(o.x + 11, o.y, o.z + 1), Vector3i(o.x + 1, o.y, o.z + 11), Vector3i(o.x + 11, o.y, o.z + 11)]


static func _stilt_huts(o: Vector3i) -> Array[Vector3i]:
	return [Vector3i(o.x + 1, o.y, o.z + 1), Vector3i(o.x + 13, o.y, o.z + 1), Vector3i(o.x + 7, o.y, o.z + 8)]


static func _id(ids: Dictionary, name: String, fallback: int = 3) -> int:
	return int(ids.get(name, fallback))


## Level the ground: fill below the floor with dirt, clear above up to h.
static func _prepare_ground(out: Dictionary, origin: Vector3i, w: int, d: int, h: int, ids: Dictionary, heights: Callable) -> void:
	var dirt := _id(ids, "dirt", 1)
	for z in range(-1, d + 1):
		for x in range(-1, w + 1):
			var wx := origin.x + x
			var wz := origin.z + z
			var th: int = heights.call(wx, wz)
			for y in range(th + 1, origin.y + 1):
				out[Vector3i(wx, y, wz)] = dirt   # raise
			for y in range(origin.y + 1, maxi(th, origin.y) + 1 + h):
				out[Vector3i(wx, y, wz)] = 0      # cut


static func _farmhouse(o: Vector3i, rng: RandomNumberGenerator, ids: Dictionary, heights: Callable) -> Dictionary:
	var out: Dictionary = {}
	var stone := _id(ids, "stone", 3)
	var planks := _id(ids, "planks", 6)
	var glass := _id(ids, "glass", 7)
	var thatch := _id(ids, "thatch", 9)
	var w := 8
	var d := 7
	var wall_h := 3
	_prepare_ground(out, o, w, d, wall_h + 3, ids, heights)
	# Floor
	for z in d:
		for x in w:
			out[Vector3i(o.x + x, o.y, o.z + z)] = planks
	# Walls
	for z in d:
		for x in w:
			var edge := x == 0 or x == w - 1 or z == 0 or z == d - 1
			if not edge:
				continue
			for y in range(1, wall_h + 1):
				out[Vector3i(o.x + x, o.y + y, o.z + z)] = stone
	# Door (front, z = 0) and windows
	var door_x := 2 + rng.randi_range(0, 2)
	out[Vector3i(o.x + door_x, o.y + 1, o.z)] = 0
	out[Vector3i(o.x + door_x, o.y + 2, o.z)] = 0
	for wx in [1, w - 2]:
		out[Vector3i(o.x + wx, o.y + 2, o.z + d - 1)] = glass
	out[Vector3i(o.x, o.y + 2, o.z + 3)] = glass
	out[Vector3i(o.x + w - 1, o.y + 2, o.z + 3)] = glass
	# Roof: pitched along x. Thatch or planks: both burn, which is the point.
	var roof_mat := thatch if rng.randf() < 0.6 else planks
	var half := int(ceil(w / 2.0))
	# A closed stepped wedge: every column is filled from the eave to its ridge
	# height, so no light leaks between steps.
	for z in range(-1, d + 1):
		for x in range(-1, w + 1):
			var dist := mini(x + 1, w - x)
			var ry := o.y + wall_h + 1 + clampi(dist / 2, 0, 2)
			for y in range(o.y + wall_h + 1, ry + 1):
				out[Vector3i(o.x + x, y, o.z + z)] = roof_mat
	# Cellar: 3x3 pit under the back of the house, stone-lined, reached by a
	# stair hole. Sun from above cannot reach the pit floor.
	var cx := o.x + w - 4
	var cz := o.z + d - 4
	for z in range(-1, 4):
		for x in range(-1, 4):
			for y in range(-4, 0):
				var wall := x == -1 or x == 3 or z == -1 or z == 3 or y == -4
				out[Vector3i(cx + x, o.y + y, cz + z)] = stone if wall else 0
	# Stair: opening in the floor plus a diagonal of removed blocks.
	out[Vector3i(cx, o.y, cz)] = 0
	out[Vector3i(cx, o.y - 1, cz)] = 0
	out[Vector3i(cx + 1, o.y - 2, cz)] = 0
	out[Vector3i(cx + 1, o.y - 1, cz)] = planks  # a step
	return out


static func _barn(o: Vector3i, rng: RandomNumberGenerator, ids: Dictionary, heights: Callable) -> Dictionary:
	var out: Dictionary = {}
	var stone := _id(ids, "stone", 3)
	var scorched := _id(ids, "scorched_stone", stone)
	var planks := _id(ids, "planks", 6)
	var w := 12
	var d := 9
	var wall_h := 4
	_prepare_ground(out, o, w, d, wall_h + 3, ids, heights)
	for z in d:
		for x in w:
			out[Vector3i(o.x + x, o.y, o.z + z)] = _id(ids, "dirt", 1)
			var edge := x == 0 or x == w - 1 or z == 0 or z == d - 1
			if edge:
				for y in range(1, wall_h + 1):
					out[Vector3i(o.x + x, o.y + y, o.z + z)] = stone
	# Big door on the front, two wide, three tall.
	var dx := 4 + rng.randi_range(0, 2)
	for x in [dx, dx + 1]:
		for y in range(1, 4):
			out[Vector3i(o.x + x, o.y + y, o.z)] = 0
	# Flat plank roof with a stone rim. Planks burn; the rim does not.
	for z in range(-1, d + 1):
		for x in range(-1, w + 1):
			var rim := x == -1 or x == w or z == -1 or z == d
			out[Vector3i(o.x + x, o.y + wall_h + 1, o.z + z)] = stone if rim else planks
	# The shadows on the wall: people who did not make it inside, burned into
	# the stone of the west face (outside, x = -1 would be air; we recolour the
	# wall blocks at x = 0 so the silhouette shows from outside).
	var figures := rng.randi_range(2, 4)
	var used: Array[int] = []
	for i in figures:
		var fz := rng.randi_range(1, d - 2)
		if used.has(fz):
			continue
		used.append(fz)
		# legs, body, head; some reach up (arms as a block beside the head)
		for y in range(1, 4):
			out[Vector3i(o.x, o.y + y, o.z + fz)] = scorched
		if rng.randf() < 0.5 and fz + 1 < d - 1:
			out[Vector3i(o.x, o.y + 3, o.z + fz + 1)] = scorched
	return out


## Planet 04: four small clay huts around a fire on a levelled hilltop. Clay
## and brick are airtight: the camp survives an eruption if the doors are
## shut (they are open by design; the hint is the altitude).
static func _hilltop_camp(o: Vector3i, rng: RandomNumberGenerator, ids: Dictionary, heights: Callable) -> Dictionary:
	var out: Dictionary = {}
	var clay := _id(ids, "clay", 5)
	var brick := _id(ids, "brick", 8)
	var planks := _id(ids, "planks", 6)
	var fire := _id(ids, "campfire", 15)
	var dirt := _id(ids, "dirt", 1)
	_prepare_ground(out, o, 16, 16, 6, ids, heights)
	for z in 16:
		for x in 16:
			out[Vector3i(o.x + x, o.y, o.z + z)] = dirt
	for h in _camp_huts(o):
		var wall := brick if rng.randf() < 0.5 else clay
		for z in 4:
			for x in 4:
				for y in range(1, 4):
					var edge := x == 0 or x == 3 or z == 0 or z == 3
					if edge:
						out[Vector3i(h.x + x, h.y + y, h.z + z)] = wall
				out[Vector3i(h.x + x, h.y + 4, h.z + z)] = planks
		# door facing the fire (toward the centre)
		var dx := 3 if h.x < o.x + 8 else 0
		var dz := 1 + rng.randi_range(0, 1)
		out[Vector3i(h.x + dx, h.y + 1, h.z + dz)] = 0
		out[Vector3i(h.x + dx, h.y + 2, h.z + dz)] = 0
	out[Vector3i(o.x + 8, o.y + 1, o.z + 8)] = fire
	for p in [Vector3i(o.x + 7, o.y + 1, o.z + 7), Vector3i(o.x + 9, o.y + 1, o.z + 9), Vector3i(o.x + 7, o.y + 1, o.z + 9), Vector3i(o.x + 9, o.y + 1, o.z + 7)]:
		out[p] = _id(ids, "cobble", 3) if ids.has("cobble") else _id(ids, "stone", 3)
	return out


## Planet 02: three plank huts on log stilts six blocks up, linked by
## walkways. Planks leak water and roaches: the hint is the height and the
## brick corner room on the largest hut.
static func _stilt_village(o: Vector3i, rng: RandomNumberGenerator, ids: Dictionary, heights: Callable) -> Dictionary:
	var out: Dictionary = {}
	var planks := _id(ids, "planks", 6)
	var log := _id(ids, "log", 11)
	var brick := _id(ids, "brick", 8)
	var thatch := _id(ids, "thatch", 9)
	var deck := o.y + 6
	var huts := _stilt_huts(o)
	for i in huts.size():
		var h := huts[i]
		var w := 6 if i == 2 else 5
		# stilts
		for p in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, w - 1), Vector2i(w - 1, w - 1)]:
			var th: int = heights.call(h.x + p.x, h.z + p.y)
			for y in range(th + 1, deck + 1):
				out[Vector3i(h.x + p.x, y, h.z + p.y)] = log
		for z in w:
			for x in w:
				out[Vector3i(h.x + x, deck, h.z + z)] = planks
				var edge := x == 0 or x == w - 1 or z == 0 or z == w - 1
				if edge:
					for y in range(1, 3):
						out[Vector3i(h.x + x, deck + y, h.z + z)] = brick if (i == 2 and x < 3 and z < 3) else planks
				out[Vector3i(h.x + x, deck + 3, h.z + z)] = thatch
		out[Vector3i(h.x + 2, deck + 1, h.z)] = 0
		out[Vector3i(h.x + 2, deck + 2, h.z)] = 0
	# walkways between hut 0 -> 2 and 1 -> 2
	for x in range(huts[0].x + 5, huts[2].x + 1):
		out[Vector3i(x, deck, huts[0].z + 2)] = planks
	for z in range(huts[0].z + 2, huts[2].z + 1):
		out[Vector3i(huts[2].x + 2, deck, z)] = planks
	for x in range(huts[2].x + 6, huts[1].x + 1):
		out[Vector3i(x, deck, huts[1].z + 2)] = planks
	for z in range(huts[1].z + 2, huts[2].z + 1):
		out[Vector3i(huts[2].x + 4, deck, z)] = planks
	# ladder: a column of planks steps up to hut 0
	for y in range(o.y + 1, deck):
		out[Vector3i(huts[0].x - 1, y, huts[0].z + 2 + (y % 2))] = planks
	return out
