// Shared PS1-style vertex tricks. Include from spatial shaders.
// Uniforms expected in the including shader:
//   uniform float snap_px;        // vertex snap grid in internal-resolution pixels (0 = off)
//   uniform float affine_amount;  // 0..1 how much perspective-incorrect texture warping
//   uniform vec2 internal_size;   // internal render resolution

// Snap a clip-space position to the low-res pixel grid (vertex jitter).
// Skipped for orthographic projections (shadow-map passes use them); snapping
// the depth pass would quantise shadows into slabs.
vec4 ps1_snap(vec4 clip, float snap, vec2 res, mat4 proj) {
	if (snap <= 0.0 || clip.w <= 0.0 || abs(proj[3][3]) > 0.5) {
		return clip;
	}
	vec2 half_grid = (res / snap) * 0.5;
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = floor(ndc.xy * half_grid + 0.5) / half_grid;
	return vec4(ndc * clip.w, clip.w);
}

// Affine texture mapping: multiply UV by w in the vertex stage and divide by
// the interpolated w in the fragment stage. Interpolation then happens in
// screen space (PS1 had no perspective-correct texturing).
vec3 ps1_affine_uv(vec2 uv, float w, float amount) {
	float ww = mix(1.0, max(w, 0.001), amount);
	return vec3(uv * ww, ww);
}
