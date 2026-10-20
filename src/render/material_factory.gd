class_name MaterialFactory
extends RefCounted
## Builds every runtime material from code. Terrain materials get the block
## atlas; everything uses nearest filtering and vertex colours. The PS1
## vertex-snap/affine shader is applied here so it is the single place to
## change the world look.

const TERRAIN_SHADER := "res://src/render/shaders/terrain.gdshader"
const VOXEL_SHADER := "res://src/render/shaders/voxel_model.gdshader"


static func terrain_opaque(atlas_tex: Texture2D, settings: Dictionary) -> Material:
	var sh := load(TERRAIN_SHADER) as Shader
	if sh == null:
		return _fallback_standard(atlas_tex, false)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo_tex", atlas_tex)
	m.set_shader_parameter("transparent_pass", false)
	apply_settings(m, settings)
	return m


static func terrain_transparent(atlas_tex: Texture2D, settings: Dictionary) -> Material:
	var sh := load(TERRAIN_SHADER) as Shader
	if sh == null:
		return _fallback_standard(atlas_tex, true)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo_tex", atlas_tex)
	m.set_shader_parameter("transparent_pass", true)
	m.render_priority = 1
	apply_settings(m, settings)
	return m


## Vertex-coloured material for micro-voxel models.
static func voxel_model(settings: Dictionary, emissive: bool = false) -> Material:
	var sh := load(VOXEL_SHADER) as Shader
	if sh == null:
		var s := StandardMaterial3D.new()
		s.vertex_color_use_as_albedo = true
		s.roughness = 1.0
		return s
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("emissive", emissive)
	apply_settings(m, settings)
	return m


static func apply_settings(m: ShaderMaterial, settings: Dictionary) -> void:
	m.set_shader_parameter("snap_px", float(settings.get("vertex_snap", 1.0)))
	m.set_shader_parameter("affine_amount", float(settings.get("affine_amount", 0.75)))
	m.set_shader_parameter("internal_size", Vector2(float(settings.get("internal_width", 480)), float(settings.get("internal_height", 270))))


static func _fallback_standard(atlas_tex: Texture2D, transparent: bool) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_texture = atlas_tex
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.vertex_color_use_as_albedo = true
	s.roughness = 1.0
	s.metallic = 0.0
	if transparent:
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
	return s
