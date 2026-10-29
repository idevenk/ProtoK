extends Node3D

@export var speed: float = 6.0
@export var lane_id: int = 1 # Set 1 for Lane 1 spawners, 2 for Lane 2 spawners

var is_stopped: bool = false
@export var stop_line_z: float = -2.0 # Adjust this to match your intersection stop line position

func _process(delta: float):
	var main_scene = get_tree().current_scene
	
	# Check if the main scene tracks light states
	if main_scene and "lane_1_green" in main_scene and "lane_2_green" in main_scene:
		var is_green = (lane_id == 1 and main_scene.lane_1_green) or (lane_id == 2 and main_scene.lane_2_green)
		
		# If we are approaching the stop line and light is RED, stop
		if not is_stopped and abs(position.z - stop_line_z) < 1.0 and not is_green:
			is_stopped = true
			
		# If we were stopped and the light turns GREEN, resume driving
		if is_stopped and is_green:
			is_stopped = false

	# Move forward only if not stopped by a red light
	if not is_stopped:
		translate(Vector3(0, 0, -speed * delta))
		
	# Clean up cars after they drive past the intersection
	if position.z < -30.0:
		queue_free()
