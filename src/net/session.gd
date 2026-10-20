class_name Session
extends Node
## Authority boundary. There is always a server: in solo play this node is a
## local host with no peers. Every world mutation is a command submitted
## here; the server validates and applies it, then the result is broadcast
## (in Milestone 4 over RPC, today by direct signal). Sims and AI only run
## where `is_server()` is true.

enum Mode { LOCAL_HOST, HOST, CLIENT }

var mode: Mode = Mode.LOCAL_HOST
var commands: WorldCommands = null
var local_peer_id: int = 1


func is_server() -> bool:
	return mode != Mode.CLIENT


func setup_local_host(world_commands: WorldCommands) -> void:
	mode = Mode.LOCAL_HOST
	commands = world_commands
	commands.session = self


## Entry point used by player input. Routes to the server-side handler.
func submit(cmd: Dictionary) -> void:
	cmd["peer"] = local_peer_id
	if is_server():
		commands.handle(cmd)
	else:
		# Milestone 4: commands.rpc_id(1, "handle", cmd)
		push_warning("client submit not implemented yet")
