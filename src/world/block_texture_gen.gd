class_name BlockTextureGen
extends RefCounted
## Generates the terrain texture atlas in code from each material's
## `texture` recipe (style + base colour), 16x16 px tiles, no filtering.
## Each material gets up to three tiles: top, side, bottom.

const TILE := 16
const ATLAS_COLS := 16

var texture: ImageTexture
var image: Image
var tile_of: PackedInt32Array = []   # index = material_id * 3 + face (0 top, 1 side, 2 bottom)
var tile_count: int = 0
var atlas_rows: int = 1


func build(materials: Array[MaterialProps], seed: int = 1) -> BlockTextureGen:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tiles: Array[Image] = []
	tile_of.resize(materials.size() * 3)
	tile_of.fill(0)
	# tile 0 is a magenta "missing" tile
	tiles.append(_flat(Color.MAGENTA))
	for m in materials:
		if m.texture.is_empty():
			continue
		var style := str(m.texture.get("style", "noise"))
		var base := Color.html(str(m.texture.get("base", "#ff00ff")))
		var variance := float(m.texture.get("variance", 0.1))
		rng.seed = seed + m.id * 1013
		match style:
			"grass_top":
				var top := Color.html(str(m.texture.get("top", "#5f9a4a")))
				tiles.append(_noise(top, variance, rng))
				tile_of[m.id * 3 + 0] = tiles.size() - 1
				tiles.append(_grass_side(base, top, variance, rng))
				tile_of[m.id * 3 + 1] = tiles.size() - 1
				tiles.append(_noise(base, variance, rng))
				tile_of[m.id * 3 + 2] = tiles.size() - 1
			"planks":
				tiles.append(_planks(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"bricks":
				var mortar := Color.html(str(m.texture.get("mortar", "#c9b9a6")))
				tiles.append(_bricks(base, mortar, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"speckle":
				tiles.append(_speckle(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"glass":
				tiles.append(_glass(base, rng))
				_all_faces(m.id, tiles.size() - 1)
			"water":
				tiles.append(_water(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"leaves":
				tiles.append(_leaves(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"cracks":
				tiles.append(_cracks(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
			"fire":
				tiles.append(_fire(base, rng))
				tile_of[m.id * 3 + 0] = tiles.size() - 1
				tiles.append(_speckle(Color("#4a4440"), 0.2, rng))
				tile_of[m.id * 3 + 1] = tiles.size() - 1
				tile_of[m.id * 3 + 2] = tiles.size() - 1
			_:
				tiles.append(_noise(base, variance, rng))
				_all_faces(m.id, tiles.size() - 1)
	tile_count = tiles.size()
	atlas_rows = maxi(1, int(ceil(float(tile_count) / float(ATLAS_COLS))))
	image = Image.create_empty(ATLAS_COLS * TILE, atlas_rows * TILE, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		@warning_ignore("integer_division")
		var tx := (i % ATLAS_COLS) * TILE
		@warning_ignore("integer_division")
		var ty := (i / ATLAS_COLS) * TILE
		image.blit_rect(tiles[i], Rect2i(0, 0, TILE, TILE), Vector2i(tx, ty))
	texture = ImageTexture.create_from_image(image)
	return self


## UV rect (in 0..1 atlas space) for a material face, inset half a texel to
## avoid bleeding between tiles.
func uv_rect(material_id: int, face: int) -> Rect2:
	var t := 0
	var i := material_id * 3 + face
	if i >= 0 and i < tile_of.size():
		t = tile_of[i]
	@warning_ignore("integer_division")
	var col := t % ATLAS_COLS
	@warning_ignore("integer_division")
	var row := t / ATLAS_COLS
	var w := 1.0 / float(ATLAS_COLS)
	var h := 1.0 / float(atlas_rows)
	var inset_u := 0.5 / float(ATLAS_COLS * TILE)
	var inset_v := 0.5 / float(atlas_rows * TILE)
	return Rect2(col * w + inset_u, row * h + inset_v, w - 2.0 * inset_u, h - 2.0 * inset_v)


func _all_faces(id: int, tile: int) -> void:
	tile_of[id * 3 + 0] = tile
	tile_of[id * 3 + 1] = tile
	tile_of[id * 3 + 2] = tile


static func _vary(c: Color, amount: float, rng: RandomNumberGenerator) -> Color:
	var v := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(c.r * v, 0, 1), clampf(c.g * v, 0, 1), clampf(c.b * v, 0, 1), c.a)


static func _flat(c: Color) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


static func _noise(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _vary(base, variance, rng))
	return img


static func _speckle(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := _noise(base, variance * 0.5, rng)
	for i in 14:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		var c := base.darkened(0.25) if rng.randf() < 0.6 else base.lightened(0.2)
		img.set_pixel(x, y, c)
		if rng.randf() < 0.5 and x + 1 < TILE:
			img.set_pixel(x + 1, y, c)
	return img


static func _grass_side(dirt: Color, grass: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := _noise(dirt, variance, rng)
	for x in TILE:
		var depth := 2 + rng.randi_range(0, 2)
		for y in depth:
			img.set_pixel(x, y, _vary(grass, variance, rng))
	return img


static func _planks(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		var plank := y / 4
		var shade := 1.0 + ((plank % 2) * 0.08 - 0.04)
		for x in TILE:
			var c := _vary(base * Color(shade, shade, shade, 1.0), variance * 0.6, rng)
			if y % 4 == 3:
				c = c.darkened(0.35)
			if (x + plank * 5) % 11 == 0:
				c = c.darkened(0.2)
			img.set_pixel(x, y, c)
	return img


static func _bricks(base: Color, mortar: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		var row := y / 4
		var offset := 0 if row % 2 == 0 else 4
		for x in TILE:
			var is_mortar := (y % 4 == 3) or ((x + offset) % 8 == 7)
			img.set_pixel(x, y, _vary(mortar, 0.05, rng) if is_mortar else _vary(base, variance, rng))
	return img


static func _glass(base: Color, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var pane := Color(base.r, base.g, base.b, 0.28)
	img.fill(pane)
	for i in TILE:
		img.set_pixel(i, 0, Color(base.darkened(0.3), 0.9))
		img.set_pixel(i, TILE - 1, Color(base.darkened(0.3), 0.9))
		img.set_pixel(0, i, Color(base.darkened(0.3), 0.9))
		img.set_pixel(TILE - 1, i, Color(base.darkened(0.3), 0.9))
	for i in 5:
		var d := 3 + i
		if d < TILE - 1:
			img.set_pixel(d, TILE - 1 - d, Color(base.lightened(0.5), 0.6))
	return img


static func _water(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var c := _vary(base, variance, rng)
			if (x + y * 3) % 9 == 0:
				c = c.lightened(0.25)
			c.a = 0.78
			img.set_pixel(x, y, c)
	return img


static func _cracks(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := _noise(base, variance, rng)
	var dark := base.darkened(0.45)
	for i in 3:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		for s in rng.randi_range(6, 14):
			img.set_pixel(posmod(x, TILE), posmod(y, TILE), dark)
			if rng.randf() < 0.5:
				x += rng.randi_range(-1, 1)
			else:
				y += rng.randi_range(-1, 1)
	return img


static func _fire(base: Color, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var d := Vector2(x + 0.5 - TILE * 0.5, y + 0.5 - TILE * 0.5).length() / (TILE * 0.5)
			var c := base.lightened(0.5 * (1.0 - d)) if d < 0.75 else Color("#3a2a20")
			if d < 0.75 and rng.randf() < 0.25:
				c = Color("#ffe27a")
			img.set_pixel(x, y, c)
	return img


static func _leaves(base: Color, variance: float, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var c := _vary(base, variance, rng)
			if rng.randf() < 0.12:
				c.a = 0.0
			img.set_pixel(x, y, c)
	return img
