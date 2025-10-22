extends ParallaxBackground
class_name RedForestBackground

## RedForestBackground - Parallax background for the red forest theme
## Works with Camera2D for proper parallax scrolling
## Each layer scrolls at different speeds based on motion_scale

# Layer references
var layer1: ParallaxLayer
var layer2: ParallaxLayer
var layer3: ParallaxLayer


func _ready() -> void:
	# Get layer references
	layer1 = $Layer1
	layer2 = $Layer2
	layer3 = $Layer3

	# Scale the sprites to be larger and fill the viewport
	call_deferred("_scale_background_layers")


	# The parallax scrolling is now handled automatically by the Camera2D
	# Each layer's motion_scale determines how fast it scrolls relative to camera


func _scale_background_layers() -> void:
	# Get viewport to calculate proper scaling
	var viewport = get_viewport()
	if not viewport:
		return

	var viewport_size = viewport.get_visible_rect().size

	var sprite1 = layer1.get_node("Sprite2D") as Sprite2D
	var sprite2 = layer2.get_node("Sprite2D") as Sprite2D
	var sprite3 = layer3.get_node("Sprite2D") as Sprite2D

	# Scale each layer to fit viewport height perfectly
	_scale_sprite_to_viewport(sprite1, viewport_size)
	_scale_sprite_to_viewport(sprite2, viewport_size)
	_scale_sprite_to_viewport(sprite3, viewport_size)

	print("Background layers scaled to fit viewport: %s" % viewport_size)


func _scale_sprite_to_viewport(sprite: Sprite2D, viewport_size: Vector2) -> void:
	if not sprite or not sprite.texture:
		return

	var texture_size = sprite.texture.get_size()

	# Calculate scale to cover both width AND height (use the larger scale)
	var scale_x = viewport_size.x / texture_size.x
	var scale_y = viewport_size.y / texture_size.y

	# Use the larger scale to ensure full coverage in both dimensions
	# Add extra multiplier to ensure no gaps with parallax
	var final_scale = max(scale_x, scale_y) * 1.6  # 60% extra to cover parallax scrolling

	sprite.scale = Vector2(final_scale, final_scale)

	# Center the sprite in the viewport
	sprite.position = viewport_size / 2.0

	print("Sprite scaled: texture=%s, viewport=%s, scale=%s, pos=%s" % [texture_size, viewport_size, sprite.scale, sprite.position])
