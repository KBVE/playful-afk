extends Node2D

## Main Gameplay Scene for AFK Virtual Pet Game
## This is where the player interacts with their pet and manages resources
## Features camera panning between ground view and sky view

@onready var camera: Camera2D = $Camera2D
@onready var sky_cloudbox: Control = $SkyCloudbox
@onready var game_view: Control = $GameView
@onready var pet_container: Control = $GameView/PetContainer
@onready var background: Control = $GameView/RollingHillsBackground

# Camera positions
var camera_ground_position: Vector2 = Vector2(576, 324)  # Center of ground view (1152x648)
var camera_sky_position: Vector2 = Vector2(576, -324)  # Center of sky view (648 pixels up)
var camera_pan_duration: float = 1.0
var is_camera_panning: bool = false

# Game state
var is_paused: bool = false

# Cat tracking for parallax
var cat: Cat = null
var cat_start_position: float = 0.0
var cat_target_position: float = 0.0
var move_right: bool = true


func _ready() -> void:
	print("Main gameplay scene loaded")

	# Wait a frame to ensure NPCManager is ready
	await get_tree().process_frame

	# Setup the pet
	_setup_pet()

	# Connect to event manager
	EventManager.game_paused.connect(_on_game_paused)


func _setup_pet() -> void:
	# Get the global cat from NPCManager
	print("Checking for cat in NPCManager...")
	if not NPCManager or not NPCManager.cat:
		push_error("Cat not found in NPCManager!")
		return

	cat = NPCManager.cat
	print("Found cat: ", cat)

	# Reparent cat to pet container
	cat.reparent(pet_container)

	# Position cat in the center-bottom of the screen
	var viewport_size = get_viewport_rect().size
	cat.position = Vector2(viewport_size.x / 2, viewport_size.y - 150)
	cat.scale = Vector2(4, 4)  # Make cat bigger for main gameplay

	# Store starting position for parallax
	cat_start_position = cat.position.x

	# Enable cat controller for autonomous movement
	cat.set_physics_process(false)  # Keep physics disabled (no gravity)
	cat.set_player_controlled(false)  # Enable autonomous behavior

	# Start the cat moving around
	_start_cat_movement()

	print("Cat setup complete in main scene at position: ", cat.position)


func _start_cat_movement() -> void:
	# Disable the cat's built-in random state timer
	if cat.state_timer:
		cat.state_timer.stop()

	# Use the controller to make the cat move between screen edges
	if cat.controller:
		var viewport_size = get_viewport_rect().size
		var screen_width = viewport_size.x

		# Start by moving to the right edge
		move_right = true
		cat_target_position = screen_width - 100
		cat.controller.move_to_position(cat_target_position)
		print("Cat moving to position: ", cat_target_position)

		# Set up a timer to change direction when cat reaches target
		var move_timer = Timer.new()
		move_timer.wait_time = 15.0  # Check every 15 seconds
		move_timer.timeout.connect(_on_move_timer_timeout)
		add_child(move_timer)
		move_timer.start()
		print("Cat movement timer started")


func _on_move_timer_timeout() -> void:
	# Make cat move to the opposite side of the screen
	if not cat or not cat.controller:
		return

	var viewport_size = get_viewport_rect().size
	var screen_width = viewport_size.x

	# Toggle direction
	move_right = !move_right

	# Set target based on direction
	if move_right:
		cat_target_position = screen_width - 100
	else:
		cat_target_position = 100

	cat.controller.move_to_position(cat_target_position)
	print("Cat changing direction, moving to: ", cat_target_position)


func _on_game_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	print("Game paused: ", paused)


func _process(delta: float) -> void:
	# Update cat controller movement
	if cat and cat.controller:
		cat.controller.update_movement(delta)

	# Update parallax background based on cat movement
	if cat and background:
		_update_background_scroll()


func _update_background_scroll() -> void:
	if not background or not cat:
		return

	# Calculate how far the cat has moved from its starting position
	var cat_offset = cat.position.x - cat_start_position

	# Scroll the background based on cat's movement
	background.scroll_to(cat_offset)


func _input(event: InputEvent) -> void:
	# Handle escape key to pause
	if event.is_action_pressed("ui_cancel"):
		EventManager.game_paused.emit(not is_paused)


## Pan camera to sky view (for cat farm interaction)
func pan_camera_to_sky() -> void:
	if is_camera_panning or not camera:
		return

	is_camera_panning = true
	print("Panning camera to sky view")

	var tween = create_tween()
	tween.tween_property(camera, "position", camera_sky_position, camera_pan_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	is_camera_panning = false
	print("Camera reached sky view")


## Pan camera back to ground view
func pan_camera_to_ground() -> void:
	if is_camera_panning or not camera:
		return

	is_camera_panning = true
	print("Panning camera to ground view")

	var tween = create_tween()
	tween.tween_property(camera, "position", camera_ground_position, camera_pan_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	is_camera_panning = false
	print("Camera reached ground view")
