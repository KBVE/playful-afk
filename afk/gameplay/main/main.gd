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

# Monster tracking (spawning managed by EventManager)
const MAX_ACTIVE_MONSTERS: int = 20  # Maximum monsters at once (to accommodate waves of 4-10)
var active_monsters: Array[Node2D] = []

# Ally tracking and respawn system
var ally_respawn_timer: Timer = null
const ALLY_RESPAWN_INTERVAL: float = 3.0  # Check every 3 seconds for dead allies
const MAX_WARRIORS: int = 6  # Always maintain 6 warriors
const MAX_ARCHERS: int = 6  # Always maintain 6 archers
var active_warriors: Array[Node2D] = []
var active_archers: Array[Node2D] = []


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

	# Connect to InputManager for NPC clicks (handles both GDScript and Rust NPCs)
	InputManager.object_clicked.connect(_on_object_clicked)

	# Register Bartender scene and ChatUI with EventManager for centralized visibility management
	if bartender:
		EventManager.register_bartender_scene(bartender)

	if chat_ui:
		# Register ChatUI as a persistent UI element (won't be destroyed, just shown/hidden)
		EventManager.register_ui(EventManager.UIType.CHAT_UI, chat_ui)
		chat_ui.dialogue_closed.connect(_on_chat_ui_closed)

	# Setup EventManager spawn system with background reference
	EventManager.setup_spawn_system(background)

	# Connect to spawn event signals
	EventManager.ally_spawn_requested.connect(_on_ally_spawn_requested)
	EventManager.monster_spawn_requested.connect(_on_monster_spawn_requested)
	EventManager.ally_respawn_requested.connect(_on_ally_respawn_requested)

	# Enable spawn processing after initial setup
	EventManager.set_spawn_enabled(true)

	# RUST COMBAT: Ally spawning is now handled by Rust (disabled GDScript ally respawn timer)
	# Rust handles all spawning (allies + monsters) with proper timing and caps
	# _setup_ally_respawn_checker()  # DISABLED


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



func _setup_character_pool() -> void:

	# Set Layer4Objects container in NPCManager (scrolls with Layer4 at 0.9 speed)
	if background and background.layer4_objects:
		NPCManager.set_layer4_container(background.layer4_objects)
		NPCManager.set_background_reference(background)  # For heightmap queries during AI movement

		# RUST POOL: Set scene container in Rust so it can add/remove NPCs
		# NOTE: Pools are pre-initialized in NPCDataWarehouse singleton's _ready()
		# This just sets the container where NPCs will be added
		NPCDataWarehouse.set_scene_container(background.layer4_objects)

		# Set projectile container for arrows and other projectiles (reparents existing arrows)
		if ProjectileManager:
			ProjectileManager.set_projectile_container(background.layer4_objects)

		# Set environment container for flags and other environment objects
		if EnvironmentManager:
			EnvironmentManager.set_environment_container(background.layer4_objects)

		# RUST COMBAT: Set world bounds from BackgroundManager (simple 4 bounds)
		# This ensures Rust waypoint clamping uses the actual background's playable area
		if BackgroundManager:
			NPCDataWarehouse.set_world_bounds(
				BackgroundManager.min_x,
				BackgroundManager.max_x,
				BackgroundManager.min_y,
				BackgroundManager.max_y
			)
	else:
		push_error("Layer4Objects not found in background!")
		return

	# RUST COMBAT: All NPC spawning (allies + monsters) is now handled by Rust
	# NPCs are spawned directly from Rust pools without GDScript involvement
	# Pools were pre-initialized in NPCDataWarehouse singleton's _ready()


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

		# Set up a timer to change direction when cat reaches target
		var move_timer = Timer.new()
		move_timer.wait_time = 15.0  # Check every 15 seconds
		move_timer.timeout.connect(_on_move_timer_timeout)
		add_child(move_timer)
		move_timer.start()


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


## Handle monster spawn requests from EventManager
func _on_monster_spawn_requested(monster_type: String, spawn_pos_global: Vector2, initial_target_global: Vector2) -> void:
	# Don't spawn if at max capacity
	if active_monsters.size() >= MAX_ACTIVE_MONSTERS:
		return

	# Convert global spawn position to Layer4Objects local coordinates
	var spawn_pos_local = spawn_pos_global
	if background.layer4_objects:
		spawn_pos_local = background.layer4_objects.to_local(spawn_pos_global)
	else:
		push_error("main.gd: Cannot spawn monster - background.layer4_objects is null")
		return

	# Convert target to Layer4Objects local coordinates
	var initial_target_local = initial_target_global
	if background.layer4_objects:
		initial_target_local = background.layer4_objects.to_local(initial_target_global)

	# Spawn the monster with initial target (NPCManager handles AI state initialization)
	var monster = NPCManager.get_generic_npc(monster_type, spawn_pos_local, initial_target_local)
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
	else:
		push_error("main.gd: Failed to spawn monster - NPCManager.get_generic_npc returned null for type: %s" % monster_type)


## Handle ally spawn requests from EventManager
func _on_ally_spawn_requested(ally_type: String, spawn_pos_global: Vector2, _initial_target_global: Vector2) -> void:
	# Convert global spawn position to Layer4Objects local coordinates
	var spawn_pos_local = spawn_pos_global
	if background.layer4_objects:
		spawn_pos_local = background.layer4_objects.to_local(spawn_pos_global)
	else:
		push_error("main.gd: Cannot spawn ally - background.layer4_objects is null")
		return

	# Get the ally from pool
	var ally = NPCManager.get_generic_npc(ally_type, spawn_pos_local)
	if ally:
		ally.scale = Vector2(1, 1)
		ally.set_physics_process(false)

		# Connect death signal
		var death_signal_name = ally_type + "_died"
		if ally.has_signal(death_signal_name):
			var death_signal = ally.get(death_signal_name)
			if not death_signal.is_connected(_on_ally_died):
				death_signal.connect(_on_ally_died.bind(ally, ally_type))

		# Connect click signal
		var click_signal_name = ally_type + "_clicked"
		if ally.has_signal(click_signal_name):
			var click_signal = ally.get(click_signal_name)
			if not click_signal.is_connected(_on_npc_clicked):
				click_signal.connect(func(): _on_npc_clicked(ally))

		# Track the ally
		if ally_type == "warrior":
			active_warriors.append(ally)
		elif ally_type == "archer":
			active_archers.append(ally)
	else:
		push_error("main.gd: Failed to spawn ally - NPCManager.get_generic_npc returned null for type: %s" % ally_type)


## Handle ally respawn requests from EventManager
func _on_ally_respawn_requested(ally_type: String) -> void:
	_respawn_ally(ally_type)


## Handle monster death - remove from active list
func _on_monster_died(monster: Node2D) -> void:
	if monster in active_monsters:
		active_monsters.erase(monster)


## Setup ally respawn system
func _setup_ally_respawn_checker() -> void:
	ally_respawn_timer = Timer.new()
	ally_respawn_timer.wait_time = ALLY_RESPAWN_INTERVAL
	ally_respawn_timer.one_shot = false
	ally_respawn_timer.timeout.connect(_on_ally_respawn_timer_timeout)
	add_child(ally_respawn_timer)
	ally_respawn_timer.start()


## Called when ally respawn timer times out - respawn dead allies
func _on_ally_respawn_timer_timeout() -> void:
	# Clean up invalid references
	active_warriors = active_warriors.filter(func(w): return is_instance_valid(w))
	active_archers = active_archers.filter(func(a): return is_instance_valid(a))

	# Respawn warriors if needed
	var warriors_needed = MAX_WARRIORS - active_warriors.size()
	if warriors_needed > 0:
		print("Respawning %d warrior(s) - currently have %d/%d" % [warriors_needed, active_warriors.size(), MAX_WARRIORS])
		for i in range(warriors_needed):
			_respawn_ally("warrior")

	# Respawn archers if needed
	var archers_needed = MAX_ARCHERS - active_archers.size()
	if archers_needed > 0:
		print("Respawning %d archer(s) - currently have %d/%d" % [archers_needed, active_archers.size(), MAX_ARCHERS])
		for i in range(archers_needed):
			_respawn_ally("archer")


## Respawn a single ally of the given type
func _respawn_ally(ally_type: String) -> void:
	var viewport_size = get_viewport_rect().size
	var spawn_x_min = 50.0
	var spawn_x_max = viewport_size.x - 50.0

	# Try to find a valid spawn position inside the walkable polygon
	var spawn_pos = Vector2.ZERO
	var is_valid = false
	var attempts = 0

	while attempts < 20 and not is_valid:
		# Random position across screen width
		var x_pos = randf_range(spawn_x_min, spawn_x_max)

		# Get Y bounds at this X position
		var y_bounds = background.get_walkable_y_bounds(x_pos)
		# Spawn in lower 70% of walkable area to avoid floating appearance on hills
		var min_y = y_bounds.x
		var max_y = y_bounds.y
		var bottom_70_percent = min_y + (max_y - min_y) * 0.3
		var random_y = randf_range(bottom_70_percent, max_y)

		spawn_pos = Vector2(x_pos, random_y)

		# Check if position is inside walkable area
		if background.has_method("is_position_in_walkable_area"):
			is_valid = background.is_position_in_walkable_area(spawn_pos)
		else:
			is_valid = true  # Fallback

		attempts += 1

	if not is_valid:
		push_warning("Could not find valid spawn position for %s respawn" % ally_type)
		return

	# Convert global spawn position to Layer4Objects local coordinates
	var spawn_pos_local = spawn_pos
	if background.layer4_objects:
		spawn_pos_local = background.layer4_objects.to_local(spawn_pos)

	# Spawn the ally
	var ally = NPCManager.get_generic_npc(ally_type, spawn_pos_local)
	if not ally:
		push_warning("Failed to spawn %s from pool" % ally_type)
		return

	ally.scale = Vector2(1, 1)
	ally.set_physics_process(false)
	ally.set_player_controlled(false)

	# Connect signals based on type
	if ally_type == "warrior":
		if ally.has_signal("warrior_clicked"):
			ally.warrior_clicked.connect(func(): _on_npc_clicked(ally))
		if ally.has_signal("npc_died"):
			if not ally.npc_died.is_connected(_on_ally_died):
				ally.npc_died.connect(_on_ally_died.bind(ally, "warrior"))
		active_warriors.append(ally)
	elif ally_type == "archer":
		if ally.has_signal("archer_clicked"):
			ally.archer_clicked.connect(func(): _on_npc_clicked(ally))
		if ally.has_signal("npc_died"):
			if not ally.npc_died.is_connected(_on_ally_died):
				ally.npc_died.connect(_on_ally_died.bind(ally, "archer"))
		active_archers.append(ally)

	print("Respawned %s at %s" % [ally_type, spawn_pos])


## Handle ally death - remove from active list
func _on_ally_died(ally: Node2D, ally_type: String) -> void:
	if ally_type == "warrior" and ally in active_warriors:
		active_warriors.erase(ally)
		print("Warrior died - now have %d/%d warriors" % [active_warriors.size(), MAX_WARRIORS])
	elif ally_type == "archer" and ally in active_archers:
		active_archers.erase(ally)
		print("Archer died - now have %d/%d archers" % [active_archers.size(), MAX_ARCHERS])


## Handle object clicked from InputManager
## Filters for NPCs and forwards to NPC click handler
func _on_object_clicked(object: Node2D) -> void:
	if not object:
		return

	# Check if clicked object is an NPC (has ulid property)
	var has_ulid = "ulid" in object
	var is_npc = has_ulid

	if is_npc:
		_on_npc_clicked(object)


## Handle NPC clicked - request dialogue via EventManager
func _on_npc_clicked(npc: Node2D) -> void:
	if not npc:
		push_warning("Clicked NPC is null!")
		return

	# Get ULID from NPC
	if not "ulid" in npc:
		var npc_script = npc.get_script()
		var script_path = npc_script.resource_path if npc_script else "no script"
		push_warning("Clicked NPC has no ULID property! Script: %s" % script_path)
		return

	var ulid_bytes: PackedByteArray = npc.ulid

	# Validate ULID
	if ulid_bytes.size() == 0:
		var npc_script = npc.get_script()
		var script_path = npc_script.resource_path if npc_script else "no script"
		push_warning("Clicked NPC has empty ULID! Script: %s - This NPC wasn't properly initialized." % script_path)
		return

	EventManager.request_npc_dialogue(npc, ulid_bytes)


## Handle NPC dialogue request from EventManager
## Query Rust for NPC data using ULID, generate dialogue, and show ChatUI
func _on_npc_dialogue_requested(npc: Node2D, npc_ulid: PackedByteArray) -> void:
	if not npc or not chat_ui:
		return

	var npc_name = ""
	var npc_type = ""
	var dialogue_text = ""

	# Check if ULID is valid (non-zero)
	var is_rust_npc = false
	if npc_ulid.size() == 16:
		# Check if ULID is non-zero
		for byte in npc_ulid:
			if byte != 0:
				is_rust_npc = true
				break

	if is_rust_npc:
		# Query Rust for NPC name and type using ULID
		npc_name = NPCDataWarehouse.get_npc_name(npc_ulid)
		npc_type = NPCDataWarehouse.get_npc_type(npc_ulid)

		# Fallback: get class name as type
		if npc_type == "":
			npc_type = npc.get_class().to_lower()

		# Fallback: generate generic name
		if npc_name == "":
			npc_name = npc_type.capitalize() + " NPC"
	else:
		# Fallback to old GDScript stats system
		if "stats" in npc and npc.stats:
			npc_name = npc.stats.npc_name
			npc_type = npc.stats.npc_type
		else:
			push_warning("No valid ULID and NPC has no stats!")
			return

	# Generate appropriate dialogue based on type
	match npc_type:
		"warrior":
			dialogue_text = "Hello traveler! I am %s, ready to serve!" % npc_name
		"archer":
			dialogue_text = "Greetings! I'm %s, my arrows never miss!" % npc_name
		"goblin":
			dialogue_text = "*Growls* %s hungers for battle!" % npc_name
		"mushroom":
			dialogue_text = "*Spore sounds* I am %s..." % npc_name
		"skeleton":
			dialogue_text = "*Rattles bones* %s rises again..." % npc_name
		"eyebeast":
			dialogue_text = "*Stares intensely* %s sees all..." % npc_name
		_:
			dialogue_text = "Hello there! I'm %s." % npc_name

	print("Main: NPC dialogue requested - %s: %s" % [npc_name, dialogue_text])

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
