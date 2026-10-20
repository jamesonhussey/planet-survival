shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled, vertex_lighting;
#include "res://src/render/shaders/ps1_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform bool transparent_pass = false;
uniform float snap_px = 1.0;
uniform float affine_amount = 0.75;
uniform vec2 internal_size = vec2(480.0, 270.0);

varying vec3 affine_uv;
varying float view_depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip = ps1_snap(clip, snap_px, internal_size, PROJECTION_MATRIX);
	POSITION = clip;
	affine_uv = ps1_affine_uv(UV, clip.w, affine_amount);
	view_depth = clip.w;
}

void fragment() {
	vec2 uv = affine_uv.xy / affine_uv.z;
	vec4 tex = texture(albedo_tex, uv);
	if (transparent_pass) {
		if (tex.a < 0.02) {
			discard;
		}
		ALPHA = tex.a;
	} else if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
