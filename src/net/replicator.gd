class_name Replicator
extends Node
## Every in-run RPC lives here so both peers have the same node path
## (Run/Replicator). The server owns the world, hazards, creatures, pickups
## and rituals; clients own their own movement, inventory and health
## (friendly co-op). The Run node calls into this and reacts to its signals.
##
## Wire format notes: Vector3i/Vector3/Dictionary go through Godot's RPC
## variant encoding as-is. Gas cells are packed into bytes and zstd-compressed.

var run: Node
var world: WorldData
var peer_states: Dictionary = {}     # peer -> {pos, yaw, pitch, moving, ghost, name}
var ghosts: Dictionary = {}          # peer -> true
var _clock_accum: float = 0.0
var _gas_accum: float = 0.0
var _creature_accum: float = 0.0
var _ritual_accum: float = 0.0
var _state_accum: float = 0.0

signal remote_block_set(pos: Vector3i, id: int, actor: int)
signal remote_grant(item_id: String, count: int, pos: Vector3)
signal remote_peer_state(peer: int, name: String, pos: Vector3, yaw: float, pitch: float, moving: bool, ghost: bool)
signal remote_peer_left(peer: int)
signal remote_pickup_spawn(id: int, item: Dictionary, pos: Vector3)
signal remote_pickup_remove(id: int)
signal remote_prop_harvested(cell: Vector2i, regrow_at: float, removed: bool)
signal remote_revive(pos: Vector3)
signal remote_ritual(state: Dictionary)
signal client_command(cmd: Dictionary)
signal client_take_pickup(peer: int, id: int)
signal client_drop(peer: int, item: Dictionary, pos: Vector3)
signal client_harvest(peer: int, cell: Vector2i)
signal client_attack(peer: int, creature_id: int)
signal client_died(peer: int, pos: Vector3, items: Array)
signal client_place_tag(peer: int, cairn_pos: Vector3i, owner: int, owner_name: String)


func setup(run_node: Node, world_data: WorldData) -> void:
	run = run_node
	world = world_data


func is_server() -> bool:
	return Net.is_server()


func _ids_except_self() -> Array:
	var out: Array = []
	for id in Net.ready_peer_ids():
		if id != Net.local_id():
			out.append(id)
	return out


# =====================================================================
# server -> clients
# =====================================================================

func broadcast_block(pos: Vector3i, id: int, actor: int) -> void:
	for p in _ids_except_self():
		rpc_block_set.rpc_id(p, pos, id, actor)


@rpc("authority", "call_remote", "reliable")
func rpc_block_set(pos: Vector3i, id: int, actor: int) -> void:
	remote_block_set.emit(pos, id, actor)


## Initial sync for a peer whose run is ready.
func send_initial_state(peer: int, edited: Dictionary, hazard_phase: Array, pickups: Array, harvested: Array, ritual_states: Array) -> void:
	rpc_initial.rpc_id(peer, edited, hazard_phase, pickups, harvested, ritual_states)


@rpc("authority", "call_remote", "reliable")
func rpc_initial(edited: Dictionary, hazard_phase: Array, pickups: Array, harvested: Array, ritual_states: Array) -> void:
	for cpos in edited:
		var c := world.get_chunk(cpos)
		if c != null:
			c.blocks = (edited[cpos] as PackedByteArray).duplicate()
			c.recount()
			c.dirty = true
			c.edited = true
		else:
			world.saved_chunks[cpos] = edited[cpos]
	for cpos in edited:
		if world.get_chunk(cpos) != null:
			run.streamer.remesh_now(cpos)
	if hazard_phase.size() >= 3:
		rpc_hazard_phase(str(hazard_phase[0]), int(hazard_phase[1]), float(hazard_phase[2]))
	for pk in pickups:
		remote_pickup_spawn.emit(int(pk[0]), pk[1], pk[2])
	for h in harvested:
		remote_prop_harvested.emit(Vector2i(int(h[0]), int(h[1])), float(h[2]), bool(h[3]))
	for r in ritual_states:
		remote_ritual.emit(r)


func grant(peer: int, item_id: String, count: int, pos: Vector3) -> void:
	rpc_grant.rpc_id(peer, item_id, count, pos)


@rpc("authority", "call_remote", "reliable")
func rpc_grant(item_id: String, count: int, pos: Vector3) -> void:
	remote_grant.emit(item_id, count, pos)


func broadcast_hazard_phase(hazard_id: String, phase: int, intensity: float) -> void:
	for p in _ids_except_self():
		rpc_hazard_phase.rpc_id(p, hazard_id, phase, intensity)


@rpc("authority", "call_remote", "reliable")
func rpc_hazard_phase(hazard_id: String, phase: int, intensity: float) -> void:
	var m: HazardModule = run.hazards.get_module(hazard_id)
	if m != null:
		m.enter_remote(phase, intensity)


## Pack gas cells near players: int16 x, uint8 y, int16 z, uint8 concentration.
static func pack_gas(cells: Dictionary, centers: Array, radius: float) -> PackedByteArray:
	var buf := PackedByteArray()
	var r2 := radius * radius
	var n := 0
	buf.resize(cells.size() * 6)
	for p in cells:
		var near := centers.is_empty()
		for c in centers:
			var d := Vector2(p.x - c.x, p.z - c.z)
			if d.length_squared() <= r2:
				near = true
				break
		if not near:
			continue
		var o := n * 6
		buf.encode_s16(o, p.x)
		buf.encode_u8(o + 2, clampi(p.y, 0, 255))
		buf.encode_s16(o + 3, p.z)
		buf.encode_u8(o + 5, clampi(int(float(cells[p]) * 255.0), 0, 255))
		n += 1
	buf.resize(n * 6)
	return buf.compress(FileAccess.COMPRESSION_ZSTD)


static func unpack_gas(packed: PackedByteArray, max_cells: int = 60000) -> Dictionary:
	var out: Dictionary = {}
	var buf := packed.decompress(max_cells * 6, FileAccess.COMPRESSION_ZSTD)
	var n := int(buf.size() / 6)
	for i in n:
		var o := i * 6
		var p := Vector3i(buf.decode_s16(o), buf.decode_u8(o + 2), buf.decode_s16(o + 3))
		out[p] = float(buf.decode_u8(o + 5)) / 255.0
	return out


func broadcast_gas(cells: Dictionary) -> void:
	if cells.is_empty() and _last_gas_empty:
		return
	var centers: Array = []
	for s in peer_states.values():
		centers.append(s["pos"])
	var packed := pack_gas(cells, centers, 64.0)
	_last_gas_empty = cells.is_empty()
	for p in _ids_except_self():
		rpc_gas.rpc_id(p, packed)
var _last_gas_empty: bool = false


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_gas(packed: PackedByteArray) -> void:
	if run.gas_hazard != null:
		run.gas_hazard.sim.cells = unpack_gas(packed)


func broadcast_clock(day: int, frac: float, time_scale: float) -> void:
	for p in _ids_except_self():
		rpc_clock.rpc_id(p, day, frac, time_scale)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_clock(day: int, frac: float, time_scale: float) -> void:
	run.clock.day = day
	run.clock.day_fraction = frac
	run.clock.time_scale = time_scale


func relay_peer_state(peer: int) -> void:
	var s: Dictionary = peer_states.get(peer, {})
	if s.is_empty():
		return
	for p in _ids_except_self():
		if p != peer:
			rpc_peer_state.rpc_id(p, peer, s["name"], s["pos"], s["yaw"], s["pitch"], s["moving"], s["ghost"])


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_peer_state(peer: int, pname: String, pos: Vector3, yaw: float, pitch: float, moving: bool, ghost: bool) -> void:
	remote_peer_state.emit(peer, pname, pos, yaw, pitch, moving, ghost)


func broadcast_peer_left(peer: int) -> void:
	peer_states.erase(peer)
	for p in _ids_except_self():
		rpc_peer_left.rpc_id(p, peer)


@rpc("authority", "call_remote", "reliable")
func rpc_peer_left(peer: int) -> void:
	remote_peer_left.emit(peer)


func broadcast_creatures(states: Array) -> void:
	for p in _ids_except_self():
		rpc_creatures.rpc_id(p, states)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_creatures(states: Array) -> void:
	for s in states:
		run.props.apply_remote_creature(int(s[0]), str(s[1]), int(s[2]), s[3], float(s[4]), bool(s[5]), bool(s[6]))


func broadcast_pickup_spawn(id: int, item: Dictionary, pos: Vector3) -> void:
	for p in _ids_except_self():
		rpc_pickup_spawn.rpc_id(p, id, item, pos)


@rpc("authority", "call_remote", "reliable")
func rpc_pickup_spawn(id: int, item: Dictionary, pos: Vector3) -> void:
	remote_pickup_spawn.emit(id, item, pos)


func broadcast_pickup_remove(id: int) -> void:
	for p in _ids_except_self():
		rpc_pickup_remove.rpc_id(p, id)


@rpc("authority", "call_remote", "reliable")
func rpc_pickup_remove(id: int) -> void:
	remote_pickup_remove.emit(id)


func broadcast_prop_harvested(cell: Vector2i, regrow_at: float, removed: bool) -> void:
	for p in _ids_except_self():
		rpc_prop_harvested.rpc_id(p, cell, regrow_at, removed)


@rpc("authority", "call_remote", "reliable")
func rpc_prop_harvested(cell: Vector2i, regrow_at: float, removed: bool) -> void:
	remote_prop_harvested.emit(cell, regrow_at, removed)


func broadcast_toast(text: String, seconds: float = 3.0) -> void:
	for p in _ids_except_self():
		rpc_toast.rpc_id(p, text, seconds)


@rpc("authority", "call_remote", "reliable")
func rpc_toast(text: String, seconds: float) -> void:
	EventBus.toast.emit(text, seconds)


func broadcast_ritual(state: Dictionary) -> void:
	for p in _ids_except_self():
		rpc_ritual.rpc_id(p, state)


@rpc("authority", "call_remote", "reliable")
func rpc_ritual(state: Dictionary) -> void:
	remote_ritual.emit(state)


func revive(peer: int, pos: Vector3) -> void:
	if peer == Net.local_id():
		remote_revive.emit(pos)
	else:
		rpc_revive.rpc_id(peer, pos)


@rpc("authority", "call_remote", "reliable")
func rpc_revive(pos: Vector3) -> void:
	remote_revive.emit(pos)


# =====================================================================
# clients -> server
# =====================================================================

func send_command(cmd: Dictionary) -> void:
	rpc_command.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func rpc_command(cmd: Dictionary) -> void:
	if not is_server():
		return
	cmd["peer"] = multiplayer.get_remote_sender_id()
	client_command.emit(cmd)


func send_my_state(pname: String, pos: Vector3, yaw: float, pitch: float, moving: bool, ghost: bool) -> void:
	if is_server():
		peer_states[Net.local_id()] = {"name": pname, "pos": pos, "yaw": yaw, "pitch": pitch, "moving": moving, "ghost": ghost}
		relay_peer_state(Net.local_id())
	else:
		rpc_my_state.rpc_id(1, pname, pos, yaw, pitch, moving, ghost)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_my_state(pname: String, pos: Vector3, yaw: float, pitch: float, moving: bool, ghost: bool) -> void:
	if not is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	peer_states[peer] = {"name": pname, "pos": pos, "yaw": yaw, "pitch": pitch, "moving": moving, "ghost": ghost}
	ghosts[peer] = ghost
	remote_peer_state.emit(peer, pname, pos, yaw, pitch, moving, ghost)
	relay_peer_state(peer)


func send_take_pickup(id: int) -> void:
	rpc_take_pickup.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_take_pickup(id: int) -> void:
	if is_server():
		client_take_pickup.emit(multiplayer.get_remote_sender_id(), id)


func send_drop(item: Dictionary, pos: Vector3) -> void:
	rpc_drop.rpc_id(1, item, pos)


@rpc("any_peer", "call_remote", "reliable")
func rpc_drop(item: Dictionary, pos: Vector3) -> void:
	if is_server():
		client_drop.emit(multiplayer.get_remote_sender_id(), item, pos)


func send_harvest(cell: Vector2i) -> void:
	rpc_harvest.rpc_id(1, cell)


@rpc("any_peer", "call_remote", "reliable")
func rpc_harvest(cell: Vector2i) -> void:
	if is_server():
		client_harvest.emit(multiplayer.get_remote_sender_id(), cell)


func send_attack(creature_id: int) -> void:
	rpc_attack.rpc_id(1, creature_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_attack(creature_id: int) -> void:
	if is_server():
		client_attack.emit(multiplayer.get_remote_sender_id(), creature_id)


func send_died(pos: Vector3, items: Array) -> void:
	if is_server():
		client_died.emit(Net.local_id(), pos, items)
	else:
		rpc_died.rpc_id(1, pos, items)


@rpc("any_peer", "call_remote", "reliable")
func rpc_died(pos: Vector3, items: Array) -> void:
	if is_server():
		client_died.emit(multiplayer.get_remote_sender_id(), pos, items)


func send_place_tag(cairn_pos: Vector3i, owner: int, owner_name: String) -> void:
	if is_server():
		client_place_tag.emit(Net.local_id(), cairn_pos, owner, owner_name)
	else:
		rpc_place_tag.rpc_id(1, cairn_pos, owner, owner_name)


@rpc("any_peer", "call_remote", "reliable")
func rpc_place_tag(cairn_pos: Vector3i, owner: int, owner_name: String) -> void:
	if is_server():
		client_place_tag.emit(multiplayer.get_remote_sender_id(), cairn_pos, owner, owner_name)
