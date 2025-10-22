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

# Cat hover scaling
var cat_is_hovered: bool = false
var cat_normal_scale: Vector2 = Vector2(1.5, 1.5)
var cat_hover_scale: Vector2 = Vector2(3, 3)

# Monster spawning system
var monster_spawn_timer: Timer = null
const MONSTER_SPAWN_INTERVAL: float = 8.0  # Spawn every 8 seconds
const MAX_ACTIVE_MONSTERS: int = 6  # Maximum monsters at once
var active_monsters: Array[Node2D] = []


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

	# Setup monster spawning system
	_setup_monster_spawner()


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
	cat.position = Vector2(viewport_size.x / 2, viewport_size.y - 55)  # Moved down 25px total (was -80, now -55)
	cat.scale = Vector2(1.5, 1.5)  # Smaller scale, grows on hover to 3x

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
		NPCManager.set_background_reference(background)  # For heightmap queries during AI movement

		# Set projectile container for arrows and other projectiles (reparents existing arrows)
		if ProjectileManager:
			ProjectileManager.set_projectile_container(background.layer4_objects)

		# Set environment container for flags and other environment objects
		if EnvironmentManager:
			EnvironmentManager.set_environment_container(background.layer4_objects)
	else:
		push_error("Layer4Objects not found in background!")
		return

	# Spawn NPCs using the generic pool system (with stats)
	# Use background heightmap for accurate Y positioning - can spawn anywhere!
	var viewport_size = get_viewport_rect().size

	# Define wide spawn range - use almost full screen width
	var spawn_x_min = 50.0
	var spawn_x_max = viewport_size.x - 50.0

	# Spawn 6 warriors spread across the full screen width
	var num_warriors = 6
	for i in range(num_warriors):
		# Try to find a valid spawn position inside the walkable polygon
		var spawn_pos = Vector2.ZERO
		var is_valid = false
		var attempts = 0

		while attempts < 20 and not is_valid:
			# Spread evenly across full width
			var x_pos = spawn_x_min + (i * (spawn_x_max - spawn_x_min) / (num_warriors - 1))

			# Add some random variation to X (±50px)
			x_pos += randf_range(-50.0, 50.0)
			x_pos = clamp(x_pos, spawn_x_min, spawn_x_max)

			# Get Y bounds at this X position
			var y_bounds = background.get_walkable_y_bounds(x_pos)
			var random_y = randf_range(y_bounds.x, y_bounds.y)

			spawn_pos = Vector2(x_pos, random_y)

			# Check if position is inside walkable area
			if background.has_method("is_position_in_walkable_area"):
				is_valid = background.is_position_in_walkable_area(spawn_pos)
			else:
				is_valid = true  # Fallback

			attempts += 1

		if is_valid:
			var warrior = NPCManager.get_generic_npc("warrior", spawn_pos)
			if warrior:
				warrior.scale = Vector2(1, 1)  # Normal size for better collision/combat
				warrior.set_physics_process(false)
				warrior.set_player_controlled(false)
				warrior.warrior_clicked.connect(func(): _on_npc_clicked(warrior))
		else:
			push_warning("Could not find valid spawn position for warrior %d" % i)

	# Spawn 6 archers spread across the full screen width
	var num_archers = 6
	for i in range(num_archers):
		# Try to find a valid spawn position inside the walkable polygon
		var spawn_pos = Vector2.ZERO
		var is_valid = false
		var attempts = 0

		while attempts < 20 and not is_valid:
			# Spread evenly across full width (offset slightly from warriors)
			var offset = (spawn_x_max - spawn_x_min) / (num_archers * 2)
			var x_pos = spawn_x_min + offset + (i * (spawn_x_max - spawn_x_min) / num_archers)

			# Add some random variation to X (±50px)
			x_pos += randf_range(-50.0, 50.0)
			x_pos = clamp(x_pos, spawn_x_min, spawn_x_max)

			# Get Y bounds at this X position
			var y_bounds = background.get_walkable_y_bounds(x_pos)
			var random_y = randf_range(y_bounds.x, y_bounds.y)

			spawn_pos = Vector2(x_pos, random_y)

			# Check if position is inside walkable area
			if background.has_method("is_position_in_walkable_area"):
				is_valid = background.is_position_in_walkable_area(spawn_pos)
			else:
				is_valid = true  # Fallback

			attempts += 1

		if is_valid:
			var archer = NPCManager.get_generic_npc("archer", spawn_pos)
			if archer:
				archer.scale = Vector2(1, 1)  # Normal size for better collision/combat
				archer.set_physics_process(false)
				archer.set_player_controlled(false)
				archer.archer_clicked.connect(func(): _on_npc_clicked(archer))
		else:
			push_warning("Could not find valid spawn position for archer %d" % i)

	# Spawn 1 chicken for combat testing
	var chicken_spawn_pos = Vector2.ZERO
	var chicken_is_valid = false
	var chicken_attempts = 0

	while chicken_attempts < 20 and not chicken_is_valid:
		# Spawn in center of screen
		var x_pos = viewport_size.x / 2 + randf_range(-100.0, 100.0)
		var y_bounds = background.get_walkable_y_bounds(x_pos)
		var random_y = randf_range(y_bounds.x, y_bounds.y)

		chicken_spawn_pos = Vector2(x_pos, random_y)

		# Check if position is inside walkable area
		if background.has_method("is_position_in_walkable_area"):
			chicken_is_valid = background.is_position_in_walkable_area(chicken_spawn_pos)
		else:
			chicken_is_valid = true

		chicken_attempts += 1

	if chicken_is_valid:
		var chicken = NPCManager.get_generic_npc("chicken", chicken_spawn_pos)
		if chicken:
			chicken.scale = Vector2(1, 1)  # Normal size to match warriors/archers
			chicken.set_physics_process(false)
			if chicken.has_signal("chicken_clicked"):
				chicken.chicken_clicked.connect(func(): _on_npc_clicked(chicken))
		print("Spawned chicken at %s for combat testing!" % chicken_spawn_pos)
	else:
		push_warning("Could not find valid spawn position for chicken")

	# Spawn 3 initial mushrooms
	for m in range(3):
		var mushroom_spawn_pos = Vector2.ZERO
		var mushroom_is_valid = false
		var mushroom_attempts = 0

		while mushroom_attempts < 20 and not mushroom_is_valid:
			# Spawn spread across the screen
			var x_pos = viewport_size.x * (0.3 + (m * 0.2)) + randf_range(-50.0, 50.0)
			var y_bounds = background.get_walkable_y_bounds(x_pos)
			var random_y = randf_range(y_bounds.x, y_bounds.y)

			mushroom_spawn_pos = Vector2(x_pos, random_y)

			# Check if position is inside walkable area
			if background.has_method("is_position_in_walkable_area"):
				mushroom_is_valid = background.is_position_in_walkable_area(mushroom_spawn_pos)
			else:
				mushroom_is_valid = true

			mushroom_attempts += 1

		if mushroom_is_valid:
			var mushroom = NPCManager.get_generic_npc("mushroom", mushroom_spawn_pos)
			if mushroom:
				mushroom.scale = Vector2(1, 1)
				mushroom.set_physics_process(false)
				if mushroom.has_signal("mushroom_died"):
					if not mushroom.mushroom_died.is_connected(_on_monster_died):
						mushroom.mushroom_died.connect(_on_monster_died.bind(mushroom))
				if mushroom.has_signal("mushroom_clicked"):
					if not mushroom.mushroom_clicked.is_connected(_on_npc_clicked):
						mushroom.mushroom_clicked.connect(func(): _on_npc_clicked(mushroom))
				active_monsters.append(mushroom)
			print("Spawned mushroom #%d at %s" % [m + 1, mushroom_spawn_pos])
		else:
			push_warning("Could not find valid spawn position for mushroom %d" % m)

	# Spawn 2-3 initial goblins
	for g in range(3):
		var goblin_spawn_pos = Vector2.ZERO
		var goblin_is_valid = false
		var goblin_attempts = 0

		while goblin_attempts < 20 and not goblin_is_valid:
			# Spawn spread across the screen (offset from mushrooms)
			var x_pos = viewport_size.x * (0.4 + (g * 0.2)) + randf_range(-50.0, 50.0)
			var y_bounds = background.get_walkable_y_bounds(x_pos)
			var random_y = randf_range(y_bounds.x, y_bounds.y)

			goblin_spawn_pos = Vector2(x_pos, random_y)

			# Check if position is inside walkable area
			if background.has_method("is_position_in_walkable_area"):
				goblin_is_valid = background.is_position_in_walkable_area(goblin_spawn_pos)
			else:
				goblin_is_valid = true

			goblin_attempts += 1

		if goblin_is_valid:
			var goblin = NPCManager.get_generic_npc("goblin", goblin_spawn_pos)
			if goblin:
				goblin.scale = Vector2(1, 1)
				goblin.set_physics_process(false)
				if goblin.has_signal("goblin_died"):
					if not goblin.goblin_died.is_connected(_on_monster_died):
						goblin.goblin_died.connect(_on_monster_died.bind(goblin))
				if goblin.has_signal("goblin_clicked"):
					if not goblin.goblin_clicked.is_connected(_on_npc_clicked):
						goblin.goblin_clicked.connect(func(): _on_npc_clicked(goblin))
				active_monsters.append(goblin)
			print("Spawned goblin #%d at %s" % [g + 1, goblin_spawn_pos])
		else:
			push_warning("Could not find valid spawn position for goblin %d" % g)


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

	# Check for cat hover and update scale
	if cat:
		_update_cat_hover()


func _update_background_scroll() -> void:
	if not background or not cat:
		return

	# Calculate how far the cat has moved from its starting position
	var cat_offset = cat.position.x - cat_start_position

	# Scroll the background based on cat's movement
	background.scroll_to(cat_offset)


func _update_cat_hover() -> void:
	# Check if mouse is hovering over the cat
	var mouse_pos = get_viewport().get_mouse_position()
	var cat_rect = _get_cat_bounding_box()
	var is_mouse_over = cat_rect.has_point(mouse_pos)

	# Update hover state and scale
	if is_mouse_over != cat_is_hovered:
		cat_is_hovered = is_mouse_over
		_update_cat_scale()


func _get_cat_bounding_box() -> Rect2:
	# Get the cat's screen position and size for hover detection
	var screen_pos = cat.get_global_transform_with_canvas().origin
	var sprite_size = Vector2(32, 29) * cat.scale  # Cat sprite base size
	return Rect2(screen_pos - sprite_size / 2, sprite_size)


func _update_cat_scale() -> void:
	# Smooth scale transition
	var target_scale = cat_hover_scale if cat_is_hovered else cat_normal_scale
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(cat, "scale", target_scale, 0.2)


## Handle ESC key when at ground view (for pause menu, etc.)
func _on_escape_pressed() -> void:
	print("Main: ESC pressed at ground view - toggling pause")
	EventManager.game_paused.emit(not is_paused)


## Setup monster spawning system
func _setup_monster_spawner() -> void:
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = MONSTER_SPAWN_INTERVAL
	monster_spawn_timer.one_shot = false
	monster_spawn_timer.timeout.connect(_on_monster_spawn_timer_timeout)
	add_child(monster_spawn_timer)
	monster_spawn_timer.start()
	print("Monster spawner initialized - spawning every %0.1fs" % MONSTER_SPAWN_INTERVAL)


## Called when monster spawn timer times out
func _on_monster_spawn_timer_timeout() -> void:
	# Don't spawn if at max capacity
	if active_monsters.size() >= MAX_ACTIVE_MONSTERS:
		print("Max monsters reached (%d/%d) - skipping spawn" % [active_monsters.size(), MAX_ACTIVE_MONSTERS])
		return

	# Get available monster types from the pool dynamically
	var monster_types = NPCManager.get_available_monster_types()
	if monster_types.is_empty():
		push_warning("No monster types available in pool!")
		return

	var monster_type = monster_types[randi() % monster_types.size()]

	# Randomly choose left or right edge
	var viewport_size = get_viewport_rect().size
	var spawn_from_left = randf() > 0.5
	var spawn_x = 50.0 if spawn_from_left else viewport_size.x - 50.0

	# Get Y bounds for this X position
	var y_bounds = background.get_walkable_y_bounds(spawn_x)
	var spawn_y = randf_range(y_bounds.x, y_bounds.y)
	var spawn_pos = Vector2(spawn_x, spawn_y)

	# Validate position
	if background.has_method("is_position_in_walkable_area"):
		if not background.is_position_in_walkable_area(spawn_pos):
			print("Invalid spawn position, trying again next cycle")
			return

	# Spawn the monster
	var monster = NPCManager.get_generic_npc(monster_type, spawn_pos)
	if monster:
		monster.scale = Vector2(1, 1)
		monster.set_physics_process(false)

		# Connect death signal dynamically (pattern: {type}_died)
		var death_signal_name = monster_type + "_died"
		if monster.has_signal(death_signal_name):
			var death_signal = monster.get(death_signal_name)
			if not death_signal.is_connected(_on_monster_died):
				death_signal.connect(_on_monster_died.bind(monster))
		# Fallback to generic monster_died signal
		elif monster.has_signal("monster_died"):
			if not monster.monster_died.is_connected(_on_monster_died):
				monster.monster_died.connect(_on_monster_died.bind(monster))

		# Connect click signal dynamically (pattern: {type}_clicked)
		var click_signal_name = monster_type + "_clicked"
		if monster.has_signal(click_signal_name):
			var click_signal = monster.get(click_signal_name)
			if not click_signal.is_connected(_on_npc_clicked):
				click_signal.connect(func(): _on_npc_clicked(monster))

		active_monsters.append(monster)


## Handle monster death - remove from active list
func _on_monster_died(monster: Node2D) -> void:
	if monster in active_monsters:
		active_monsters.erase(monster)


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
