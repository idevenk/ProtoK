class_name AiTrafficController
extends Node

## Captures a snapshot of the intersection and sends it to an external AI
## service over HTTP. The service returns the number of cars in each lane and
## which traffic light should be lit; this node applies that decision.
##
## Disabled by default so the project still runs standalone with the timed
## light cycle. Turn `enabled` on (and set `endpoint`) once your service is up.
##
## Expected response (JSON object):
##   {
##     "lane_counts": { "north": 3, "south": 1, "east": 0, "west": 2 },
##     "light_states": { "Trafic light 1": "green", "Trafic light 2": "red", ... }
##   }
## Both keys are optional: `light_states` names each traffic light directly,
## while `lane_counts` falls back to giving the busier road the green.

@export var enabled: bool = false
## URL of the detection service (must accept an HTTP POST with a JSON body).
@export var endpoint: String = "http://127.0.0.1:8000/detect"
## How often to send a snapshot, in seconds.
@export var request_interval: float = 2.0
## Offscreen viewport whose image is sent to the service.
@export var capture_viewport: SubViewport
## The spawner that owns the traffic lights.
@export var car_spawner: CarSpawner
## "jpg" (smaller) or "png" (lossless).
@export var image_format: String = "jpg"
@export_range(0.1, 1.0) var jpg_quality: float = 0.75
## Save each captured frame under user://ai_snapshots/ for debugging.
@export var save_debug_snapshots: bool = false
@export var verbose_logging: bool = true

var _http: HTTPRequest
var _timer: Timer
var _request_in_flight: bool = false
var _shot_index: int = 0

func _ready() -> void:
	_resolve_refs()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_timer = Timer.new()
	_timer.wait_time = maxf(0.5, request_interval)
	_timer.timeout.connect(_send_snapshot)
	add_child(_timer)

	# TEMP DIAGNOSTIC
	var diag := Timer.new()
	diag.wait_time = 1.5
	diag.one_shot = true
	diag.timeout.connect(_write_diag)
	add_child(diag)
	diag.start()

	if not enabled:
		if verbose_logging:
			print("[AiTrafficController] disabled -> using the timed light cycle. viewport=", capture_viewport, " spawner=", car_spawner)
		return

	# The AI drives the lights, so switch off the built-in timed cycle.
	if car_spawner != null:
		car_spawner.auto_cycle_lights = false
	_timer.start()

## Fall back to sensible defaults if the references weren't set in the editor.
func _resolve_refs() -> void:
	if capture_viewport == null:
		capture_viewport = get_node_or_null("CaptureViewport") as SubViewport
	if car_spawner == null:
		car_spawner = get_tree().get_first_node_in_group("car_spawner") as CarSpawner

func _send_snapshot() -> void:
	if _request_in_flight or capture_viewport == null:
		return
	var image := capture_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	if save_debug_snapshots:
		_save_debug_image(image)

	var buffer: PackedByteArray
	var mime := "image/jpeg"
	if image_format == "png":
		buffer = image.save_png_to_buffer()
		mime = "image/png"
	else:
		buffer = image.save_jpg_to_buffer(jpg_quality)

	var payload := {
		"image": Marshalls.raw_to_base64(buffer),
		"mime": mime,
		"width": image.get_width(),
		"height": image.get_height(),
		"lanes": ["north", "south", "east", "west"],
		"traffic_lights": _light_names(),
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		push_warning("[AiTrafficController] could not start request (error %d)." % err)
		return
	_request_in_flight = true

func _save_debug_image(image: Image) -> void:
	var dir := "user://ai_snapshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var ext := "png" if image_format == "png" else "jpg"
	image.save_png("%s/shot_%04d.png" % [dir, _shot_index]) if ext == "png" else image.save_jpg("%s/shot_%04d.jpg" % [dir, _shot_index], jpg_quality)
	_shot_index += 1

func _light_names() -> Array:
	var names: Array = []
	if car_spawner != null:
		for light in car_spawner.get_lights():
			names.append(light.name)
	return names

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if verbose_logging:
			push_warning("[AiTrafficController] bad response (result %d, code %d)." % [result, response_code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[AiTrafficController] response was not a JSON object.")
		return
	_apply_decision(data)

func _apply_decision(data: Dictionary) -> void:
	if car_spawner == null:
		return

	# Preferred: the AI names each traffic light and the state it should show.
	var states = data.get("light_states", {})
	if states is Dictionary and not states.is_empty():
		for light in car_spawner.get_lights():
			if states.has(light.name):
				light.set_state(_state_from_string(str(states[light.name])))

	# Fallback: per-lane car counts -> give the busier road the green.
	var counts = data.get("lane_counts", {})
	if counts is Dictionary and not counts.is_empty():
		_apply_counts(counts)

	if verbose_logging:
		print("[AiTrafficController] decision: ", data)

func _apply_counts(counts: Dictionary) -> void:
	var ns := int(counts.get("north", 0)) + int(counts.get("south", 0))
	var ew := int(counts.get("east", 0)) + int(counts.get("west", 0))
	car_spawner.set_road_green(ns >= ew)

func _write_diag() -> void:
	var txt := "viewport=%s\nspawner=%s\n" % [capture_viewport, car_spawner]
	if capture_viewport != null:
		var vp: SubViewport = capture_viewport
		var img: Image = vp.get_texture().get_image()
		if img == null:
			txt += "image=null\n"
		else:
			var sz := img.get_size()
			var nonblack := 0
			var y := 0
			while y < sz.y:
				var x := 0
				while x < sz.x:
					var c := img.get_pixel(x, y)
					if c.r + c.g + c.b > 0.05:
						nonblack += 1
					x += 16
				y += 16
			txt += "image=%dx%d nonblack_samples=%d\n" % [sz.x, sz.y, nonblack]
	var f := FileAccess.open("user://ai_diag.txt", FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()

func _state_from_string(value: String) -> IntersectionTrafficLight.State:
	match value.to_lower():
		"green":
			return IntersectionTrafficLight.State.GREEN
		"yellow", "amber":
			return IntersectionTrafficLight.State.YELLOW
		_:
			return IntersectionTrafficLight.State.RED
