extends Node

## StructureManager - Centralized management for all interactive structures
## Handles click debouncing, modal management, and camera panning
## Ensures only one structure can be interacted with at a time

## Signals
signal structure_clicked(structure: Node2D)
signal structure_modal_opened(structure: Node2D)
signal structure_modal_closed(structure: Node2D)

## State management
var is_modal_open: bool = false
var current_structure: Node2D = null
var is_transitioning: bool = false

## Click debouncing
var click_debounce_time: float = 0.5  # Seconds between allowed clicks
var time_since_last_click: float = 0.0

## Structure positioning system
var registered_structures: Array[Node2D] = []
var structure_spacing: float = 230.0  # Minimum horizontal spacing between structures (reduced for more structures)
var ground_y_variance: float = 20.0  # Random Y variance for natural look
var start_x: float = 100.0  # Starting X position for first structure
var viewport_width: float = 1152.0  # Screen width
var structure_scale: float = 1.5  # Scale for all structures

## Y positions for different structure levels
var level_y_positions: Dictionary = {
	BaseStructure.StructureLevel.GROUND: 380.0,    # Base ground level
	BaseStructure.StructureLevel.ELEVATED: 280.0,  # Higher up (100px higher)
	BaseStructure.StructureLevel.SKY: 100.0        # Sky layer (280px higher)
}


func _ready() -> void:
	print("StructureManager initialized")


func _process(delta: float) -> void:
	# Update debounce timer
	if time_since_last_click > 0:
		time_since_last_click -= delta


## Check if a structure can be clicked
func can_interact() -> bool:
	# Can't interact if modal is open
	if is_modal_open:
		print("StructureManager: Cannot interact - modal is open")
		return false

	# Can't interact if transitioning (camera panning)
	if is_transitioning:
		print("StructureManager: Cannot interact - transition in progress")
		return false

	# Can't interact if still in debounce period
	if time_since_last_click > 0:
		print("StructureManager: Cannot interact - debounce period (", time_since_last_click, "s remaining)")
		return false

	return true


## Handle structure click (called by individual structures)
func handle_structure_click(structure: Node2D, structure_name: String, structure_description: String) -> void:
	if not can_interact():
		return

	print("========================================")
	print("StructureManager: Structure clicked - ", structure_name)
	print("========================================")

	# Set debounce
	time_since_last_click = click_debounce_time

	# Store current structure
	current_structure = structure

	# Emit signal
	structure_clicked.emit(structure)

	# Open modal with camera pan
	_open_structure_modal(structure_name, structure_description)


## Open the modal for a structure
func _open_structure_modal(structure_name: String, structure_description: String) -> void:
	# Find the main scene to trigger camera pan
	var main_scene = get_tree().root.get_node_or_null("Main")
	if not main_scene:
		push_error("StructureManager: Could not find Main scene for camera pan")
		return

	# Mark as transitioning
	is_transitioning = true

	# Pan camera to sky
	await main_scene.pan_camera_to_sky()

	# Mark transition complete, modal opening
	is_transitioning = false
	is_modal_open = true

	# Create and show modal
	var modal = load("res://nodes/ui/modal/modal.tscn").instantiate()
	get_tree().root.add_child(modal)
	modal.set_title(structure_name)

	# Check if this is the Dragon Den - special content with dice
	if structure_name == "Dragon Den":
		var content = _create_dragon_den_content(structure_description)
		modal.set_content(content)
	else:
		# Standard content for other structures
		var content_label = Label.new()
		content_label.text = structure_description
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
	structure_modal_opened.emit(current_structure)
	print("StructureManager: Modal opened for ", structure_name)


## Called when the modal is closed
func _on_modal_closed(main_scene: Node) -> void:
	print("StructureManager: Modal closed, panning camera back")

	# Mark as transitioning
	is_transitioning = true
	is_modal_open = false

	# Pan camera back to ground view
	if main_scene and main_scene.has_method("pan_camera_to_ground"):
		await main_scene.pan_camera_to_ground()

	# Mark transition complete
	is_transitioning = false

	structure_modal_closed.emit(current_structure)
	current_structure = null
	print("StructureManager: Returned to ground view")


## Force close any open modal (emergency cleanup)
func force_close_modal() -> void:
	is_modal_open = false
	is_transitioning = false
	current_structure = null
	print("StructureManager: Force closed modal")


## Register a structure and automatically position it
func register_structure(structure: Node2D) -> void:
	if structure in registered_structures:
		push_warning("StructureManager: Structure already registered")
		return

	registered_structures.append(structure)

	# Get structure level if it's a BaseStructure
	var level = BaseStructure.StructureLevel.GROUND
	if structure is BaseStructure:
		level = structure.structure_level

	# Calculate position based on number of registered structures and level
	var index = registered_structures.size() - 1
	var position = _calculate_structure_position(index, level)
	structure.position = position

	print("StructureManager: Registered structure at position ", position, " (Level: ", level, ")")


## Calculate position for a structure based on its index and level
func _calculate_structure_position(index: int, level: BaseStructure.StructureLevel = BaseStructure.StructureLevel.GROUND) -> Vector2:
	# Calculate X position with spacing
	var x = start_x + (index * structure_spacing)

	# Wrap around if we exceed viewport width
	if x > viewport_width - 100:  # Leave margin on right edge
		# Calculate how many structures fit in one row
		var structures_per_row = int((viewport_width - start_x) / structure_spacing)
		var row = index / structures_per_row
		var col = index % structures_per_row
		x = start_x + (col * structure_spacing)

		# Offset Y for new rows (not implemented yet, but placeholder)
		# y_offset = row * 100.0

	# Get base Y position for the structure's level
	var base_y = level_y_positions.get(level, level_y_positions[BaseStructure.StructureLevel.GROUND])

	# Add random Y variance for natural look (seeded by index for consistency)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(index)
	var y_offset = rng.randf_range(-ground_y_variance, ground_y_variance)
	var y = base_y + y_offset

	return Vector2(x, y)


## Get the next available position for a new structure
func get_next_structure_position(level: BaseStructure.StructureLevel = BaseStructure.StructureLevel.GROUND) -> Vector2:
	var next_index = registered_structures.size()
	return _calculate_structure_position(next_index, level)


## Get all structures with a specific type flag
func get_structures_by_type(type: BaseStructure.StructureType) -> Array[Node2D]:
	var matching_structures: Array[Node2D] = []
	for structure in registered_structures:
		if structure is BaseStructure and structure.has_type(type):
			matching_structures.append(structure)
	return matching_structures


## Get all spawn structures (for starting scene)
func get_spawn_structures() -> Array[Node2D]:
	return get_structures_by_type(BaseStructure.StructureType.SPAWN)


## Clear all registered structures (useful for scene transitions)
func clear_structures() -> void:
	registered_structures.clear()
	print("StructureManager: Cleared all registered structures")


## Create special content for Dragon Den with dice rolling
func _create_dragon_den_content(description: String) -> Control:
	# Create main container
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 20)

	# Add description label
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Apply font to description
	var font = load("res://nodes/ui/fonts/alagard.ttf")
	desc_label.add_theme_font_override("font", font)
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	desc_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	desc_label.add_theme_constant_override("outline_size", 4)

	container.add_child(desc_label)

	# Add dice from MechanicsManager
	var dice = MechanicsManager.get_dice_instance()
	dice.scale = Vector2(3, 3)  # Make dice bigger for visibility

	# Center the dice
	var dice_center = CenterContainer.new()
	dice_center.add_child(dice)
	container.add_child(dice_center)

	# Add result label (initially hidden)
	var result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_override("font", font)
	result_label.add_theme_font_size_override("font_size", 24)
	result_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))  # Gold color
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	result_label.add_theme_constant_override("outline_size", 4)
	container.add_child(result_label)

	# Add roll button
	var roll_button = Button.new()
	roll_button.text = "Roll the Dice!"
	roll_button.add_theme_font_override("font", font)
	roll_button.add_theme_font_size_override("font_size", 20)
	roll_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# Create button style
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color(0.6, 0.3, 0.1, 0.9)  # Brown color
	button_style.border_color = Color(1, 0.8, 0, 1)  # Gold border
	button_style.border_width_left = 2
	button_style.border_width_right = 2
	button_style.border_width_top = 2
	button_style.border_width_bottom = 2
	button_style.corner_radius_top_left = 8
	button_style.corner_radius_top_right = 8
	button_style.corner_radius_bottom_left = 8
	button_style.corner_radius_bottom_right = 8

	var button_hover_style = button_style.duplicate()
	button_hover_style.bg_color = Color(0.7, 0.4, 0.15, 1.0)

	roll_button.add_theme_stylebox_override("normal", button_style)
	roll_button.add_theme_stylebox_override("hover", button_hover_style)
	roll_button.add_theme_stylebox_override("pressed", button_style)

	# Center the button
	var button_center = CenterContainer.new()
	button_center.add_child(roll_button)
	container.add_child(button_center)

	# Connect button to dice roll
	roll_button.pressed.connect(func():
		if not dice.is_dice_rolling():
			result_label.text = "Rolling..."
			roll_button.disabled = true
			dice.roll()
	)

	# Connect dice signals
	dice.dice_roll_finished.connect(func(result: int):
		result_label.text = "You rolled a " + str(result) + "!"
		roll_button.disabled = false
		print("Dragon Den dice result: ", result)
	)

	return container
