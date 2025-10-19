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
## Emitted when the game is paused. Parameters: (paused: bool)
signal game_paused(paused)

## Emitted when the game is saved. Parameters: (save_success: bool)
signal game_saved(save_success)

## Emitted when the game is loaded. Parameters: (load_success: bool)
signal game_loaded(load_success)

## Emitted when game data is reset
signal game_reset()

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


func _ready() -> void:
	print("EventManager initialized - Centralized event system ready")


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
