class_name Chunk
extends RefCounted
## 16x16x16 block storage. Index layout: (y * SIZE + z) * SIZE + x so that a
## horizontal slice is contiguous. Pure data; no nodes.

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

var cpos: Vector3i
var blocks: PackedByteArray
var dirty: bool = true        # needs remesh
var edited: bool = false      # differs from generator output (save this)
var solid_count: int = 0      # cached count of non-air blocks
var generated: bool = false


func _init(chunk_pos: Vector3i = Vector3i.ZERO) -> void:
	cpos = chunk_pos
	blocks = PackedByteArray()
	blocks.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x


func get_local(x: int, y: int, z: int) -> int:
	return blocks[(y * SIZE + z) * SIZE + x]


func set_local(x: int, y: int, z: int, id: int) -> void:
	var i := (y * SIZE + z) * SIZE + x
	var old := blocks[i]
	if old == id:
		return
	if old == 0:
		solid_count += 1
	elif id == 0:
		solid_count -= 1
	blocks[i] = id
	dirty = true


func is_empty() -> bool:
	return solid_count == 0


func recount() -> void:
	solid_count = 0
	for b in blocks:
		if b != 0:
			solid_count += 1


func origin() -> Vector3i:
	return cpos * SIZE
