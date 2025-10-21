extends Node2D

## Main Gameplay Scene for AFK Virtual Pet Game
## This is where the player interacts with their pet and manages resources
## Features camera panning between ground view and sky view

@onready var camera: Camera2D = $Camera2D
@onready var sky_cloudbox: Control = $SkyCloudbox
@onready var bartender: Control = $Bartender
@onready var chat_ui: Control = $Bartender/ChatUI
@onready var game_view: Control = $GameView
@onready var pet_container: Control = $GameView/PetContainer
@onready var background: Control = $GameView/RollingHillsBackground
@onready var foreground_characters: Control = $GameView/ForegroundCharacters

# Camera positions
var camera_ground_position: Vector2 = Vector2(576, 324)  # Center of ground view (1152x648)
var camera_sky_position: Vector2 = Vector2(576, -324)  # Center of sky view (648 pixels up)
var camera_bartender_position: Vector2 = Vector2(576, 972)  # Center of bartender view (648 pixels down)
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

	# Setup character pool and warriors
	_setup_character_pool()

	# Connect to EventManager signals
	EventManager.game_paused.connect(_on_game_paused)
	EventManager.view_state_changed.connect(_on_view_state_changed)
	EventManager.npc_dialogue_requested.connect(_on_npc_dialogue_requested)
	EventManager.npc_dialogue_closed.connect(_on_npc_dialogue_closed)
	EventManager.escape_pressed.connect(_on_escape_pressed)

	# Register Bartender scene and ChatUI with EventManager for centralized visibility management
	if bartender:
		EventManager.register_bartender_scene(bartender)

	if chat_ui:
		# Register ChatUI as a persistent UI element (won't be destroyed, just shown/hidden)
		EventManager.register_ui(EventManager.UIType.CHAT_UI, chat_ui)
		chat_ui.dialogue_closed.connect(_on_chat_ui_closed)


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
	cat.position = Vector2(viewport_size.x / 2, viewport_size.y - 60)  # Moved down 20px (was -80, now -60)
	cat.scale = Vector2(3, 3)  # Make cat bigger for main gameplay

	# Store starting position for parallax
	cat_start_position = cat.position.x

	# Enable cat controller for autonomous movement
	cat.set_physics_process(false)  # Keep physics disabled (no gravity)
	cat.set_player_controlled(false)  # Enable autonomous behavior

	# Start the cat moving around
	_start_cat_movement()

	print("Cat setup complete in main scene at position: ", cat.position)


func _setup_character_pool() -> void:
	# Set Layer4Objects container in NPCManager (scrolls with Layer4 at 0.9 speed)
	if background and background.layer4_objects:
		NPCManager.set_layer4_container(background.layer4_objects)
	else:
		push_error("Layer4Objects not found in background!")
		return

	# Spawn NPCs using the generic pool system (with stats)
	var viewport_size = get_viewport_rect().size
	var base_y = viewport_size.y - 150

	# Define safe Y zone for NPC movement
	var upper_bound_y = viewport_size.y - 220  # Archer spawn position (moved down 10px from -230)
	var lower_bound_y = base_y  # Warrior spawn position (ground level)
	var y_movement_bounds = Vector2(upper_bound_y, lower_bound_y)  # Safe Y zone for AI movement

	# Spawn 6 warriors with random names and stats
	var num_warriors = 6
	for i in range(num_warriors):
		var x_pos = 200 + (i * 150)  # Spread them across the screen
		var warrior_pos = Vector2(x_pos, base_y)
		var warrior = NPCManager.get_generic_npc("warrior", warrior_pos, y_movement_bounds)
		if warrior:
			warrior.scale = Vector2(2, 2)
			warrior.set_physics_process(false)
			warrior.set_player_controlled(false)
			# Use lambda to pass the warrior instance to the handler
			warrior.warrior_clicked.connect(func(): _on_npc_clicked(warrior))

	# Spawn 6 archers with random names and stats
	var num_archers = 6
	for i in range(num_archers):
		var x_pos = 200 + (i * 150)
		var archer_pos = Vector2(x_pos, upper_bound_y)  # Upper bound (moved down 10px)
		var archer = NPCManager.get_generic_npc("archer", archer_pos, y_movement_bounds)
		if archer:
			archer.scale = Vector2(2, 2)
			archer.set_physics_process(false)
			archer.set_player_controlled(false)
			# Use lambda to pass the archer instance to the handler
			archer.archer_clicked.connect(func(): _on_npc_clicked(archer))


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


## Handle ESC key when at ground view (for pause menu, etc.)
func _on_escape_pressed() -> void:
	print("Main: ESC pressed at ground view - toggling pause")
	EventManager.game_paused.emit(not is_paused)


## Handle NPC clicked - request dialogue via EventManager
func _on_npc_clicked(npc: Node2D) -> void:
	if not npc or not "stats" in npc or not npc.stats:
		push_warning("Clicked NPC has no stats!")
		return

	# Get NPC info from stats
	var npc_name = npc.stats.npc_name
	var npc_type = npc.stats.npc_type

	# Generate appropriate dialogue based on type
	var dialogue = ""
	match npc_type:
		"warrior":
			dialogue = "Hello traveler! I am %s, ready to serve!" % npc_name
		"archer":
			dialogue = "Greetings! I'm %s, my arrows never miss!" % npc_name
		_:
			dialogue = "Hello there!"

	# Request NPC dialogue via EventManager (pass NPC with stats)
	EventManager.request_npc_dialogue(npc, npc_name, dialogue)


## Handle NPC dialogue request from EventManager
func _on_npc_dialogue_requested(npc: Node2D, npc_name: String, dialogue_text: String) -> void:
	print("Main: NPC dialogue requested - ", npc_name)

	if not npc or not chat_ui:
		print("ERROR: npc or chat_ui is null! npc=", npc, " chat_ui=", chat_ui)
		return

	# Prepare chat UI with NPC data (ChatUI will use cached sprite from NPCManager)
	chat_ui.show_dialogue(npc_name, npc)
	chat_ui.set_dialogue_text(dialogue_text)

	# Show ChatUI via EventManager (handles visibility, input blocking, and stack management)
	EventManager.show_ui(EventManager.UIType.CHAT_UI)

	# Request view change to bartender (ChatUI will be shown after pan completes)
	EventManager.request_view_change(EventManager.ViewState.BARTENDER)


## Handle ChatUI close button pressed
func _on_chat_ui_closed() -> void:
	print("ChatUI close button pressed")
	# Notify EventManager that dialogue is closed
	EventManager.close_npc_dialogue()


## Handle NPC dialogue closed from EventManager
func _on_npc_dialogue_closed() -> void:
	print("Main: NPC dialogue closed event received")

	# Hide ChatUI via EventManager (handles visibility, input blocking, and stack management)
	EventManager.hide_ui(EventManager.UIType.CHAT_UI)

	# Request view change back to ground
	EventManager.request_view_change(EventManager.ViewState.GROUND)


## Handle view state changes from EventManager
func _on_view_state_changed(new_state: EventManager.ViewState, old_state: EventManager.ViewState) -> void:
	print("Main: View state changed from ", EventManager.ViewState.keys()[old_state], " to ", EventManager.ViewState.keys()[new_state])

	# Perform the camera pan based on new state
	match new_state:
		EventManager.ViewState.GROUND:
			_pan_to_ground()
		EventManager.ViewState.SKY:
			_pan_to_sky()
		EventManager.ViewState.BARTENDER:
			_pan_to_bartender()


## Internal camera pan functions (called by view state changes)
func _pan_to_ground() -> void:
	if is_camera_panning or not camera:
		return

	is_camera_panning = true
	print("Panning camera to ground view")

	var tween = create_tween()
	tween.tween_property(camera, "position", camera_ground_position, camera_pan_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	is_camera_panning = false
	print("Camera reached ground view")
	EventManager.complete_view_transition(EventManager.ViewState.GROUND)


func _pan_to_sky() -> void:
	if is_camera_panning or not camera:
		return

	is_camera_panning = true
	print("Panning camera to sky view")

	var tween = create_tween()
	tween.tween_property(camera, "position", camera_sky_position, camera_pan_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	is_camera_panning = false
	print("Camera reached sky view")
	EventManager.complete_view_transition(EventManager.ViewState.SKY)


func _pan_to_bartender() -> void:
	if is_camera_panning or not camera:
		return

	is_camera_panning = true
	print("Panning camera to bartender view")

	var tween = create_tween()
	tween.tween_property(camera, "position", camera_bartender_position, camera_pan_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	is_camera_panning = false
	print("Camera reached bartender view")
	EventManager.complete_view_transition(EventManager.ViewState.BARTENDER)
