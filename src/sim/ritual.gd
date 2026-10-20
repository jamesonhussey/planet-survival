class_name Ritual
extends RefCounted
## The Revival Ritual rules (same on every planet). A dead player's Tag is
## placed on a Cairn; a fire must keep burning within reach of the cairn
## through one full night; then the owner of the tag returns. Pure logic:
## the run feeds it clock time and the state of the blocks around the cairn.
##
## Night coverage is accumulated only while a heat source is present, so a
## fire that goes out resets nothing but pauses the vigil; the ritual fails
## only if the cairn itself is destroyed.

var cairn_pos: Vector3i
var tag_owner: int                 # peer id of the dead player
var started_day_time: float
var night_needed: float = 1.0      # fraction of a night that must be covered (1 = a full night)
var night_covered: float = 0.0
var fire_present: bool = false
var complete: bool = false
var failed: bool = false
var fail_reason: String = ""
var revives_so_far: int = 0


func _init(pos: Vector3i, owner: int, day_time: float, previous_revives: int = 0) -> void:
	cairn_pos = pos
	tag_owner = owner
	started_day_time = day_time
	revives_so_far = previous_revives
	# Each revive this run asks for a longer vigil (1, 1.25, 1.5 nights ...).
	night_needed = 1.0 + 0.25 * previous_revives


## `dt_days` elapsed since last tick in days; `is_night` from the clock;
## `fire` whether a lit heat source is within range; `cairn_intact` whether
## the cairn block still stands. Returns true when the ritual completes.
func tick(dt_days: float, is_night: bool, fire: bool, cairn_intact: bool) -> bool:
	if complete or failed:
		return complete
	if not cairn_intact:
		failed = true
		fail_reason = "the cairn was destroyed"
		return false
	fire_present = fire
	if is_night and fire:
		# A night is ~40% of a day (sun below -6 degrees).
		night_covered += dt_days / 0.4
		if night_covered >= night_needed:
			complete = true
	return complete


func progress() -> float:
	return clampf(night_covered / maxf(night_needed, 0.01), 0.0, 1.0)


## What the revived player comes back with.
static func revive_state() -> Dictionary:
	return {"max_hp_factor": 0.6, "hp_factor": 0.5, "hunger": 0.5, "thirst": 0.5}
