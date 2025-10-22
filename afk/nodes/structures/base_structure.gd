extends Node2D
class_name BaseStructure

## Base class for all interactive structures
## Handles common functionality like floating animation, click detection, and modal opening
## Child classes only need to define their name and description

## Structure Level - determines vertical placement
enum StructureLevel {
	GROUND = 1,   ## Base location on the ground
	ELEVATED = 2, ## Higher up, more Y offset
	SKY = 3       ## Up in the sky layer
}

## Structure Type - bitwise flags for categorization and spawning
enum StructureType {
	NONE = 0,
	SPAWN = 1,    ## Included in starting scene
	DEFENSE = 2,  ## Defensive structure
	TOWN = 4,     ## Town/settlement structure
	FARM = 8,     ## Resource farming structure
	CASTLE = 16,  ## Castle/fortress structure
}

signal structure_clicked

@onready var sprite: Sprite2D = $Sprite2D

## Structure properties (override in child classes)
@export var structure_name: String = "Structure"
@export var structure_description: String = "This is a structure."
@export var structure_level: StructureLevel = StructureLevel.GROUND  ## Default to ground level
@export_flags("SPAWN", "DEFENSE", "TOWN", "FARM", "CASTLE") var structure_types: int = 0  ## Bitwise flags

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
	# Set up the sprite
	if sprite:
		sprite.centered = true
		sprite.scale = Vector2(1.0, 1.0)
		initial_y_position = sprite.position.y
		# Start with distance fade
		sprite.modulate.a = distance_opacity
		print(structure_name, " initialized with opacity: ", distance_opacity)

	# Register with InputManager for efficient input handling
	if InputManager:
		InputManager.register_interactive_object(self, click_radius, self)
		print(structure_name, " registered with InputManager (radius: ", click_radius, ")")

	# Log structure metadata
	print(structure_name, " - Level: ", structure_level, ", Types: ", _get_type_names())


func _exit_tree() -> void:
	# Unregister from InputManager when this node is removed
	if InputManager:
		InputManager.unregister_interactive_object(self)


func _process(delta: float) -> void:
	# Update floating animation
	time_elapsed += delta
	if sprite:
		sprite.position.y = initial_y_position + sin(time_elapsed * float_speed) * float_amplitude


## Called by InputManager when this structure is clicked
func _on_input_manager_clicked() -> void:
	structure_clicked.emit()

	# Add a small bounce effect when clicked
	_play_click_animation()

	# Delegate to StructureManager for modal handling
	if StructureManager:
		StructureManager.handle_structure_click(self, structure_name, structure_description)


## Called by InputManager when mouse enters this structure
func _on_input_manager_hover_enter() -> void:
	print("Mouse ENTERED ", structure_name, " at position: ", global_position)
	# Remove fade and brighten when hovered (structure comes into focus)
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.1, 1.1, 1.1, near_opacity), 0.2)


## Called by InputManager when mouse exits this structure
func _on_input_manager_hover_exit() -> void:
	print("Mouse EXITED ", structure_name, " at position: ", global_position)
	# Return to faded distant appearance
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, distance_opacity), 0.2)


## Play a small bounce animation when clicked
func _play_click_animation() -> void:
	if sprite:
		var tween = create_tween()
		var original_scale = sprite.scale
		tween.tween_property(sprite, "scale", original_scale * 1.2, 0.1)
		tween.tween_property(sprite, "scale", original_scale, 0.1)


## Set the scale of the structure
func set_structure_scale(new_scale: Vector2) -> void:
	if sprite:
		sprite.scale = new_scale


## Get the bounds of the structure for collision or placement purposes
func get_structure_bounds() -> Rect2:
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(position - scaled_size / 2, scaled_size)
	return Rect2()


## Check if structure has a specific type flag
func has_type(type: StructureType) -> bool:
	return (structure_types & type) != 0


## Check if structure should spawn in starting scene
func is_spawn_structure() -> bool:
	return has_type(StructureType.SPAWN)


## Get human-readable type names for debugging
func _get_type_names() -> String:
	if structure_types == 0:
		return "NONE"

	var type_names: Array[String] = []
	if has_type(StructureType.SPAWN):
		type_names.append("SPAWN")
	if has_type(StructureType.DEFENSE):
		type_names.append("DEFENSE")
	if has_type(StructureType.TOWN):
		type_names.append("TOWN")
	if has_type(StructureType.FARM):
		type_names.append("FARM")
	if has_type(StructureType.CASTLE):
		type_names.append("CASTLE")

	return " | ".join(type_names)
