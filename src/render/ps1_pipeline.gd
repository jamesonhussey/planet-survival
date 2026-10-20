class_name PS1Pipeline
extends Node
## Renders the whole 3D scene (and the HUD) into a low-resolution SubViewport,
## then draws that texture upscaled with nearest filtering through the post
## shader (dither, quantise, vignette). Everything tunable comes from
## data/render_settings.json; call apply_settings() to hot-reload.
## Input events must be forwarded to the SubViewport (nodes inside it do not
## receive the root viewport's events), which _input() does.

var viewport: SubViewport
var display_layer: CanvasLayer
var display: TextureRect
var post: ShaderMaterial
var settings: Dictionary = {}


func build(render_settings: Dictionary) -> SubViewport:
	settings = render_settings
	viewport = SubViewport.new()
	viewport.name = "View"
	viewport.size = _internal_size()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.handle_input_locally = true
	viewport.audio_listener_enable_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	viewport.positional_shadow_atlas_size = 1024
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.gui_embed_subwindows = true
	add_child(viewport)

	display_layer = CanvasLayer.new()
	display_layer.name = "Display"
	display_layer.layer = 10
	add_child(display_layer)
	display = TextureRect.new()
	display.name = "Screen"
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://src/render/shaders/post.gdshader")
	display.material = post
	display_layer.add_child(display)
	# Black bars when the window aspect differs from 16:9.
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	display.add_child(bg)
	apply_settings(settings)
	return viewport


func _internal_size() -> Vector2i:
	return Vector2i(int(settings.get("internal_width", 480)), int(settings.get("internal_height", 270)))


func apply_settings(render_settings: Dictionary) -> void:
	settings = render_settings
	if viewport.size != _internal_size():
		viewport.size = _internal_size()
	post.set_shader_parameter("dither_strength", float(settings.get("dither_strength", 0.55)))
	post.set_shader_parameter("color_bits", float(settings.get("color_bits", 5)))
	post.set_shader_parameter("vignette", float(settings.get("vignette", 0.25)))
	post.set_shader_parameter("scanline_strength", float(settings.get("scanline_strength", 0.0)))
	post.set_shader_parameter("internal_size", Vector2(_internal_size()))


func set_tint(color: Color, amount: float) -> void:
	post.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	post.set_shader_parameter("tint_amount", amount)


## Window-space to internal-resolution transform for the letterboxed display.
func screen_to_view_transform() -> Transform2D:
	var win := Vector2(get_viewport().get_visible_rect().size)
	var internal := Vector2(_internal_size())
	var scale := minf(win.x / internal.x, win.y / internal.y)
	if scale <= 0.0:
		return Transform2D.IDENTITY
	var offset := (win - internal * scale) * 0.5
	return Transform2D(0.0, Vector2(1.0 / scale, 1.0 / scale), 0.0, -offset / scale)


func _input(event: InputEvent) -> void:
	if viewport == null:
		return
	# Mouse events carry window coordinates; remap them into the low-res
	# viewport so Controls inside it hit-test correctly. Captured-mouse look
	# uses relative motion and is pushed untouched.
	if event is InputEventMouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		viewport.push_input(event.xformed_by(screen_to_view_transform()), false)
	else:
		viewport.push_input(event, false)
