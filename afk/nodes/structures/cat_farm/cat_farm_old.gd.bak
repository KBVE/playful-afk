extends Node2D
class_name CatFarm

## A cat farm structure that can be placed in parallax backgrounds
## Automatically handles sprite rendering, floating animation, and click detection
## Uses InputManager for efficient centralized input handling

signal farm_clicked

@onready var sprite: Sprite2D = $Sprite2D

## Floating animation properties
@export var float_amplitude: float = 3.0  ## How high/low it floats
@export var float_speed: float = 0.5  ## Speed of floating animation

## Fade properties
@export var distance_opacity: float = 0.6  ## Opacity when not hovered (distant)
@export var near_opacity: float = 1.0  ## Opacity when hovered (near)

## Click detection
@export var click_radius: float = 81.6  ## Radius for click/hover detection

var time_elapsed: float = 0.0
var initial_y_position: float = 0.0

func _ready() -> void:
	# Set up the sprite with the cat farm texture
	if sprite:
		sprite.centered = true
		sprite.scale = Vector2(1.0, 1.0)
		initial_y_position = sprite.position.y
		# Start with distance fade
		sprite.modulate.a = distance_opacity
		print("Cat Farm sprite initialized with opacity: ", distance_opacity)

	# Register with InputManager for efficient input handling
	if InputManager:
		InputManager.register_interactive_object(self, click_radius, self)
		print("Cat Farm registered with InputManager (radius: ", click_radius, ")")


func _exit_tree() -> void:
	# Unregister from InputManager when this node is removed
	if InputManager:
		InputManager.unregister_interactive_object(self)

func _process(delta: float) -> void:
	# Update floating animation
	time_elapsed += delta
	if sprite:
		sprite.position.y = initial_y_position + sin(time_elapsed * float_speed) * float_amplitude


## Called by InputManager when this object is clicked
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("CAT FARM CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	farm_clicked.emit()
	# Add a small bounce effect when clicked
	_play_click_animation()

	# Trigger camera pan and modal
	_show_farm_modal()


## Show the farm interaction modal
func _show_farm_modal() -> void:
	# Find the main scene to trigger camera pan
	var main_scene = get_tree().root.get_node_or_null("Main")
	if not main_scene:
		print("Warning: Could not find Main scene for camera pan")
		return

	# Pan camera to sky
	await main_scene.pan_camera_to_sky()

	# Create and show modal
	var modal = load("res://nodes/ui/modal/modal.tscn").instantiate()
	get_tree().root.add_child(modal)
	modal.set_title("Cat Farm")

	# Add placeholder content with the custom font
	var content_label = Label.new()
	content_label.text = "This is where you can manage your cats,\ncollect resources, and expand your farm.\n\n(More features coming soon...)"
	content_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Load and apply the alagard font
	var font = load("res://nodes/ui/fonts/alagard.ttf")
	content_label.add_theme_font_override("font", font)
	content_label.add_theme_font_size_override("font_size", 20)
	content_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))  # White text
	content_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))  # Black outline
	content_label.add_theme_constant_override("outline_size", 4)  # Outline thickness

	modal.set_content(content_label)

	# Connect modal close to camera pan back
	modal.modal_closed.connect(_on_modal_closed.bind(main_scene))

	modal.open()
	print("Farm modal opened")


## Called when the modal is closed
func _on_modal_closed(main_scene: Node) -> void:
	# Pan camera back to ground view
	if main_scene and main_scene.has_method("pan_camera_to_ground"):
		await main_scene.pan_camera_to_ground()
	print("Returned to ground view")

## Play a small bounce animation when clicked
func _play_click_animation() -> void:
	var tween = create_tween()
	var original_scale = sprite.scale
	tween.tween_property(sprite, "scale", original_scale * 1.2, 0.1)
	tween.tween_property(sprite, "scale", original_scale, 0.1)

## Called by InputManager when mouse enters this object
func _on_input_manager_hover_enter() -> void:
	print("Mouse ENTERED cat farm at position: ", global_position)
	# Remove fade and brighten when hovered (farm comes into focus)
	if sprite:
		print("  Current sprite modulate: ", sprite.modulate)
		print("  Target modulate: ", Color(1.1, 1.1, 1.1, near_opacity))
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.1, 1.1, 1.1, near_opacity), 0.2)

## Called by InputManager when mouse exits this object
func _on_input_manager_hover_exit() -> void:
	print("Mouse EXITED cat farm at position: ", global_position)
	# Return to faded distant appearance
	if sprite:
		print("  Current sprite modulate: ", sprite.modulate)
		print("  Target modulate: ", Color(1.0, 1.0, 1.0, distance_opacity))
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, distance_opacity), 0.2)

## Set the scale of the cat farm
func set_farm_scale(new_scale: Vector2) -> void:
	if sprite:
		sprite.scale = new_scale

## Get the bounds of the farm for collision or placement purposes
func get_farm_bounds() -> Rect2:
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(position - scaled_size / 2, scaled_size)
	return Rect2()
