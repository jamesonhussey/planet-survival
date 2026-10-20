class_name SaveSystem
extends RefCounted
## One save slot per run at user://saves/current.json plus a binary chunk
## file with only the *edited* chunks (the generator recreates the rest from
## the seed). Permadeath deletes the slot. Everything else that matters to
## a run (kit, body, vitals, clock, hazard schedule, pickups, harvested
## props) goes through to_dict()/from_dict() on the owning systems.

const DIR := "user://saves"
const META := "user://saves/current.json"
const CHUNKS := "user://saves/current.chunks"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(META)


static func summary() -> String:
	if not exists():
		return ""
	var d := _read_meta()
	return "planet %s, day %d" % [str(d.get("planet_id", "?")), int(d.get("clock", {}).get("day", 1))]


static func delete() -> void:
	if FileAccess.file_exists(META):
		DirAccess.remove_absolute(META)
	if FileAccess.file_exists(CHUNKS):
		DirAccess.remove_absolute(CHUNKS)


static func _read_meta() -> Dictionary:
	var f := FileAccess.open(META, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not (json.data is Dictionary):
		return {}
	return json.data


## `meta` is the run state dictionary; `world` supplies the edited chunks.
static func write(meta: Dictionary, world: WorldData) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	meta["version"] = VERSION
	meta["saved_at"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(META, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	var cf := FileAccess.open(CHUNKS, FileAccess.WRITE)
	if cf == null:
		return FileAccess.get_open_error()
	var edited := world.edited_chunks()
	cf.store_32(VERSION)
	cf.store_32(edited.size())
	for c in edited:
		cf.store_32(c.cpos.x)
		cf.store_32(c.cpos.y)
		cf.store_32(c.cpos.z)
		var packed := c.blocks.compress(FileAccess.COMPRESSION_ZSTD)
		cf.store_32(packed.size())
		cf.store_buffer(packed)
	cf.close()
	return OK


static func read_meta() -> Dictionary:
	return _read_meta()


## Edited chunks as {Vector3i: PackedByteArray}; applied by the run after
## the generator produced the base terrain.
static func read_chunks() -> Dictionary:
	var out: Dictionary = {}
	var cf := FileAccess.open(CHUNKS, FileAccess.READ)
	if cf == null:
		return out
	var version := cf.get_32()
	if version != VERSION:
		push_warning("[save] chunk file version %d != %d" % [version, VERSION])
	var n := cf.get_32()
	for i in n:
		var x := int(cf.get_32())
		var y := int(cf.get_32())
		var z := int(cf.get_32())
		# get_32 is unsigned; recover sign.
		if x >= 1 << 31: x -= 1 << 32
		if y >= 1 << 31: y -= 1 << 32
		if z >= 1 << 31: z -= 1 << 32
		var size := cf.get_32()
		var packed := cf.get_buffer(size)
		var blocks := packed.decompress(Chunk.VOLUME, FileAccess.COMPRESSION_ZSTD)
		if blocks.size() == Chunk.VOLUME:
			out[Vector3i(x, y, z)] = blocks
	cf.close()
	return out
