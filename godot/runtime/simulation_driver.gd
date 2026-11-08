extends Node
## 以宿主物理帧驱动固定模拟步；无UI、无后台线程、无离线补算。
signal fault(reason: String)
const Codec = preload("res://runtime/snapshot_codec.gd")
var _runtime
var _seconds_per_tick: float = 0.1
var _accumulator: float = 0.0
func _init() -> void: set_physics_process(false)
func bind_runtime(runtime, ticks_per_second: Variant = 10) -> Dictionary:
	if runtime == null or not runtime.has_method("advance_tick") or not runtime.has_method("clock_state") or runtime.clock_state().is_empty() or typeof(ticks_per_second) != TYPE_INT or ticks_per_second < 1 or ticks_per_second > 60:
		return Codec.reject("invalid_driver_binding")
	_runtime = runtime
	_seconds_per_tick = 1.0 / ticks_per_second
	_accumulator = 0.0
	set_physics_process(true)
	return {"ok":true,"error":""}
func process_delta(delta: Variant) -> Dictionary:
	if (typeof(delta) != TYPE_FLOAT and typeof(delta) != TYPE_INT) or not is_finite(float(delta)) or delta < 0:
		return Codec.reject("invalid_frame_delta")
	if _runtime == null: return Codec.reject("driver_not_bound")
	var clock: Dictionary = _runtime.clock_state()
	if clock.is_empty():
		_accumulator = 0.0
		set_physics_process(false)
		return Codec.reject("driver_clock_unavailable")
	if clock.paused:
		_accumulator = 0.0
		return {"ok":true,"error":"","steps":0,"dropped_seconds":float(delta)}
	var accepted: float = minf(float(delta), _seconds_per_tick * 4.0)
	var dropped: float = float(delta) - accepted
	_accumulator += accepted
	var count: int = 0
	while _accumulator + 0.000000001 >= _seconds_per_tick and count < 4:
		var result: Dictionary = _runtime.advance_tick()
		if not result.ok:
			_accumulator = 0.0
			set_physics_process(false)
			return {"ok":false,"error":result.error,"steps":count}
		_accumulator = maxf(0.0, _accumulator - _seconds_per_tick)
		count += 1
	return {"ok":true,"error":"","steps":count,"dropped_seconds":dropped}
func _physics_process(delta: float) -> void:
	var result: Dictionary = process_delta(delta)
	if not result.ok: fault.emit(result.error)
func dispose() -> void:
	set_physics_process(false)
	_runtime = null
	_accumulator = 0.0

func reset_accumulator() -> void:
	_accumulator = 0.0
