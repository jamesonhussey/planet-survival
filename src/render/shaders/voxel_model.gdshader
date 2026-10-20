shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled, vertex_lighting;
#include "res://src/render/shaders/ps1_common.gdshaderinc"

uniform bool emissive = false;
uniform float emission_strength = 1.5;
uniform float desaturate = 0.0;
uniform float snap_px = 1.0;
uniform float affine_amount = 0.75;
uniform vec2 internal_size = vec2(480.0, 270.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = ps1_snap(clip, snap_px, internal_size, PROJECTION_MATRIX);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(col, vec3(grey) * 0.8, desaturate);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	if (emissive) {
		EMISSION = COLOR.rgb * emission_strength * COLOR.a;
	}
}
