class_name GameClock
extends Node
## In-game time. `minutes_per_day` real minutes per in-game day. Emits day and
## hour changes through EventBus. Time scale is a debug/accessibility knob.

var minutes_per_day: float = 15.0
var time_scale: float = 1.0
var day: int = 1
var day_fraction: float = 0.33    # 0..1, 0 = midnight
var running: bool = true
var _last_hour: int = -1


func setup(cfg: Dictionary) -> void:
	minutes_per_day = float(cfg.get("minutes_per_day", 15.0))
	day_fraction = float(cfg.get("start_hour", 8)) / 24.0
	_last_hour = hour()


func _process(delta: float) -> void:
	if not running:
		return
	day_fraction += delta * time_scale / (minutes_per_day * 60.0)
	while day_fraction >= 1.0:
		day_fraction -= 1.0
		day += 1
		EventBus.day_changed.emit(day)
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		EventBus.hour_changed.emit(h)


func hour() -> int:
	return int(day_fraction * 24.0) % 24


## Continuous day count (e.g. 3.5 = noon of day 4) for escalation curves.
func day_time() -> float:
	return float(day - 1) + day_fraction


## Seconds of real time per in-game hour at the current time scale.
func seconds_per_hour() -> float:
	return minutes_per_day * 60.0 / 24.0 / maxf(time_scale, 0.0001)


func clock_text() -> String:
	var h := hour()
	var m := int(fmod(day_fraction * 24.0, 1.0) * 60.0)
	return "Day %d  %02d:%02d" % [day, h, m]
