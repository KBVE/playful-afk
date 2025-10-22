extends Node

## BackgroundManager - Centralized Background & Bounds Management
## Autoload singleton that manages safe zones and bounds for all NPCs
## Access via: BackgroundManager.is_in_safe_zone(pos) anywhere in your code

## Safe rectangle for NPC movement (calculated by active background)
var safe_rectangle: Rect2 = Rect2()

## Reference to the active background scene
var active_background: Control = null


func _ready() -> void:
	# Background will register itself when ready
	pass


## Called by background scenes to register themselves and update bounds
func register_background(background: Control) -> void:
	active_background = background

	# If background has a safe_rectangle, use it
	if "safe_rectangle" in background:
		safe_rectangle = background.safe_rectangle
		print("BackgroundManager: Registered background with safe zone: ", safe_rectangle)


## Check if position is in the safe rectangle (fastest check)
func is_in_safe_zone(pos: Vector2) -> bool:
	return safe_rectangle.has_point(pos)


## Get walkable Y bounds at a specific X position
## Returns Vector2(min_y, max_y) where NPCs can walk
func get_walkable_y_bounds(screen_x: float) -> Vector2:
	if active_background and active_background.has_method("get_walkable_y_bounds"):
		return active_background.get_walkable_y_bounds(screen_x)

	# Fallback: use safe rectangle bounds
	return Vector2(safe_rectangle.position.y, safe_rectangle.position.y + safe_rectangle.size.y)


## Get a random position within the safe zone
func get_random_safe_position() -> Vector2:
	if safe_rectangle.has_area():
		var random_x = randf_range(safe_rectangle.position.x, safe_rectangle.position.x + safe_rectangle.size.x)
		var random_y = randf_range(safe_rectangle.position.y, safe_rectangle.position.y + safe_rectangle.size.y)
		return Vector2(random_x, random_y)

	# Fallback: return origin
	push_warning("BackgroundManager: No safe zone defined, returning origin")
	return Vector2.ZERO


## Get a safe waypoint between start and target positions
func get_safe_waypoint(start_pos: Vector2, target_pos: Vector2) -> Vector2:
	if active_background and active_background.has_method("get_safe_waypoint"):
		return active_background.get_safe_waypoint(start_pos, target_pos)

	# Fallback: simple midpoint in safe zone
	var waypoint_x = lerp(start_pos.x, target_pos.x, 0.5)
	waypoint_x = clamp(waypoint_x, safe_rectangle.position.x, safe_rectangle.position.x + safe_rectangle.size.x)
	var waypoint_y = safe_rectangle.position.y + safe_rectangle.size.y * 0.5
	return Vector2(waypoint_x, waypoint_y)


## Check if position is in walkable area (uses background's method if available)
func is_position_walkable(pos: Vector2) -> bool:
	if active_background and active_background.has_method("is_position_in_walkable_area"):
		return active_background.is_position_in_walkable_area(pos)

	# Fallback: simple rectangle check
	return is_in_safe_zone(pos)
