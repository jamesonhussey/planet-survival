class_name Session
extends Node
## Authority boundary inside a run. There is always a server: in solo play
## this is a local host with no peers; online, the Net autoload says whether
## we are the host or a client. World mutations are commands submitted here;
## the server validates and applies them and the Replicator broadcasts the
## results. Sims and AI only run where `is_server()` is true.

enum Mode { LOCAL_HOST, HOST, CLIENT }

var mode: Mode = Mode.LOCAL_HOST
var commands: WorldCommands = null
var replicator: Node = null
var local_peer_id: int = 1


func is_server() -> bool:
	return mode != Mode.CLIENT


func is_online() -> bool:
	return mode != Mode.LOCAL_HOST


func setup(world_commands: WorldCommands) -> void:
	commands = world_commands
	commands.session = self
	if Net.is_online():
		mode = Mode.HOST if Net.is_server() else Mode.CLIENT
		local_peer_id = Net.local_id()
	else:
		mode = Mode.LOCAL_HOST
		local_peer_id = 1


## Entry point used by player input. Routes to the server-side handler.
func submit(cmd: Dictionary) -> void:
	cmd["peer"] = local_peer_id
	if is_server():
		commands.handle(cmd)
	elif replicator != null:
		replicator.send_command(cmd)
