class_name PixelFont
extends RefCounted
## Builds a chunky pixel FontFile in code from PixelFontGlyphs, with a 1px
## black outline baked into every glyph (bitmap fonts cannot grow outlines
## at runtime). `scale` multiplies the pixel size (1 = 5x7 glyphs in a 7x9
## cell, 2 = 14x18 cells, ...). Results are cached per scale.

static var _cache: Dictionary = {}

const COLS := 16


static func get_font(scale: int = 1) -> FontFile:
	if _cache.has(scale):
		return _cache[scale]
	var f := build(scale)
	_cache[scale] = f
	return f


static func cell_size(scale: int) -> Vector2i:
	return Vector2i((PixelFontGlyphs.W + 2) * scale, (PixelFontGlyphs.H + 2) * scale)


static func build(scale: int = 1) -> FontFile:
	var cw := (PixelFontGlyphs.W + 2) * scale
	var ch := (PixelFontGlyphs.H + 2) * scale
	var keys := PixelFontGlyphs.GLYPHS.keys()
	var rows := int(ceil(float(keys.size()) / float(COLS)))
	var img := Image.create_empty(COLS * cw, rows * ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var font := FontFile.new()
	var size := Vector2i(ch, 0)
	font.fixed_size = ch
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.allow_system_fallback = false
	var i := 0
	for key in keys:
		var rows_data: Array = PixelFontGlyphs.GLYPHS[key]
		@warning_ignore("integer_division")
		var cx := (i % COLS) * cw
		@warning_ignore("integer_division")
		var cy := (i / COLS) * ch
		_draw_glyph(img, cx, cy, rows_data, scale)
		var code: int = (key as String).unicode_at(0)
		font.set_glyph_texture_idx(0, size, code, 0)
		font.set_glyph_uv_rect(0, size, code, Rect2(cx, cy, cw, ch))
		font.set_glyph_size(0, size, code, Vector2(cw, ch))
		# Baseline sits one outline pixel above the cell bottom.
		font.set_glyph_offset(0, size, code, Vector2(-scale, -(PixelFontGlyphs.H + 1) * scale))
		font.set_glyph_advance(0, ch, code, Vector2((PixelFontGlyphs.W + 1) * scale, 0))
		i += 1
	font.set_texture_image(0, size, 0, img)
	font.set_cache_ascent(0, ch, (PixelFontGlyphs.H + 1) * scale)
	font.set_cache_descent(0, ch, 1 * scale)
	return font


static func _draw_glyph(img: Image, ox: int, oy: int, rows_data: Array, scale: int) -> void:
	# Pass 1: outline (black) around every lit pixel, pass 2: white pixels on top.
	for layer in 2:
		for ry in rows_data.size():
			var row: String = rows_data[ry]
			for rx in row.length():
				if row[rx] != "#":
					continue
				if layer == 0:
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							_fill(img, ox + (rx + 1 + dx) * scale, oy + (ry + 1 + dy) * scale, scale, Color.BLACK)
				else:
					_fill(img, ox + (rx + 1) * scale, oy + (ry + 1) * scale, scale, Color.WHITE)


static func _fill(img: Image, x: int, y: int, s: int, c: Color) -> void:
	for yy in s:
		for xx in s:
			var px := x + xx
			var py := y + yy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, c)


## A Theme using the pixel font for every Control, white text.
static func make_theme(scale: int = 1) -> Theme:
	var t := Theme.new()
	var f := get_font(scale)
	t.default_font = f
	t.default_font_size = cell_size(scale).y
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_color", "Button", Color.WHITE)
	return t
