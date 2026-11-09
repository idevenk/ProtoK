class_name CarSpawner
extends Node3D

@export var car_scenes: Array[PackedScene] = []
@export var car_scene_folder: String = "res://cars"
@export var spawn_markers: Array[Marker3D] = []
@export var traffic_lights: Array[IntersectionTrafficLight] = []

@export_group("Spawning")
@export var spawn_interval_min: float = 1.2
@export var spawn_interval_max: float = 2.8
@export var first_spawn_delay: float = 1.5

@export_group("Intersection")
@export var intersection_center: Vector3 = Vector3.ZERO
@export var stop_line_distance: float = 16.0
## 0 for models that face -Z, PI for models that face +Z.
@export var model_yaw_offset: float = 0.0

@export_group("Traffic light cycle")
@export var auto_cycle_lights: bool = true
@export var green_time: float = 12.0
@export var yellow_time: float = 3.0
@export var all_red_time: float = 3.0

var _spawn_timer: Timer
var _ns_lights: Array[IntersectionTrafficLight] = []
var _ew_lights: Array[IntersectionTrafficLight] = []

func _ready() -> void:
	_load_car_scenes()
	_discover_markers_and_lights()
	_split_lights_by_axis()

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = first_spawn_delay
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timeout)
	add_child(_spawn_timer)

	if auto_cycle_lights and not traffic_lights.is_empty():
		_cycle_lights()

func _load_car_scenes() -> void:
	if not car_scenes.is_empty():
		return
	var dir := DirAccess.open(car_scene_folder)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension() in ["tscn", "scn"]:
			var scene := load(car_scene_folder.path_join(file)) as PackedScene
			if scene != null:
				car_scenes.append(scene)

func _discover_markers_and_lights() -> void:
	if spawn_markers.is_empty():
		for node in get_tree().get_nodes_in_group("spawn_marker"):
			if node is Marker3D:
				spawn_markers.append(node)
	if traffic_lights.is_empty():
		for node in get_tree().get_nodes_in_group("traffic_light"):
			if node is IntersectionTrafficLight:
				traffic_lights.append(node)

func _is_north_south(pos: Vector3) -> bool:
	return absf(pos.z) >= absf(pos.x)

func _split_lights_by_axis() -> void:
	for light in traffic_lights:
		if _is_north_south(light.global_position):
			_ns_lights.append(light)
		else:
			_ew_lights.append(light)

func _on_spawn_timeout() -> void:
	_spawn_timer.wait_time = randf_range(spawn_interval_min, spawn_interval_max)
	spawn_random_car()

func spawn_random_car() -> void:
	if car_scenes.is_empty() or spawn_markers.is_empty():
		return

	var marker := spawn_markers[randi() % spawn_markers.size()]
	var scene := car_scenes[randi() % car_scenes.size()]
	var car := scene.instantiate() as Car
	if car == null:
		return

	get_tree().current_scene.add_child(car)

	var spawn_pos := marker.global_position
	spawn_pos.y = 0.0
	car.global_position = spawn_pos

	# Direction is ALWAYS toward the intersection, regardless of marker rotation.
	var to_centre := intersection_center - spawn_pos
	to_centre.y = 0.0
	var forward: Vector3
	if absf(to_centre.x) >= absf(to_centre.z):
		forward = Vector3(signf(to_centre.x), 0.0, 0.0)
	else:
		forward = Vector3(0.0, 0.0, signf(to_centre.z))

	# look_at points -Z along `forward`; add model_yaw_offset for +Z models.
	car.rotation.y = atan2(-forward.x, -forward.z) + model_yaw_offset

	# Stop line: pull back so the FRONT bumper sits `stop_line_distance` from
	# the intersection edge, before the crosswalk.
	var crossing := spawn_pos
	if absf(forward.x) > 0.5:
		crossing.x = intersection_center.x
	else:
		crossing.z = intersection_center.z

	var stop_center := crossing - forward * stop_line_distance
	stop_center.y = 0.0
	car.stop_position = stop_center - forward * (car.car_length * 0.5)

	car.target_light = _pick_light(spawn_pos)

func _pick_light(pos: Vector3) -> IntersectionTrafficLight:
	var group := _ns_lights if _is_north_south(pos) else _ew_lights
	return null if group.is_empty() else group[randi() % group.size()]

func _cycle_lights() -> void:
	while is_inside_tree():
		_set_lights(_ns_lights, IntersectionTrafficLight.State.GREEN)
		_set_lights(_ew_lights, IntersectionTrafficLight.State.RED)
		await _wait(green_time)

		_set_lights(_ns_lights, IntersectionTrafficLight.State.YELLOW_BLINK)
		await _wait(yellow_time)

		_set_lights(_ns_lights, IntersectionTrafficLight.State.RED)
		_set_lights(_ew_lights, IntersectionTrafficLight.State.RED)
		await _wait(all_red_time)

		_set_lights(_ew_lights, IntersectionTrafficLight.State.GREEN)
		_set_lights(_ns_lights, IntersectionTrafficLight.State.RED)
		await _wait(green_time)

		_set_lights(_ew_lights, IntersectionTrafficLight.State.YELLOW_BLINK)
		await _wait(yellow_time)

		_set_lights(_ew_lights, IntersectionTrafficLight.State.RED)
		_set_lights(_ns_lights, IntersectionTrafficLight.State.RED)
		await _wait(all_red_time)

func set_road_green(north_south_green: bool) -> void:
	_set_lights(_ns_lights, IntersectionTrafficLight.State.GREEN if north_south_green else IntersectionTrafficLight.State.RED)
	_set_lights(_ew_lights, IntersectionTrafficLight.State.RED if north_south_green else IntersectionTrafficLight.State.GREEN)

func _set_lights(lights: Array[IntersectionTrafficLight], state: IntersectionTrafficLight.State) -> void:
	for light in lights:
		if is_instance_valid(light):
			light.set_state(state)

func _wait(seconds: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout
