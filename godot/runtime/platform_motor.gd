extends CharacterBody2D
## 复用Godot原生移动/碰撞。脚点是权威世界数据的投影，不另建角色位置真相。
const Codec = preload("res://runtime/snapshot_codec.gd")
const WC = preload("res://runtime/world_codec.gd")
const TILE: int = 16
const SPEED: float = 96.0
const GRAVITY: float = 900.0
const JUMP_SPEED: float = 260.0
const MAX_FALL: float = 384.0
var _world
var _window: Rect2i

func _init() -> void:
	set_physics_process(false)
	collision_layer = 2
	collision_mask = 1
	safe_margin = 0.04
	floor_snap_length = 1.0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 28)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -14)
	add_child(collider)

func bind_world(world, window: Rect2i) -> Dictionary:
	if world == null or not is_inside_tree() or not world.rule_view().get("actor", {}).has("body_foot"):
		return Codec.reject("motor_binding")
	dispose()
	_world = world
	_window = window
	_world.committed.connect(_on_committed)
	_world.reloaded.connect(_sync_pose)
	_sync_pose()
	velocity = Vector2.ZERO
	return {"ok":true,"error":""}

func _sync_pose() -> void:
	if _world == null: return
	position = Vector2(_world.actor_body_foot() - _window.position * WC.BODY_UNITS) * float(TILE) / WC.BODY_UNITS

func _on_committed(_cells: Array) -> void:
	_sync_pose()

func step_motion(delta: float, axis: int, jump: bool) -> Dictionary:
	if _world == null or not is_inside_tree() or not Engine.is_in_physics_frame(): return Codec.reject("motor_requires_physics_frame")
	if not is_finite(delta) or delta <= 0.0 or delta > 1.0 / 20.0 or axis < -1 or axis > 1: return Codec.reject("motor_step")
	var old_position: Vector2 = position
	velocity.x = axis * SPEED
	# is_on_floor缓存来自上次move_and_slide；载入/挖掘后必须重新确认脚下支撑。
	if jump and is_on_floor() and test_move(global_transform, Vector2(0, 0.25)): velocity.y = -JUMP_SPEED
	velocity.y = minf(MAX_FALL, velocity.y + GRAVITY * delta)
	move_and_slide()
	var target := Vector2i(roundi(position.x * WC.BODY_UNITS / TILE), roundi(position.y * WC.BODY_UNITS / TILE)) + _window.position * WC.BODY_UNITS
	var view_actor: Dictionary = {"body_foot":[target.x,target.y]}
	for cell: Vector2i in WC.actor_cells(view_actor):
		if not _window.has_point(cell):
			position = old_position; velocity = Vector2.ZERO
			return {"ok":true,"error":"","blocked":"unloaded_region"}
	var result: Dictionary = _world.move_actor_body(target)
	if not result.ok:
		position = old_position
		velocity = Vector2.ZERO
		if result.error in ["actor_collision", "deep_water", "coordinate_range"]:
			return {"ok":true,"error":"","blocked":result.error}
		return result
	_sync_pose()
	return {"ok":true,"error":"","blocked":""}

func motion_value() -> Dictionary:
	# 速度用整数1/64像素/秒保存，保持已有JSON整数协议。
	return {"velocity_x":roundi(velocity.x * 64.0),"velocity_y":roundi(velocity.y * 64.0)}

static func valid_motion(value: Variant) -> bool:
	return Codec._shape(value,["velocity_x","velocity_y"]) and Codec._integer(value.velocity_x,-6144,6144) and Codec._integer(value.velocity_y,-16640,24576)

func restore_motion(value: Dictionary) -> void:
	_sync_pose()
	velocity = Vector2(int(value.velocity_x),int(value.velocity_y)) / 64.0

func dispose() -> void:
	if _world != null:
		if _world.committed.is_connected(_on_committed): _world.committed.disconnect(_on_committed)
		if _world.reloaded.is_connected(_sync_pose): _world.reloaded.disconnect(_sync_pose)
	_world = null
