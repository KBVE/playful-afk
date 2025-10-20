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

# ===== View State Events =====
## View states for camera navigation
enum ViewState {
	GROUND,    ## Main gameplay view at ground level
	SKY,       ## Sky cloudbox view for structures/farms
	BARTENDER  ## Bartender view for NPC dialogue
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

## Emitted when NPC dialogue is requested. Parameters: (npc: Node2D, npc_name: String, dialogue_text: String)
signal npc_dialogue_requested(npc, npc_name, dialogue_text)

## Emitted when NPC dialogue is closed
signal npc_dialogue_closed()

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


var transition_scene: CanvasLayer = null

# ===== State Management =====
## Current view state
var current_view_state: ViewState = ViewState.GROUND

## Current active modal (if any)
var active_modal: Control = null

## ChatUI reference (set by main scene)
var chat_ui: Control = null

## Bartender scene reference (set by main scene)
var bartender_scene: Control = null


func _ready() -> void:
	print("EventManager initialized - Centralized event system ready")

	# Connect to screen transition requests
	screen_transition_requested.connect(_on_screen_transition_requested)

	# Load and add transition scene (deferred to avoid blocking)
	call_deferred("_setup_transition_layer")


## Setup the transition layer
func _setup_transition_layer() -> void:
	var transition_packed = load("res://gameplay/transition/transition.tscn")
	if transition_packed:
		transition_scene = transition_packed.instantiate()
		get_tree().root.add_child.call_deferred(transition_scene)
		print("Transition layer initialized")
	else:
		push_error("Failed to load transition scene")


## Handle scene transitions with fade effect
func _on_screen_transition_requested(from_scene: String, to_scene: String) -> void:
	print("Scene transition: %s -> %s" % [from_scene, to_scene])

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

## Register the ChatUI with EventManager
func register_chat_ui(ui: Control) -> void:
	chat_ui = ui
	print("EventManager: ChatUI registered")


## Register the Bartender scene with EventManager
func register_bartender_scene(scene: Control) -> void:
	bartender_scene = scene
	# Start with bartender scene hidden
	if bartender_scene:
		bartender_scene.visible = false
	print("EventManager: Bartender scene registered")


## Request a view state change
func request_view_change(new_state: ViewState) -> void:
	if current_view_state == new_state:
		print("EventManager: Already in view state ", ViewState.keys()[new_state])
		return

	var old_state = current_view_state
	current_view_state = new_state

	# Manage UI visibility based on view state
	_manage_ui_visibility(new_state, old_state)

	print("EventManager: View state changed from ", ViewState.keys()[old_state], " to ", ViewState.keys()[new_state])
	view_state_changed.emit(new_state, old_state)


## Manage UI visibility during view transitions
func _manage_ui_visibility(new_state: ViewState, old_state: ViewState) -> void:
	# Manage Bartender scene visibility
	if bartender_scene:
		if new_state == ViewState.BARTENDER:
			# Show bartender scene when entering BARTENDER view
			bartender_scene.visible = true
			print("EventManager: Bartender scene shown")
		elif old_state == ViewState.BARTENDER and new_state != ViewState.BARTENDER:
			# Hide bartender scene when leaving BARTENDER view
			bartender_scene.visible = false
			print("EventManager: Bartender scene hidden")

	# Manage ChatUI visibility
	if not chat_ui:
		return

	# Hide ChatUI when leaving BARTENDER view
	if old_state == ViewState.BARTENDER and new_state != ViewState.BARTENDER:
		chat_ui.visible = false
		print("EventManager: ChatUI hidden (leaving bartender view)")

	# Hide ChatUI when entering BARTENDER view (will be shown after camera pan)
	if new_state == ViewState.BARTENDER:
		chat_ui.visible = false
		print("EventManager: ChatUI hidden (entering bartender view, will show after pan)")


## Get the current view state
func get_current_view() -> ViewState:
	return current_view_state


## Notify that a view transition has completed
func complete_view_transition(view_state: ViewState) -> void:
	print("EventManager: View transition completed for ", ViewState.keys()[view_state])

	# Show ChatUI when arriving at BARTENDER view
	if view_state == ViewState.BARTENDER and chat_ui:
		chat_ui.visible = true
		print("EventManager: ChatUI shown (arrived at bartender view)")

	view_transition_completed.emit(view_state)


# ===== Modal State Management =====

## Open a modal (registers it and emits signal)
func open_modal(modal: Control) -> void:
	if active_modal == modal:
		print("EventManager: Modal already open")
		return

	if active_modal:
		print("EventManager: Warning - Opening new modal while another is active")

	active_modal = modal
	print("EventManager: Modal opened - ", modal.name if modal else "null")
	modal_opened.emit(modal)


## Close the active modal
func close_modal(modal: Control = null) -> void:
	# If no modal specified, close the active one
	var modal_to_close = modal if modal else active_modal

	if not modal_to_close:
		print("EventManager: No modal to close")
		return

	if active_modal == modal_to_close:
		active_modal = null

	print("EventManager: Modal closed - ", modal_to_close.name if modal_to_close else "null")
	modal_closed.emit(modal_to_close)


## Check if a modal is currently active
func has_active_modal() -> bool:
	return active_modal != null


## Get the currently active modal
func get_active_modal() -> Control:
	return active_modal


# ===== NPC Dialogue Management =====

## Request NPC dialogue (emits signal that main scene will handle)
func request_npc_dialogue(npc: Node2D, npc_name: String, dialogue_text: String) -> void:
	print("EventManager: NPC dialogue requested - ", npc_name)
	npc_dialogue_requested.emit(npc, npc_name, dialogue_text)


## Close NPC dialogue
func close_npc_dialogue() -> void:
	print("EventManager: NPC dialogue closed")
	npc_dialogue_closed.emit()
