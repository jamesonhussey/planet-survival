class_name InputSetup
extends RefCounted
## Defines every input action from code so project.godot stays minimal.
## Call InputSetup.install() once at boot. Safe to call twice.

const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"inventory": [KEY_TAB],
	"health_screen": [KEY_H],
	"flashlight": [KEY_F],
	"hotbar_next": [KEY_BRACKETRIGHT],
	"hotbar_prev": [KEY_BRACKETLEFT],
	"debug_trigger_hazard": [KEY_F5],
	"debug_time_scale": [KEY_F6],
	"debug_fly": [KEY_F7],
	"debug_reload_render": [KEY_F8],
	"debug_overlay": [KEY_F3],
	"pause": [KEY_ESCAPE],
	"restart": [KEY_R],
}

const MOUSE_ACTIONS := {
	"dig": MOUSE_BUTTON_LEFT,
	"place": MOUSE_BUTTON_RIGHT,
}

const HOTBAR_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]


static func install() -> void:
	for action in ACTIONS:
		_ensure(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	for action in MOUSE_ACTIONS:
		_ensure(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
	for i in HOTBAR_KEYS.size():
		var action := "hotbar_%d" % (i + 1)
		_ensure(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = HOTBAR_KEYS[i]
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
