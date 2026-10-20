shader_type canvas_item;
// Low-res upscale post pass: ordered (Bayer 4x4) dithering, colour
// quantisation to N bits per channel, vignette, optional scanlines.
// Every knob comes from data/render_settings.json via PS1Pipeline.

uniform float dither_strength = 0.55;
uniform float color_bits = 5.0;
uniform float vignette = 0.25;
uniform float scanline_strength = 0.0;
uniform vec2 internal_size = vec2(480.0, 270.0);
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float tint_amount = 0.0;

// 2x2 Bayer element 0..3
int bayer2(int x, int y) {
	return (((y & 1) * 3) + ((x & 1) * 2)) & 3;
}

// 4x4 Bayer element 0..15 (recursive construction)
int bayer4(int x, int y) {
	return 4 * bayer2(x & 1, y & 1) + bayer2((x >> 1) & 1, (y >> 1) & 1);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec2 px = floor(UV * internal_size);
	int ix = int(px.x);
	int iy = int(px.y);
	float threshold = (float(bayer4(ix, iy)) + 0.5) / 16.0 - 0.5;
	float levels = pow(2.0, color_bits) - 1.0;
	vec3 col = src.rgb;
	col = mix(col, col * tint, tint_amount);
	col += threshold * dither_strength / levels;
	col = floor(col * levels + 0.5) / levels;
	col = clamp(col, 0.0, 1.0);
	vec2 d = UV - vec2(0.5);
	col *= 1.0 - vignette * dot(d, d) * 2.2;
	if (scanline_strength > 0.0) {
		float s = mod(px.y, 2.0) < 1.0 ? 1.0 : 1.0 - scanline_strength;
		col *= s;
	}
	COLOR = vec4(col, 1.0);
}
