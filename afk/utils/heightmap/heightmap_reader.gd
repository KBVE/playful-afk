extends RefCounted
class_name HeightmapReader

## Heightmap Reader Utility
## Converts 2D heightmap data (extracted from background images) into walkable Y bounds
## Used for accurate terrain-following NPC movement
##
## Usage:
##   var heightmap = HeightmapReader.new(HEIGHTMAP_DATA, image_width, image_height)
##   var y_bounds = heightmap.get_walkable_y_bounds(screen_x, viewport_size)

## Heightmap data: Dictionary mapping X coordinates to Y values
var heightmap_data: Dictionary = {}

## Original image dimensions (before scaling to screen)
var image_width: int = 640
var image_height: int = 384

## Sample interval used when extracting heightmap (default 10px)
var sample_interval: int = 10

## Margin around the walkable line for movement variation (±pixels)
var walkable_margin: float = 20.0

## Tile scale if background uses tiling (set to 1.0 for non-tiling backgrounds)
var tile_scale: float = 3.0


func _init(heightmap: Dictionary, img_width: int = 640, img_height: int = 384) -> void:
	heightmap_data = heightmap
	image_width = img_width
	image_height = img_height


## Get walkable Y bounds at a specific screen X position
## Returns Vector2(min_y, max_y) where entities can walk
## Handles coordinate conversion, interpolation, and scaling
func get_walkable_y_bounds(screen_x: float, viewport_size: Vector2) -> Vector2:
	# Convert screen X to tiling background space (considering parallax)
	var bg_x = fposmod(screen_x, image_width * tile_scale) / tile_scale

	# Find nearest heightmap samples
	var x1 = int(bg_x / sample_interval) * sample_interval  # Floor to nearest sample
	var x2 = x1 + sample_interval  # Next sample

	# Clamp to valid range
	var max_x = (image_width / sample_interval) * sample_interval
	x1 = clamp(x1, 0, max_x)
	x2 = clamp(x2, 0, max_x)

	# Get Y values from heightmap (with default fallback)
	var default_y = image_height / 2.0  # Default to middle if data missing
	var y1 = heightmap_data.get(x1, default_y)
	var y2 = heightmap_data.get(x2, default_y)

	# Interpolate between samples for smooth curve
	var t = (bg_x - x1) / float(sample_interval)
	var walkable_y = lerp(y1, y2, t)

	# Convert from image space to screen space
	var scale_y = viewport_size.y / float(image_height)
	var screen_y = walkable_y * scale_y

	# Return range around the walkable line (±margin for variety)
	return Vector2(screen_y - walkable_margin, screen_y + walkable_margin)


## Set tile scale for backgrounds that use tiling shaders
func set_tile_scale(scale: float) -> void:
	tile_scale = scale


## Set walkable margin (how much vertical variation allowed)
func set_walkable_margin(margin: float) -> void:
	walkable_margin = margin


## Get the exact walkable Y at a specific X (without margin)
## Useful for precise positioning
func get_exact_walkable_y(screen_x: float, viewport_size: Vector2) -> float:
	var bounds = get_walkable_y_bounds(screen_x, viewport_size)
	return (bounds.x + bounds.y) / 2.0  # Return center of range


## Get statistics about the heightmap
func get_heightmap_stats() -> Dictionary:
	if heightmap_data.is_empty():
		return {"min_y": 0, "max_y": 0, "range": 0, "sample_count": 0}

	var y_values = heightmap_data.values()
	var min_y = y_values.min()
	var max_y = y_values.max()

	return {
		"min_y": min_y,
		"max_y": max_y,
		"range": max_y - min_y,
		"sample_count": heightmap_data.size(),
		"sample_interval": sample_interval
	}
