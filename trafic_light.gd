class_name IntersectionTrafficLight
extends Node3D

enum State { RED, YELLOW, GREEN, YELLOW_BLINK }

var current_state: State = State.RED
var _state_serial: int = 0

@onready var red_light: Light3D = $Red
@onready var yellow_light: Light3D = $Yellow
@onready var green_light: Light3D = $Green

func _ready() -> void:
	set_state(State.RED)

func set_state(new_state: State) -> void:
	_state_serial += 1
	current_state = new_state

	_show_only(null)

	match new_state:
		State.RED:          _show_only(red_light)
		State.YELLOW:       _show_only(yellow_light)
		State.GREEN:        _show_only(green_light)
		State.YELLOW_BLINK: _blink_yellow_loop(_state_serial)

func is_green() -> bool:
	return current_state == State.GREEN

func _show_only(lamp: Light3D) -> void:
	if red_light:    red_light.visible    = (lamp == red_light)
	if yellow_light: yellow_light.visible = (lamp == yellow_light)
	if green_light:  green_light.visible  = (lamp == green_light)

func _blink_yellow_loop(serial: int) -> void:
	while serial == _state_serial:
		_show_only(yellow_light)
		await get_tree().create_timer(0.5).timeout
		if serial != _state_serial: return
		_show_only(null)
		await get_tree().create_timer(0.5).timeout
