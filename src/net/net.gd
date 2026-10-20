extends Node
## Autoload "Net": connection lifecycle and the join handshake. It exists on
## every peer at the same path (/root/Net) so the handshake RPCs resolve
## before any run is built. In-run replication lives in Run/Replicator.
##
## Flow: host() creates an ENet server and the host's own run. A joining
## peer calls join(); on connection it sends hello(); the server answers
## welcome(config) with planet/mode/seed and the clock; the client then
## builds its run from that config and announces ready_in_run().

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT := 24565
const MAX_PEERS := 8

var role: Role = Role.NONE
var peer: ENetMultiplayerPeer = null
var run_config: Dictionary = {}        # the config the host is running (planet_id, mode_id, seed)
var peers_ready: Dictionary = {}       # peer id -> true once their run is built
var peer_names: Dictionary = {}        # peer id -> display name
var my_name: String = "Survivor"
var last_error: String = ""

signal hosting_started(port: int)
signal joined(config: Dictionary)
signal join_failed(reason: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal peer_run_ready(id: int)
signal disconnected_from_host


func is_online() -> bool:
	return role != Role.NONE


func is_server() -> bool:
	return role != Role.CLIENT


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func host(config: Dictionary, port: int = DEFAULT_PORT) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		last_error = "could not open port %d (%s)" % [port, error_string(err)]
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	run_config = config
	peers_ready = {1: true}
	peer_names = {1: my_name}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[net] hosting on port %d" % port)
	hosting_started.emit(port)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "could not connect to %s:%d (%s)" % [address, port, error_string(err)]
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("[net] joining %s:%d" % [address, port])
	return OK


func leave() -> void:
	if not is_online():
		return
	for s in [[multiplayer.peer_connected, _on_peer_connected], [multiplayer.peer_disconnected, _on_peer_disconnected],
			[multiplayer.connected_to_server, _on_connected_to_server], [multiplayer.connection_failed, _on_connection_failed],
			[multiplayer.server_disconnected, _on_server_disconnected]]:
		if (s[0] as Signal).is_connected(s[1]):
			(s[0] as Signal).disconnect(s[1])
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	role = Role.NONE
	peers_ready.clear()
	peer_names.clear()
	run_config = {}


func peer_ids() -> Array:
	if not is_online():
		return [1]
	var out: Array = [1]
	for id in multiplayer.get_peers():
		if not out.has(id):
			out.append(id)
	if not out.has(local_id()):
		out.append(local_id())
	return out


func ready_peer_ids() -> Array:
	return peers_ready.keys()


# ---- server side ----

func _on_peer_connected(id: int) -> void:
	print("[net] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	peers_ready.erase(id)
	peer_names.erase(id)
	peer_left.emit(id)


@rpc("any_peer", "call_remote", "reliable")
func hello(name: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	peer_names[id] = name
	welcome.rpc_id(id, run_config)
	peer_joined.emit(id)


@rpc("any_peer", "call_remote", "reliable")
func ready_in_run() -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	peers_ready[id] = true
	peer_run_ready.emit(id)


# ---- client side ----

func _on_connected_to_server() -> void:
	print("[net] connected, sending hello")
	hello.rpc_id(1, my_name)


func _on_connection_failed() -> void:
	last_error = "connection failed"
	leave()
	join_failed.emit("connection failed")


func _on_server_disconnected() -> void:
	leave()
	disconnected_from_host.emit()


@rpc("authority", "call_remote", "reliable")
func welcome(config: Dictionary) -> void:
	run_config = config
	print("[net] welcome: planet %s seed %s" % [str(config.get("planet_id", "?")), str(config.get("seed", "?"))])
	joined.emit(config)
