class_name EclipseVisuals
extends Node3D
## The sky on planet 01: a corona disc that brightens and a dark moon that
## slides aside as `light_factor` rises. Billboards placed far along the sun
## direction relative to the camera every frame (they never get closer).

var corona: Sprite3D
var moon: Sprite3D
var camera: Camera3D
var distance: float = 180.0


func setup(cam: Camera3D) -> void:
	camera = cam
	corona = Sprite3D.new()
	corona.texture = ImageTexture.create_from_image(_radial(64, Color(1.0, 0.95, 0.8), 0.18, 0.5))
	corona.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	corona.shaded = false
	corona.no_depth_test = true
	corona.render_priority = -10
	corona.pixel_size = 0.9
	corona.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	corona.transparent = true
	add_child(corona)
	moon = Sprite3D.new()
	moon.texture = ImageTexture.create_from_image(_disc(48, Color(0.05, 0.03, 0.08)))
	moon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	moon.shaded = false
	moon.no_depth_test = true
	moon.render_priority = -9
	moon.pixel_size = 0.9
	moon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	moon.transparent = true
	add_child(moon)


func update(sun_dir: Vector3, light_factor: float) -> void:
	if camera == null:
		return
	var base := camera.global_position + sun_dir * distance
	corona.global_position = base
	corona.modulate = Color(1, 1, 1, 0.35 + 0.65 * light_factor)
	corona.scale = Vector3.ONE * (1.0 + light_factor * 1.6)
	# The moon slides sideways (perpendicular to the sun direction) as the light grows.
	var side := sun_dir.cross(Vector3.UP).normalized()
	moon.global_position = base + side * light_factor * 70.0 + Vector3.UP * light_factor * 10.0
	moon.modulate = Color(1, 1, 1, 1.0)


static func _radial(size: int, color: Color, inner: float, outer: float) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / (size * 0.5)
			var a := 1.0 - smoothstep(inner, outer, d)
			# Spiky corona: modulate by angle.
			var ang := atan2(y - c.y, x - c.x)
			a *= 0.75 + 0.25 * absf(sin(ang * 6.0))
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(a, 0.0, 1.0)))
	return img


static func _disc(size: int, color: Color) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / (size * 0.5)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0 if d < 0.96 else 0.0))
	return img
