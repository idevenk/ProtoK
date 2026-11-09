class_name Car
extends CharacterBody3D

@export var speed: float = 7.0
@export var despawn_distance: float = 120.0
@export var car_length: float = 4.0
@export var follow_gap: float = 2.5
@export var stop_distance: float = 2.0

var target_light: IntersectionTrafficLight = null
var stop_position: Vector3 = Vector3.ZERO

func _physics_process(_delta: float) -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	var must_stop := _should_stop_at_light(fwd)
	var gap := 999.0 if must_stop else _gap_to_car_ahead(fwd)

	var target_speed := 0.0
	if not must_stop and gap >= follow_gap * 3.0:
		target_speed = speed
	elif not must_stop:
		target_speed = speed * clampf(gap / (follow_gap * 3.0), 0.0, 1.0)

	velocity = fwd * target_speed
	move_and_slide()

	if global_position.length() > despawn_distance:
		queue_free()

func _should_stop_at_light(fwd: Vector3) -> bool:
	if target_light == null or target_light.is_green():
		return false
	var bumper := global_position + fwd * (car_length * 0.5)
	var to_line := stop_position - bumper
	var along := to_line.dot(fwd)
	# Only stop when the bumper is still before the line and within range.
	return along > -1.0 and along < stop_distance + 6.0

func _gap_to_car_ahead(fwd: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var start := global_position + Vector3.UP * 0.5
	var end := start + fwd * (car_length + follow_gap + 8.0)

	var q := PhysicsRayQueryParameters3D.create(start, end)
	q.exclude = [self]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is Car):
		return 999.0

	var other: Car = hit.collider
	var offset := other.global_position - global_position
	# Only count cars actually ahead in our lane (ignore opposite direction).
	var along := offset.dot(fwd)
	if along <= 0.0:
		return 999.0
	var lateral := (offset - fwd * along).length()
	if lateral > 2.0:
		return 999.0
	return along - (car_length + other.car_length) * 0.5
