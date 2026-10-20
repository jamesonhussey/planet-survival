class_name Telegraph
extends Node3D
## Turns hazard cues (plain dictionaries from the planet JSON) into things the
## player can perceive: toasts, procedural sounds, camera shake, bubbling
## particles at source cells, sky tint. Pure presentation; runs on every
## peer. Lives inside the 3D viewport so particles render.

var sounds: SoundBank
var player: PlayerController
var pipeline: PS1Pipeline
var hazards: HazardDirector = null
var _bubble_nodes: Array[CPUParticles3D] = []
var _bubble_mat: StandardMaterial3D


func setup(sound_bank: SoundBank, player_ctrl: PlayerController, ps1: PS1Pipeline) -> void:
	sounds = sound_bank
	player = player_ctrl
	pipeline = ps1
	EventBus.hazard_cue.connect(_on_cue)
	EventBus.hazard_phase_changed.connect(_on_phase)
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.vertex_color_use_as_albedo = true
	_bubble_mat.albedo_color = Color(0.85, 0.95, 0.9, 0.9)
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _on_cue(_hazard_id: String, cue: Dictionary) -> void:
	match str(cue.get("type", "")):
		"toast":
			EventBus.toast.emit(str(cue.get("text", "")), float(cue.get("seconds", 3.0)))
		"sound":
			if sounds != null:
				sounds.play(str(cue.get("id", "")), bool(cue.get("loop", false)), float(cue.get("volume_db", 0.0)))
		"shake":
			if player != null:
				player.add_shake(float(cue.get("strength", 0.2)) * float(cue.get("intensity", 1.0)), float(cue.get("seconds", 2.0)))
			if sounds != null:
				sounds.play("heartbeat")
		"lake_bubbles":
			_bubbles(cue.get("points", []), float(cue.get("intensity", 0.5)))
			if sounds != null:
				sounds.play("bubbles")
		"haze":
			pass  # gas renderer handles the visible cloud
		_:
			pass


func _on_phase(_hazard_id: String, phase: int, _intensity: float) -> void:
	match phase:
		HazardModule.Phase.IDLE:
			_clear_bubbles()
			if sounds != null:
				sounds.stop("deep_rumble")
				sounds.stop("gas_hiss")
			if pipeline != null:
				pipeline.set_tint(Color.WHITE, 0.0)
		HazardModule.Phase.ACTIVE:
			if sounds != null:
				sounds.stop("deep_rumble")
			if pipeline != null:
				var tint := Color(0.85, 1.0, 0.75)
				var amount := 0.25
				var m: HazardModule = hazards.get_module(_hazard_id) if hazards != null else null
				if m != null and m.cfg.has("active_tint"):
					tint = Color.html(str(m.cfg["active_tint"]))
					amount = float(m.cfg.get("active_tint_amount", 0.25))
				pipeline.set_tint(tint, amount)
		HazardModule.Phase.RECOVERY:
			_clear_bubbles()
			if sounds != null:
				sounds.stop("gas_hiss")
			if pipeline != null:
				pipeline.set_tint(Color(0.9, 1.0, 0.85), 0.1)


func _bubbles(points: Array, intensity: float) -> void:
	_clear_bubbles()
	for p in points:
		var cell: Vector3i = p
		var ps := CPUParticles3D.new()
		ps.amount = int(6 + 18 * intensity)
		ps.lifetime = 1.2
		ps.one_shot = false
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		ps.emission_box_extents = Vector3(0.5, 0.05, 0.5)
		ps.direction = Vector3.UP
		ps.spread = 10.0
		ps.gravity = Vector3(0, 1.5, 0)
		ps.initial_velocity_min = 0.6
		ps.initial_velocity_max = 1.6 + intensity
		ps.scale_amount_min = 0.08
		ps.scale_amount_max = 0.2
		ps.color = Color(0.9, 1.0, 0.95, 0.8)
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = _bubble_mat
		ps.mesh = mesh
		ps.position = Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		add_child(ps)
		_bubble_nodes.append(ps)


func _clear_bubbles() -> void:
	for n in _bubble_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_bubble_nodes.clear()
