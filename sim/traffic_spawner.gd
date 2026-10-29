extends Node3D

@export var car_scenes: Array[PackedScene] = [] # Drop multiple car scenes here in the Inspector
@export var spawn_interval: float = 1.5 
@export var speed_variation: float = 2.0

var timer: float = 0.0

func _process(delta: float):
	timer += delta
	if timer >= spawn_interval:
		timer = 0.0
		spawn_car()

func spawn_car():
	if car_scenes.is_empty():
		print("Error: No car scenes assigned in the spawner array!")
		return
		
	# Pick a random car scene from your list
	var random_scene = car_scenes.pick_random()
	var car = random_scene.instantiate()
	
	# Spawn at the spawner's position with a slight horizontal offset across the lane
	var random_offset_x = randf_range(-0.5, 0.5)
	car.position = global_position + Vector3(random_offset_x, 0, 0)
	
	# Randomize speed if the car has a speed property
	if "speed" in car:
		car.speed += randf_range(-speed_variation, speed_variation)
		
	# Add the car to the main scene tree
	get_tree().current_scene.add_child(car)
