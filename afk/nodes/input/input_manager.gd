extends Node

## InputManager - Centralized input handling system
## Manages click and hover detection for all interactive objects efficiently
## This prevents each object from doing expensive distance checks every frame

## Signals
signal object_clicked(object: Node2D)
signal object_hover_started(object: Node2D)
signal object_hover_ended(object: Node2D)

## Registered interactive objects
var interactive_objects: Array[Dictionary] = []

## Currently hovered object
var current_hovered_object: Node2D = null

## Modal management
var active_modals: Array[Node] = []
var input_blocked: bool = false

## Performance settings
@export var check_interval: float = 0.016  ## How often to check hover (60fps default)

var time_since_last_check: float = 0.0


func _ready() -> void:
	pass


## Register an object for click and hover detection
## radius: The click/hover detection radius in pixels
## callback_node: The node that will receive signals (usually the object itself)
func register_interactive_object(object: Node2D, radius: float, callback_node: Node = null) -> void:
	if callback_node == null:
		callback_node = object

	var data = {
		"object": object,
		"radius": radius,
		"callback_node": callback_node,
		"is_hovered": false
	}

	interactive_objects.append(data)


## Unregister an object (call this when the object is freed)
func unregister_interactive_object(object: Node2D) -> void:
	for i in range(interactive_objects.size() - 1, -1, -1):
		if interactive_objects[i]["object"] == object:
			interactive_objects.remove_at(i)
			break


func _process(delta: float) -> void:
	time_since_last_check += delta

	# Only check hover at the specified interval (performance optimization)
	# Skip if input is blocked by modals
	if time_since_last_check >= check_interval and not input_blocked:
		time_since_last_check = 0.0
		_check_hover_state()
	elif input_blocked and current_hovered_object != null:
		# If input becomes blocked, clear current hover
		_trigger_hover_exit(current_hovered_object)
		current_hovered_object = null


func _input(event: InputEvent) -> void:
	# ESC key always gets priority - allows closing modals even when input is blocked
	if event.is_action_pressed("ui_cancel"):
		_forward_escape_to_event_manager()
		return

	# Block all other input when modals are active
	if input_blocked:
		return

	# Handle mouse interactions
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)


## Forward ESC key press to EventManager for centralized handling
func _forward_escape_to_event_manager() -> void:
	print("InputManager: ESC detected → forwarding to EventManager")
	EventManager.handle_escape()
	get_viewport().set_input_as_handled()


## Check which object (if any) is currently being hovered
func _check_hover_state() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var found_hovered_object: Node2D = null
	var closest_distance: float = INF

	# Find the closest object under the mouse
	for data in interactive_objects:
		var obj: Node2D = data["object"]
		if not is_instance_valid(obj):
			continue

		var distance = obj.global_position.distance_to(mouse_pos)
		if distance <= data["radius"] and distance < closest_distance:
			closest_distance = distance
			found_hovered_object = obj

	# Check if hover state changed
	if found_hovered_object != current_hovered_object:
		# Mouse left previous object
		if current_hovered_object != null:
			_trigger_hover_exit(current_hovered_object)

		# Mouse entered new object
		if found_hovered_object != null:
			_trigger_hover_enter(found_hovered_object)

		current_hovered_object = found_hovered_object


## Handle click events
func _handle_click(click_position: Vector2) -> void:
	var closest_object: Node2D = null
	var closest_distance: float = INF

	# Find the closest object under the click
	for data in interactive_objects:
		var obj: Node2D = data["object"]
		if not is_instance_valid(obj):
			continue

		var distance = obj.global_position.distance_to(click_position)
		if distance <= data["radius"] and distance < closest_distance:
			closest_distance = distance
			closest_object = obj

	# Trigger click on the closest object
	if closest_object != null:
		_trigger_click(closest_object)


## Trigger hover enter for an object
func _trigger_hover_enter(obj: Node2D) -> void:
	# Find the object data
	for data in interactive_objects:
		if data["object"] == obj:
			data["is_hovered"] = true

			# Call the object's hover method if it exists
			var callback_node = data["callback_node"]
			if callback_node.has_method("_on_input_manager_hover_enter"):
				callback_node._on_input_manager_hover_enter()

			# Emit global signal
			object_hover_started.emit(obj)
			break


## Trigger hover exit for an object
func _trigger_hover_exit(obj: Node2D) -> void:
	# Find the object data
	for data in interactive_objects:
		if data["object"] == obj:
			data["is_hovered"] = false

			# Call the object's hover exit method if it exists
			var callback_node = data["callback_node"]
			if callback_node.has_method("_on_input_manager_hover_exit"):
				callback_node._on_input_manager_hover_exit()

			# Emit global signal
			object_hover_ended.emit(obj)
			break


## Trigger click on an object
func _trigger_click(obj: Node2D) -> void:
	# Find the object data
	for data in interactive_objects:
		if data["object"] == obj:
			# Call the object's click method if it exists
			var callback_node = data["callback_node"]
			if callback_node.has_method("_on_input_manager_clicked"):
				callback_node._on_input_manager_clicked()

			# Emit global signal
			object_clicked.emit(obj)
			print("InputManager: CLICK on ", obj.name)
			break


## Clean up invalid objects (objects that were freed)
func cleanup_invalid_objects() -> void:
	for i in range(interactive_objects.size() - 1, -1, -1):
		if not is_instance_valid(interactive_objects[i]["object"]):
			interactive_objects.remove_at(i)


## Register a modal - blocks input to interactive objects
func register_modal(modal: Node) -> void:
	if not active_modals.has(modal):
		active_modals.append(modal)
		input_blocked = true
		print("InputManager: Modal registered, input blocked (", active_modals.size(), " active modals)")


## Unregister a modal - restores input if no other modals are active
func unregister_modal(modal: Node) -> void:
	var index = active_modals.find(modal)
	if index != -1:
		active_modals.remove_at(index)

		# Only unblock input if no modals remain
		if active_modals.is_empty():
			input_blocked = false
			print("InputManager: All modals closed, input restored")
		else:
			print("InputManager: Modal unregistered (", active_modals.size(), " modals still active)")
