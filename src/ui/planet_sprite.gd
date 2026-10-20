class_name PlanetSprite
extends RefCounted
## Procedural pixel-art planets for the select screen: a shaded sphere with
## noise continents/oceans/clouds from the planet's palette, rendered to an
## Image. `phase` rotates the surface (longitude offset) for animation.


static func render(size: int, palette: Dictionary, planet_id: String, phase: float, seed: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.6
	noise.fractal_octaves = 4
	var cloud := FastNoiseLite.new()
	cloud.seed = seed + 11
	cloud.frequency = 2.4
	cloud.fractal_octaves = 3
	var ramps: Dictionary = palette.get("ramps", {})
	var land := _ramp(ramps, ["leaf", "grass", "sand", "dust", "rock"], [Color("#2f6e3a"), Color("#4f9a4a"), Color("#8fd19a")])
	var sea := _ramp(ramps, ["water", "sea", "stone"], [Color("#2a5a58"), Color("#3f8078"), Color("#5aa89a")])
	var sky_c := Color.html(str(palette.get("sky_horizon", "#d8e3b4")))
	var r := size * 0.46
	var c := Vector2(size * 0.5, size * 0.5)
	var light_dir := Vector3(-0.55, 0.45, 0.7).normalized()
	for y in size:
		for x in size:
			var p := (Vector2(x + 0.5, y + 0.5) - c) / r
			var d2 := p.length_squared()
			if d2 > 1.0:
				continue
			var z := sqrt(1.0 - d2)
			var n := Vector3(p.x, -p.y, z)
			# Longitude/latitude with rotation.
			var lon := atan2(n.x, n.z) + phase
			var lat := asin(clampf(n.y, -1.0, 1.0))
			var sx := cos(lat) * cos(lon)
			var sy := sin(lat)
			var sz := cos(lat) * sin(lon)
			var h := noise.get_noise_3d(sx * 2.0, sy * 2.0, sz * 2.0)
			var col: Color
			match planet_id:
				"01":
					col = _pick(land, h * 0.5 + 0.5)
				"02":
					col = _pick(sea, h * 0.5 + 0.5) if h < 0.25 else _pick(land, (h - 0.25) * 2.0)
				_:
					col = _pick(sea, h * 0.5 + 0.5) if h < -0.05 else _pick(land, (h + 0.05) * 1.2)
			var cl := cloud.get_noise_3d(sx * 2.0 + phase * 0.3, sy * 2.0, sz * 2.0)
			if cl > 0.32 and planet_id != "01":
				col = col.lerp(Color(0.95, 0.95, 0.9), 0.75)
			var shade := clampf(n.dot(light_dir), 0.0, 1.0)
			shade = 0.18 + 0.82 * shade
			if planet_id == "01":
				shade *= 0.45  # eclipse twilight
			col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			# Rim atmosphere.
			if d2 > 0.86:
				col = col.lerp(sky_c, (d2 - 0.86) / 0.14 * 0.6)
			img.set_pixel(x, y, col)
	# Planet 01: a dark moon disc in front, planet 03: a ring.
	if planet_id == "01":
		var mc := c + Vector2(-r * 0.2, -r * 0.1)
		for y in size:
			for x in size:
				if (Vector2(x + 0.5, y + 0.5) - mc).length() < r * 0.78:
					img.set_pixel(x, y, Color(0.06, 0.04, 0.09))
	return img


static func _ramp(ramps: Dictionary, names: Array, fallback: Array) -> Array:
	for n in names:
		if ramps.has(n):
			var out: Array = []
			for hex in ramps[n]:
				out.append(Color.html(hex))
			return out
	return fallback


static func _pick(ramp: Array, t: float) -> Color:
	var i := clampi(int(clampf(t, 0.0, 0.999) * ramp.size()), 0, ramp.size() - 1)
	return ramp[i]
