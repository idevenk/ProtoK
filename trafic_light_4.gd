class_name SimpleTrafficLight
extends Node3D

enum State { RED, YELLOW, GREEN }
var current_state: State = State.RED

@export var red_light: MeshInstance3D
@export var yellow_light: MeshInstance3D
@export var green_light: MeshInstance3D

func set_state(new_state: State) -> void:
	current_state = new_state
	
	# Turn off all lights
	if red_light: red_light.visible = false
	if yellow_light: yellow_light.visible = false
	if green_light: green_light.visible = false
	
	# Turn on active light
	match current_state:
		State.RED:
			if red_light: red_light.visible = true
		State.YELLOW:
			if yellow_light: yellow_light.visible = true
		State.GREEN:
			if green_light: green_light.visible = true

func is_green() -> bool:
	return current_state == State.GREEN
