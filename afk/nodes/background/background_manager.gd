extends Node

## BackgroundManager - Simple Rectangle Bounds for NPCs
## Autoload singleton that manages a simple rectangular safe zone
## Access via: BackgroundManager.clamp_to_bounds(pos) anywhere in your code

## Simple rectangle bounds - 4 values: min_x, max_x, min_y, max_y
var min_x: float = -200.0
var max_x: float = 1280.0
var min_y: float = 510.0  # Top of playable area (just below UI fold at ~514)
var max_y: float = 650.0  # Bottom of visible viewport

## Reference to the active background scene
var active_background: Control = null


func _ready() -> void:
	# Background will register itself when ready
	pass


## Called by background scenes to register themselves and update bounds
func register_background(background: Control) -> void:
	active_background = background

	# NOTE: safe_rectangle was giving incorrect bounds (too small Y range)
	# Using fixed defaults instead for now
	# TODO: Fix safe_rectangle in background scenes or use a different bounds property
	print("BackgroundManager: Using default bounds X(%f to %f), Y(%f to %f)" % [min_x, max_x, min_y, max_y])


## Check if position is in bounds
func is_in_safe_zone(pos: Vector2) -> bool:
	return pos.x >= min_x and pos.x <= max_x and pos.y >= min_y and pos.y <= max_y


## Clamp position to bounds (move NPC back into safe zone if outside)
func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, min_x, max_x),
		clamp(pos.y, min_y, max_y)
	)


## Get walkable Y bounds (for compatibility with existing code)
func get_walkable_y_bounds(_screen_x: float) -> Vector2:
	return Vector2(min_y, max_y)


## Get a random position within the safe zone
func get_random_safe_position() -> Vector2:
	return Vector2(
		randf_range(min_x, max_x),
		randf_range(min_y, max_y)
	)
