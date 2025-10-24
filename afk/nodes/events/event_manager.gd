extends Node

## EventManager - Centralized Event System
## This autoload singleton handles all gameplay events for the AFK Virtual Pet game.
## Usage: EventManager.pet_fed.emit(pet_data) or EventManager.pet_fed.connect(_on_pet_fed)

# ===== Pet Events =====
## Emitted when the pet is fed. Parameters: (food_item: Dictionary)
signal pet_fed(food_item)

## Emitted when the pet's hunger changes. Parameters: (hunger_value: float)
signal pet_hunger_changed(hunger_value)

## Emitted when the pet's happiness changes. Parameters: (happiness_value: float)
signal pet_happiness_changed(happiness_value)

## Emitted when the pet's health changes. Parameters: (health_value: float)
signal pet_health_changed(health_value)

## Emitted when the pet levels up. Parameters: (new_level: int)
signal pet_leveled_up(new_level)

## Emitted when the pet's experience changes. Parameters: (current_xp: int, max_xp: int)
signal pet_xp_changed(current_xp, max_xp)

## Emitted when the pet evolves. Parameters: (new_form: String)
signal pet_evolved(new_form)

## Emitted when the pet's state changes (sleeping, playing, idle, etc.). Parameters: (state: String)
signal pet_state_changed(state)

# ===== Time & AFK Events =====
## Emitted when the player returns after being AFK. Parameters: (time_away: float)
signal player_returned(time_away)

## Emitted when AFK rewards are calculated. Parameters: (rewards: Dictionary)
signal afk_rewards_calculated(rewards)

## Emitted when the in-game time advances. Parameters: (delta_time: float)
signal time_advanced(delta_time)

# ===== Inventory & Items Events =====
## Emitted when an item is added to inventory. Parameters: (item: Dictionary, quantity: int)
signal item_added(item, quantity)

## Emitted when an item is removed from inventory. Parameters: (item: Dictionary, quantity: int)
signal item_removed(item, quantity)

## Emitted when an item is used. Parameters: (item: Dictionary)
signal item_used(item)

## Emitted when inventory changes. Parameters: (inventory: Array)
signal inventory_changed(inventory)

# ===== Currency & Resources Events =====
## Emitted when currency changes. Parameters: (currency_type: String, amount: int)
signal currency_changed(currency_type, amount)

## Emitted when a resource is gained. Parameters: (resource_type: String, amount: int)
signal resource_gained(resource_type, amount)

## Emitted when a resource is spent. Parameters: (resource_type: String, amount: int)
signal resource_spent(resource_type, amount)

# ===== UI Events =====
## Emitted when a screen transition is requested. Parameters: (from_scene: String, to_scene: String)
signal screen_transition_requested(from_scene, to_scene)

## Emitted when a popup should be shown. Parameters: (popup_type: String, data: Dictionary)
signal popup_requested(popup_type, data)

## Emitted when UI needs to be updated. Parameters: (ui_element: String)
signal ui_update_requested(ui_element)

# ===== Game State Events =====
## Emitted when the game starts/begins
signal game_started()

## Emitted when the game is paused. Parameters: (paused: bool)
signal game_paused(paused)

## Emitted when the game is saved. Parameters: (save_success: bool)
signal game_saved(save_success)

## Emitted when the game is loaded. Parameters: (load_success: bool)
signal game_loaded(load_success)

## Emitted when game data is reset
signal game_reset()

# ===== NPC & Combat Events =====
## Emitted when an NPC's state should change. Parameters: (npc: Node2D, new_state: int, reason: String)
signal npc_state_change_requested(npc, new_state, reason)

## Emitted when an NPC's state has changed. Parameters: (npc: Node2D, old_state: int, new_state: int, reason: String)
signal npc_state_changed(npc, old_state, new_state, reason)

## Emitted when combat starts. Parameters: (attacker: Node2D, target: Node2D)
signal combat_started(attacker, target)

## Emitted when combat ends. Parameters: (attacker: Node2D, target: Node2D)
signal combat_ended(attacker, target)

## Emitted when damage is dealt. Parameters: (attacker: Node2D, target: Node2D, damage: float)
signal damage_dealt(attacker, target, damage)

## Emitted when an NPC/target is killed. Parameters: (attacker: Node2D, target: Node2D)
signal target_killed(attacker, target)

# ===== View State Events =====
## View states for camera navigation
enum ViewState {
	GROUND,    ## Main gameplay view at ground level
	SKY,       ## Sky cloudbox view for structures/farms
	BARTENDER  ## Bartender view for NPC dialogue
}

## UI element types for centralized management
enum UIType {
	MODAL,        ## Generic modal window (structure info, etc.)
	CHAT_UI,      ## NPC dialogue chat interface
	INVENTORY,    ## Inventory screen (future)
	PAUSE_MENU,   ## Pause menu (future)
	SETTINGS      ## Settings screen (future)
}

## Emitted when the view state changes. Parameters: (new_state: ViewState, old_state: ViewState)
signal view_state_changed(new_state, old_state)

## Emitted when a view transition completes
signal view_transition_completed(view_state)

# ===== Modal State Events =====
## Emitted when a modal is opened. Parameters: (modal: Control)
signal modal_opened(modal)

## Emitted when a modal is closed. Parameters: (modal: Control)
signal modal_closed(modal)

## Emitted when NPC dialogue is requested. Parameters: (npc: Node2D, npc_ulid: PackedByteArray)
## The npc_ulid can be used to query Rust for NPC data (name, type, stats, etc.)
signal npc_dialogue_requested(npc, npc_ulid)

## Emitted when NPC dialogue is closed
signal npc_dialogue_closed()

## Emitted when ESC key is pressed (for centralized handling)
signal escape_pressed()

# ===== Achievement & Quest Events =====
## Emitted when an achievement is unlocked. Parameters: (achievement_id: String)
signal achievement_unlocked(achievement_id)

## Emitted when a quest is started. Parameters: (quest_id: String)
signal quest_started(quest_id)

## Emitted when a quest is completed. Parameters: (quest_id: String, rewards: Dictionary)
signal quest_completed(quest_id, rewards)

## Emitted when quest progress updates. Parameters: (quest_id: String, progress: float)
signal quest_progress_updated(quest_id, progress)

# ===== Mini-game Events =====
## Emitted when a mini-game starts. Parameters: (game_type: String)
signal minigame_started(game_type)

## Emitted when a mini-game ends. Parameters: (game_type: String, score: int, won: bool)
signal minigame_ended(game_type, score, won)

# ===== Audio Events =====
## Emitted when music should change. Parameters: (track_name: String)
signal music_change_requested(track_name)

## Emitted when a sound effect should play. Parameters: (sfx_name: String)
signal sfx_play_requested(sfx_name)

## Emitted when audio settings change. Parameters: (setting: String, value: float)
signal audio_settings_changed(setting, value)

# ===== Spawn Events =====
## Emitted when an ally should spawn. Parameters: (ally_type: String, position: Vector2, initial_target: Vector2)
signal ally_spawn_requested(ally_type, position, initial_target)

## Emitted when a monster should spawn. Parameters: (monster_type: String, position: Vector2, initial_target: Vector2)
signal monster_spawn_requested(monster_type, position, initial_target)

## Emitted when an ally respawn is needed. Parameters: (ally_type: String)
signal ally_respawn_requested(ally_type)

## Emitted when a spawn wave starts. Parameters: (wave_number: int)
signal spawn_wave_started(wave_number)


var transition_scene: CanvasLayer = null

# ===== State Management =====
## Current view state
var current_view_state: ViewState = ViewState.GROUND

## UI Registry - centralized storage for all UI elements
## Note: Can store Control, CanvasLayer, or any Node-based UI
var ui_registry: Dictionary = {}

## UI State Stack - tracks which UIs are currently open (LIFO order)
var ui_state_stack: Array[UIType] = []

## Bartender scene reference (background scene, not a UI element)
var bartender_scene: Control = null

# ===== Spawn Management =====
## Reference to the background for terrain queries
var background_ref: Node = null

## Spawn timing configuration
const MONSTER_SPAWN_INTERVAL: float = 5.0  # Spawn a wave every 5 seconds (faster waves!)
const RESPAWN_CHECK_INTERVAL: float = 3.0  # Check for respawns every 3 seconds
const MIN_WAVE_SIZE: int = 4  # Minimum monsters per wave
const MAX_WAVE_SIZE: int = 10  # Maximum monsters per wave

## Spawn state
var monster_spawn_timer: float = 0.0
var respawn_check_timer: float = 0.0
var spawn_enabled: bool = false
var _debug_printed_process: bool = false


func _ready() -> void:
	# Connect to screen transition requests
	screen_transition_requested.connect(_on_screen_transition_requested)

	# Setup all UI elements FIRST (synchronously so they're ready for other managers)
	_setup_ui_elements()

	# Load and add transition scene (deferred to avoid blocking)
	call_deferred("_setup_transition_layer")


func _process(delta: float) -> void:
	# Only process spawns if enabled
	if not spawn_enabled or not background_ref:
		return

	# RUST COMBAT: Monster spawning is now handled by Rust (disabled GDScript spawning)
	# Rust handles all spawning (allies + monsters) with proper timing and caps
	# GDScript only handles the spawn event by instantiating NPCs from the pool

	# Update respawn check timer (allies only - monsters handled by Rust)
	respawn_check_timer += delta
	if respawn_check_timer >= RESPAWN_CHECK_INTERVAL:
		respawn_check_timer = 0.0
		_check_respawns()


## Setup the transition layer
func _setup_transition_layer() -> void:
	var transition_packed = load("res://gameplay/transition/transition.tscn")
	if transition_packed:
		transition_scene = transition_packed.instantiate()
		get_tree().root.add_child.call_deferred(transition_scene)
	else:
		push_error("Failed to load transition scene")


## Setup all UI elements - SINGLE SOURCE OF TRUTH
## All UIs are created, instantiated, and registered here
func _setup_ui_elements() -> void:
	# Setup Modal (for structures, dialogs, etc.)
	_setup_modal_ui()

	# Setup ChatUI (for NPC dialogues)
	_setup_chat_ui()

	# Future UIs can be added here:
	# _setup_inventory_ui()
	# _setup_pause_menu_ui()
	# _setup_settings_ui()


## Setup Modal UI
func _setup_modal_ui() -> void:
	var modal_scene = load("res://nodes/ui/modal/modal.tscn")
	if not modal_scene:
		push_error("EventManager: Failed to load modal scene")
		return

	var modal = modal_scene.instantiate()
	if not modal:
		push_error("EventManager: Failed to instantiate modal")
		return

	# Add to tree deferred (tree is busy during _ready)
	get_tree().root.add_child.call_deferred(modal)

	# Connect modal signals (Modal class always has modal_closed signal)
	modal.modal_closed.connect(_on_modal_closed_internally)

	# Register in UI system immediately (modal exists, just not in tree yet)
	register_ui(UIType.MODAL, modal)


## Internal handler for modal closed (from EventManager-owned modal)
func _on_modal_closed_internally() -> void:
	# Remove from UI stack
	hide_ui(UIType.MODAL)


## Setup ChatUI
func _setup_chat_ui() -> void:
	# ChatUI is part of the main scene, so we'll register it when main scene provides it
	# This is called from main.gd's _ready() after the scene is loaded
	pass


## Handle scene transitions with fade effect
func _on_screen_transition_requested(from_scene: String, to_scene: String) -> void:
	if not transition_scene:
		push_error("Transition scene not available - falling back to direct transition")
		var error = get_tree().change_scene_to_file(to_scene)
		if error != OK:
			push_error("Failed to change scene to: %s (Error code: %d)" % [to_scene, error])
		return

	# Use the transition scene for smooth fade
	transition_scene.transition_to(to_scene)


## Request a scene transition (convenience function)
func transition_to_scene(scene_path: String) -> void:
	var current_scene = get_tree().current_scene
	var from_scene = current_scene.scene_file_path if current_scene else "Unknown"
	screen_transition_requested.emit(from_scene, scene_path)


## Transition to introduction scene
func start_new_game() -> void:
	game_started.emit()
	transition_to_scene("res://gameplay/introduction/introduction.tscn")


## Transition to main game scene
func start_main_game() -> void:
	transition_to_scene("res://gameplay/main/main.tscn")


## Transition to title screen
func return_to_title() -> void:
	transition_to_scene("res://gameplay/title/title.tscn")


## Helper function to emit debug info about signal connections
func debug_signal_info(signal_name: String) -> void:
	var signal_list = get_signal_list()
	for sig in signal_list:
		if sig.name == signal_name:
			var connections = get_signal_connection_list(signal_name)
			print("Signal '%s' has %d connections" % [signal_name, connections.size()])
			return
	print("Signal '%s' not found" % signal_name)


## Helper function to list all available signals
func list_all_signals() -> Array:
	var signal_list = get_signal_list()
	var signal_names = []
	for sig in signal_list:
		signal_names.append(sig.name)
	return signal_names


# ===== View State Management =====

## Register the Bartender scene with EventManager
func register_bartender_scene(scene: Control) -> void:
	bartender_scene = scene
	# Start with bartender scene hidden
	if bartender_scene:
		bartender_scene.visible = false


## Request a view state change
func request_view_change(new_state: ViewState) -> void:
	if current_view_state == new_state:
		return

	var old_state = current_view_state
	current_view_state = new_state

	# Prepare the TARGET view (show what we're transitioning TO)
	_prepare_view_for_transition(new_state)

	# Emit signal so main can start the camera pan
	view_state_changed.emit(new_state, old_state)


## Prepare the target view before camera pan starts
func _prepare_view_for_transition(target_state: ViewState) -> void:
	var chat_ui = get_ui(UIType.CHAT_UI)

	# Show/hide scenes based on TARGET state
	match target_state:
		ViewState.BARTENDER:
			# Going TO bartender - show bartender scene, hide ChatUI (will show after pan)
			if bartender_scene:
				bartender_scene.visible = true
			if chat_ui:
				chat_ui.visible = false

		ViewState.GROUND, ViewState.SKY:
			# Going TO ground/sky - hide ChatUI immediately, keep bartender visible during pan
			if chat_ui:
				chat_ui.visible = false
			# NOTE: Bartender scene stays visible during pan, will be hidden after pan completes


## Get the current view state
func get_current_view() -> ViewState:
	return current_view_state


## Notify that a view transition has completed
func complete_view_transition(view_state: ViewState) -> void:

	var chat_ui = get_ui(UIType.CHAT_UI)

	# Apply final visibility states based on CURRENT view
	match view_state:
		ViewState.BARTENDER:
			# Arrived at bartender - fade in ChatUI
			if chat_ui and chat_ui.has_method("fade_in"):
				chat_ui.fade_in()
			elif chat_ui:
				chat_ui.visible = true

		ViewState.GROUND, ViewState.SKY:
			# Arrived at ground/sky - hide bartender scene
			if bartender_scene:
				bartender_scene.visible = false

	view_transition_completed.emit(view_state)


# ===== UI Management System =====

## Register a UI element with the EventManager
## This creates a persistent reference that can be shown/hidden without destruction
func register_ui(ui_type: UIType, ui_element: Node) -> void:
	if ui_registry.has(ui_type):
		push_warning("EventManager: UI type %s already registered, replacing" % UIType.keys()[ui_type])

	ui_registry[ui_type] = ui_element

	# Ensure UI starts hidden (will be shown when needed)
	ui_element.visible = false



## Unregister a UI element (for cleanup)
func unregister_ui(ui_type: UIType) -> void:
	if ui_registry.has(ui_type):
		ui_registry.erase(ui_type)


## Get a UI element by type
func get_ui(ui_type: UIType) -> Node:
	return ui_registry.get(ui_type, null)


## Check if a UI type is registered and ready
func is_ui_ready(ui_type: UIType) -> bool:
	return ui_registry.has(ui_type)


## Show a UI element (adds to stack and makes visible)
func show_ui(ui_type: UIType) -> void:
	var ui_element = get_ui(ui_type)

	if not ui_element:
		push_error("EventManager: Cannot show UI - %s not registered" % UIType.keys()[ui_type])
		return

	# Check if already in stack
	if ui_state_stack.has(ui_type):
		return

	# Add to stack and show
	ui_state_stack.push_back(ui_type)
	ui_element.visible = true

	# Register with InputManager if it's a blocking UI (modal, chat, etc.)
	if _is_blocking_ui(ui_type):
		InputManager.register_modal(ui_element)


	# Emit appropriate signal
	match ui_type:
		UIType.MODAL:
			modal_opened.emit(ui_element)
		UIType.CHAT_UI:
			pass  # ChatUI has its own fade-in logic


## Hide a UI element (removes from stack and hides)
func hide_ui(ui_type: UIType) -> void:
	var ui_element = get_ui(ui_type)

	if not ui_element:
		push_warning("EventManager: Cannot hide UI - %s not registered (ignoring)" % UIType.keys()[ui_type])
		return

	# Check if UI is actually in the stack before trying to hide
	var index = ui_state_stack.find(ui_type)
	if index == -1:
		push_warning("EventManager: UI %s not in stack, already hidden (ignoring)" % UIType.keys()[ui_type])
		return

	# Remove from stack
	ui_state_stack.remove_at(index)

	# Hide the element
	ui_element.visible = false

	# Unregister from InputManager if it was blocking
	if _is_blocking_ui(ui_type):
		InputManager.unregister_modal(ui_element)


	# Emit appropriate signal
	match ui_type:
		UIType.MODAL:
			modal_closed.emit(ui_element)
		UIType.CHAT_UI:
			pass  # ChatUI has its own fade-out logic


## Check if a UI type blocks background input
func _is_blocking_ui(ui_type: UIType) -> bool:
	match ui_type:
		UIType.MODAL, UIType.CHAT_UI, UIType.PAUSE_MENU, UIType.SETTINGS:
			return true
		_:
			return false


## Get the topmost (most recent) UI from the stack
func get_top_ui() -> UIType:
	if ui_state_stack.is_empty():
		return -1  # No UI open
	return ui_state_stack.back()


## Check if any UI is currently open
func has_active_ui() -> bool:
	return not ui_state_stack.is_empty()


## Close the topmost UI (for ESC key handling)
func close_top_ui() -> void:
	if ui_state_stack.is_empty():
		push_warning("EventManager: No UI to close (stack is empty)")
		return

	var top_ui = ui_state_stack.back()
	hide_ui(top_ui)


# ===== Legacy Modal API (for backwards compatibility) =====
# These will be deprecated once all code uses the new UI system

# ===== NPC Dialogue Management =====

## Request NPC dialogue (emits signal that main scene will handle)
## Pass the NPC node and its ULID - main scene will query Rust for data
func request_npc_dialogue(npc: Node2D, npc_ulid: PackedByteArray) -> void:
	npc_dialogue_requested.emit(npc, npc_ulid)


## Close NPC dialogue
func close_npc_dialogue() -> void:
	npc_dialogue_closed.emit()


# ===== ESC Key Handling =====

## Handle ESC key press - determines context and takes appropriate action
## Priority: Active UI > View Reset > Pause
func handle_escape() -> void:
	var top_ui = get_top_ui()

	# Handle based on current context (highest priority first)
	if has_active_ui():
		_handle_escape_from_ui(top_ui)
	elif _is_away_from_ground():
		_handle_escape_return_to_ground()
	else:
		_handle_escape_at_ground()


## Check if player is away from ground view
func _is_away_from_ground() -> bool:
	return current_view_state != ViewState.GROUND


## Handle ESC when a UI is open - close the topmost UI
func _handle_escape_from_ui(ui_type: UIType) -> void:

	# Special handling for specific UI types
	match ui_type:
		UIType.CHAT_UI:
			# ChatUI needs full dialogue close flow
			close_npc_dialogue()

		UIType.MODAL:
			# Modal has its own close() animation, trigger it
			var modal = get_ui(UIType.MODAL)
			if modal and modal.has_method("close"):
				modal.close()  # This will emit modal_closed signal which StructureManager handles
			else:
				close_top_ui()

		_:
			# Generic UI close
			close_top_ui()


## Handle ESC when away from ground - reset view to ground
func _handle_escape_return_to_ground() -> void:
	request_view_change(ViewState.GROUND)


## Handle ESC at ground level - emit signal for pause menu, etc.
func _handle_escape_at_ground() -> void:
	escape_pressed.emit()


# ===== Spawn Management Functions =====

## Initialize spawn system with background reference
func setup_spawn_system(background: Node) -> void:
	if not background:
		push_error("EventManager: Cannot setup spawn system - background is null")
		return
	background_ref = background


## Enable or disable spawn processing
func set_spawn_enabled(enabled: bool) -> void:
	spawn_enabled = enabled


## Calculate a safe spawn position in the lower 70% of walkable area
func calculate_spawn_position(x_position: float) -> Vector2:
	if not background_ref or not background_ref.has_method("get_walkable_y_bounds"):
		push_error("EventManager: Cannot calculate spawn position - background not available")
		return Vector2.ZERO

	var y_bounds = background_ref.get_walkable_y_bounds(x_position)
	# Spawn in lower 70% of walkable area to avoid floating appearance on hills
	var min_y = y_bounds.x
	var max_y = y_bounds.y
	var bottom_70_percent = min_y + (max_y - min_y) * 0.3
	var spawn_y = randf_range(bottom_70_percent, max_y)

	return Vector2(x_position, spawn_y)


## Request spawn of an ally at a specific position
func request_ally_spawn(ally_type: String, spawn_pos: Vector2, initial_target: Vector2 = Vector2.ZERO) -> void:
	ally_spawn_requested.emit(ally_type, spawn_pos, initial_target)


## Request spawn of a monster at a specific position
func request_monster_spawn(monster_type: String, spawn_pos: Vector2, initial_target: Vector2 = Vector2.ZERO) -> void:
	monster_spawn_requested.emit(monster_type, spawn_pos, initial_target)


## Internal: Request a random monster spawn at edge of screen
func _request_random_monster_spawn() -> void:
	if not background_ref:
		push_error("EventManager: Cannot spawn monster - background_ref is null")
		return

	# Random monster type
	var monster_types = ["mushroom", "goblin", "eyebeast", "skeleton"]
	var monster_type = monster_types[randi() % monster_types.size()]

	# Get safe rect from background
	var safe_rect: Rect2
	if "safe_rectangle" in background_ref:
		safe_rect = background_ref.safe_rectangle
	else:
		# Fallback to viewport size
		var viewport_size = GameplayCache.get_viewport_rect().size
		safe_rect = Rect2(-100, 0, viewport_size.x + 200, viewport_size.y)
		push_error("EventManager: Background missing safe_rectangle property - using fallback rect")

	# Spawn on left or right edge
	var spawn_x: float
	if randf() < 0.5:
		spawn_x = safe_rect.position.x + randf_range(150.0, 250.0)  # Left side
	else:
		spawn_x = safe_rect.position.x + safe_rect.size.x - randf_range(150.0, 250.0)  # Right side

	# Calculate spawn position in lower 70%
	var spawn_pos = calculate_spawn_position(spawn_x)

	# Validate position
	if background_ref.has_method("is_position_in_walkable_area"):
		if not background_ref.is_position_in_walkable_area(spawn_pos):
			# Silently skip invalid positions - this is expected behavior
			return

	# Calculate initial target toward center (using GameplayCache for viewport)
	var viewport_size = GameplayCache.get_viewport_rect().size
	var target_x = viewport_size.x / 2 + randf_range(-200.0, 200.0)
	var initial_target = calculate_spawn_position(target_x)

	# Emit spawn request
	request_monster_spawn(monster_type, spawn_pos, initial_target)


## Internal: Check if respawns are needed
func _check_respawns() -> void:
	# This will be triggered as an event that main.gd listens to
	# Main.gd will check its active ally counts and emit respawn requests
	pass


## Request respawn of a specific ally type
func request_ally_respawn(ally_type: String) -> void:
	ally_respawn_requested.emit(ally_type)
