class_name WorldCommands
extends Node
## Server-side validation and application of player commands. Commands are
## plain dictionaries so they serialise for RPC later:
##   {"type": "dig",   "pos": Vector3i, "from": Vector3}
##   {"type": "place", "pos": Vector3i, "block": int, "from": Vector3}
## Validation only uses material properties and reach, never special cases.

const REACH := 5.5

var session: Session = null
var world: WorldData = null
var player_lookup: Callable = Callable()   # peer id -> PlayerState (hotbar etc.)

signal command_rejected(peer: int, cmd: Dictionary, reason: String)
signal block_dug(peer: int, pos: Vector3i, block_id: int)
signal block_placed(peer: int, pos: Vector3i, block_id: int)


func setup(world_data: WorldData) -> void:
	world = world_data


func handle(cmd: Dictionary) -> void:
	var peer: int = int(cmd.get("peer", 1))
	match str(cmd.get("type", "")):
		"dig":
			_dig(peer, cmd)
		"place":
			_place(peer, cmd)
		_:
			command_rejected.emit(peer, cmd, "unknown command")


func _in_reach(cmd: Dictionary, pos: Vector3i) -> bool:
	if not cmd.has("from"):
		return true
	var from: Vector3 = cmd["from"]
	return from.distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5)) <= REACH + 0.87


func _dig(peer: int, cmd: Dictionary) -> void:
	var pos: Vector3i = cmd.get("pos", Vector3i.ZERO)
	if not world.in_bounds(pos):
		command_rejected.emit(peer, cmd, "out of bounds")
		return
	if not _in_reach(cmd, pos):
		command_rejected.emit(peer, cmd, "out of reach")
		return
	var id := world.get_block(pos)
	var mp := world.block_props(pos)
	if id == 0 or not mp.solid:
		command_rejected.emit(peer, cmd, "nothing to dig")
		return
	if pos.y == 0:
		command_rejected.emit(peer, cmd, "bedrock")
		return
	if world.set_block(pos, 0):
		block_dug.emit(peer, pos, id)


func _place(peer: int, cmd: Dictionary) -> void:
	var pos: Vector3i = cmd.get("pos", Vector3i.ZERO)
	var block_id: int = int(cmd.get("block", 0))
	if block_id <= 0 or block_id >= world.props.size():
		command_rejected.emit(peer, cmd, "invalid block")
		return
	if not world.in_bounds(pos):
		command_rejected.emit(peer, cmd, "out of bounds")
		return
	if not _in_reach(cmd, pos):
		command_rejected.emit(peer, cmd, "out of reach")
		return
	var existing := world.block_props(pos)
	if existing.solid:
		command_rejected.emit(peer, cmd, "occupied")
		return
	if cmd.has("blocked_by_body") and bool(cmd["blocked_by_body"]):
		command_rejected.emit(peer, cmd, "player in the way")
		return
	if world.set_block(pos, block_id):
		block_placed.emit(peer, pos, block_id)
