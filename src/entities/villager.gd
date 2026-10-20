class_name Villager
extends Creature
## A settler. Idles near home, wanders a little, and when a hazard warning
## starts goes home and stays until the all-clear. Talks, trades and gives
## small tasks (see data/npcs/villagers.json). Vulnerable like everyone.

var npc_id: String = ""
var display_name: String = ""
var npc_kind: String = ""
var home: Vector3 = Vector3.ZERO
var sheltering: bool = false
var leash: float = 7.0
var talk_cooldown: float = 0.0
var name_label: Label3D
var active_task: String = ""     # task id handed to a player
var done_tasks: Dictionary = {}  # task id -> true
var line_index: int = 0


func setup_villager(id: String, pname: String, vk: String, home_pos: Vector3) -> void:
	npc_id = id
	display_name = pname
	npc_kind = vk
	home = home_pos
	speed = 1.6
	breathes = true
	vitals.hp = 50.0
	vitals.max_hp = 50.0
	name_label = Label3D.new()
	name_label.text = pname
	name_label.font = PixelFont.get_font(1)
	name_label.font_size = 9
	name_label.pixel_size = 0.02
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position = Vector3(0, rig_height + 0.3, 0)
	add_child(name_label)


func set_sheltering(on: bool) -> void:
	sheltering = on


func _brain(delta: float) -> void:
	talk_cooldown = maxf(0.0, talk_cooldown - delta)
	if sheltering or vitals.suffocating:
		# Go home and stay. If home is unreachable the villager still tries.
		go_toward(home, 0.5)
		if not moving:
			wander_dir = Vector3.ZERO
		return
	wander_timer -= delta
	var from_home := global_position - home
	from_home.y = 0.0
	if from_home.length() > leash:
		go_toward(home, leash * 0.5)
		return
	if wander_timer <= 0.0:
		moving = rng.randf() < 0.4
		wander_timer = rng.randf_range(2.0, 6.0)
		if moving:
			var a := rng.randf() * TAU
			wander_dir = Vector3(cos(a), 0, sin(a))
	if flee_timer > 0.0:
		flee_timer -= delta
		moving = true


func die(cause: String) -> void:
	super.die(cause)
	if name_label != null:
		name_label.text = display_name + " (dead)"
