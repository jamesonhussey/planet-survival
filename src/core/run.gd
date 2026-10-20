extends Node
## One survival run. Built entirely from code by Game.start_run().
## (Milestone 1 stub: subsystems are attached as they land.)

var planet_id: String = "04"
var mode_id: String = "standard"
var world_seed: int = 1337


func _ready() -> void:
	var planet := Data.planet(planet_id)
	if planet.is_empty():
		push_error("[run] unknown planet '%s'" % planet_id)
		return
	print("[run] planet %s (%s), mode %s, seed %d" % [planet_id, planet.get("name", "?"), mode_id, world_seed])
