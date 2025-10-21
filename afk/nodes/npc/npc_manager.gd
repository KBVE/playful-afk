extends Node

## NPCManager - Global NPC Management System
## Provides centralized access to all NPCs in the game, especially the virtual pet
## Access via: NPCManager.cat anywhere in your code

# Virtual Pet Reference
var cat: Cat = null
var cat_scene: PackedScene = preload("res://nodes/npc/cat/cat.tscn")

## ===== NPC REGISTRY SYSTEM =====
## Central registry for all NPC types - add new NPCs here!
## Each entry contains: scene_path, class_name, and optional metadata

const NPC_REGISTRY: Dictionary = {
	"warrior": {
		"scene": "res://nodes/npc/warrior/warrior.tscn",
		"class_name": "Warrior",
		"category": "melee",
		"ai_profile": {
			"idle_weight": 60,      # Prefers action over idle
			"walk_weight": 40,
			"state_change_min": 3.0,  # Min seconds between state changes
			"state_change_max": 8.0,  # Max seconds between state changes
			"movement_speed": 1.0     # Movement speed multiplier
		}
	},
	"archer": {
		"scene": "res://nodes/npc/archer/archer.tscn",
		"class_name": "Archer",
		"category": "ranged",
		"ai_profile": {
			"idle_weight": 70,      # Prefers idle (patient archer)
			"walk_weight": 30,
			"state_change_min": 3.0,
			"state_change_max": 8.0,
			"movement_speed": 0.8   # Slightly slower movement
		}
	}
	# Future NPCs: Add here! Example:
	# "mage": {
	#     "scene": "res://nodes/npc/mage/mage.tscn",
	#     "class_name": "Mage",
	#     "category": "magic",
	#     "ai_profile": {
	#         "idle_weight": 80,
	#         "walk_weight": 20,
	#         "state_change_min": 4.0,
	#         "state_change_max": 10.0,
	#         "movement_speed": 0.6
	#     }
	# }
}

# Loaded NPC scenes cache
var _npc_scenes: Dictionary = {}

# NPC Singleton References (for globally accessible NPCs like cat/warrior)
var warrior: Warrior = null

# UI Sprite Cache - Pre-cloned sprites for UI display (performance optimization)
# Automatically populated from NPC_REGISTRY + cat
var ui_sprite_cache: Dictionary = {}

# Character Pool for Layer4 NPCs (scroll with Layer4 at 0.9 speed)
const MAX_POOL_SIZE: int = 16
var character_pool: Array[Dictionary] = []
var foreground_container: Node2D = null

## ===== NPC AI SYSTEM =====
## Centralized AI controller for all pooled NPCs

# AI state tracking for each NPC
var _npc_ai_states: Dictionary = {}  # Key: NPC instance, Value: AI state data

# AI update timer
var _ai_timer: Timer = null
const AI_UPDATE_INTERVAL: float = 0.1  # Check AI every 100ms

# Z-index update timer for depth sorting
var _z_index_timer: Timer = null
const Z_INDEX_UPDATE_INTERVAL: float = 0.1  # Update z-index every 100ms

# Save/Load data
var npc_save_data: Dictionary = {}


func _ready() -> void:
	# Load all NPC scenes from registry
	_load_npc_scenes()

	# Initialize the cat (virtual pet)
	_initialize_cat()

	# Initialize the warrior NPC
	_initialize_warrior()

	# Initialize character pool (empty slots)
	_initialize_character_pool()

	# Initialize UI sprite cache (create pre-cloned sprites for UI)
	_initialize_ui_sprite_cache()

	# Initialize AI system
	_initialize_ai_system()

	# Connect to save/load events
	EventManager.game_saved.connect(_on_game_saved)
	EventManager.game_loaded.connect(_on_game_loaded)

	print("NPCManager initialized - Cat, Warrior, Character Pool, AI System, and UI Sprite Cache ready")


## ===== NPC REGISTRY HELPER FUNCTIONS =====

## Load all NPC scenes from the registry
func _load_npc_scenes() -> void:
	for npc_type in NPC_REGISTRY:
		var npc_data = NPC_REGISTRY[npc_type]
		var scene = load(npc_data["scene"]) as PackedScene
		if scene:
			_npc_scenes[npc_type] = scene
			print("NPCManager: Loaded %s scene" % npc_type)
		else:
			push_error("NPCManager: Failed to load scene for %s at %s" % [npc_type, npc_data["scene"]])


## Get NPC scene by type name (e.g., "warrior", "archer", "mage")
func get_npc_scene(npc_type: String) -> PackedScene:
	if _npc_scenes.has(npc_type):
		return _npc_scenes[npc_type]
	else:
		push_error("NPCManager: Unknown NPC type '%s'" % npc_type)
		return null


## Create an NPC instance by type
func create_npc(npc_type: String) -> Node2D:
	var scene = get_npc_scene(npc_type)
	if scene:
		return scene.instantiate() as Node2D
	return null


## Get all registered NPC types
func get_registered_npc_types() -> Array:
	return NPC_REGISTRY.keys()


## Check if NPC type exists in registry
func is_valid_npc_type(npc_type: String) -> bool:
	return NPC_REGISTRY.has(npc_type)


## ===== INITIALIZATION FUNCTIONS =====

## Initialize the cat virtual pet
func _initialize_cat() -> void:
	if cat == null:
		cat = cat_scene.instantiate()
		add_child(cat)

		# Load saved data if available
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])

		print("Cat virtual pet instantiated and ready")


## Save cat data to dictionary
func save_cat_data() -> Dictionary:
	if cat == null:
		return {}

	return {
		"hunger": cat.hunger,
		"happiness": cat.happiness,
		"health": cat.health,
		"level": cat.level,
		"experience": cat.experience,
		"current_state": cat.current_state,
		"position": {
			"x": cat.position.x,
			"y": cat.position.y
		}
	}


## Load cat data from dictionary
func _load_cat_data(data: Dictionary) -> void:
	if cat == null:
		return

	cat.hunger = data.get("hunger", 100.0)
	cat.happiness = data.get("happiness", 100.0)
	cat.health = data.get("health", 100.0)
	cat.level = data.get("level", 1)
	cat.experience = data.get("experience", 0)
	cat.current_state = data.get("current_state", "Idle")

	# Restore position if available
	if data.has("position"):
		var pos = data["position"]
		cat.position = Vector2(pos.get("x", 0), pos.get("y", 0))

	print("Cat data loaded successfully")


## Reset cat to default state
func reset_cat() -> void:
	if cat:
		cat.queue_free()
		cat = null

	_initialize_cat()
	print("Cat has been reset to default state")


## Initialize the warrior NPC
func _initialize_warrior() -> void:
	if warrior == null:
		warrior = create_npc("warrior") as Warrior
		if warrior:
			add_child(warrior)

			# Load saved data if available
			if npc_save_data.has("warrior"):
				_load_warrior_data(npc_save_data["warrior"])

			print("Warrior NPC instantiated and ready")
		else:
			push_error("NPCManager: Failed to create warrior NPC")


## Save warrior data to dictionary
func save_warrior_data() -> Dictionary:
	if warrior == null:
		return {}

	return {
		"health": warrior.health,
		"strength": warrior.strength,
		"defense": warrior.defense,
		"level": warrior.level,
		"current_state": warrior.current_state,
		"position": {
			"x": warrior.position.x,
			"y": warrior.position.y
		}
	}


## Load warrior data from dictionary
func _load_warrior_data(data: Dictionary) -> void:
	if warrior == null:
		return

	warrior.health = data.get("health", 100.0)
	warrior.strength = data.get("strength", 50.0)
	warrior.defense = data.get("defense", 50.0)
	warrior.level = data.get("level", 1)
	warrior.current_state = data.get("current_state", "Idle")

	# Restore position if available
	if data.has("position"):
		var pos = data["position"]
		warrior.position = Vector2(pos.get("x", 0), pos.get("y", 0))

	print("Warrior data loaded successfully")


## Reset warrior to default state
func reset_warrior() -> void:
	if warrior:
		warrior.queue_free()
		warrior = null

	_initialize_warrior()
	print("Warrior has been reset to default state")




## Handle game save event
func _on_game_saved(success: bool) -> void:
	if success:
		npc_save_data["cat"] = save_cat_data()
		npc_save_data["warrior"] = save_warrior_data()
		print("NPC data saved")


## Handle game load event
func _on_game_loaded(success: bool) -> void:
	if success:
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])
		if npc_save_data.has("warrior"):
			_load_warrior_data(npc_save_data["warrior"])
		print("NPC data loaded")


## Get all NPC data for saving to file
func get_save_data() -> Dictionary:
	return {
		"cat": save_cat_data(),
		"warrior": save_warrior_data()
	}


## Load all NPC data from save file
func load_save_data(data: Dictionary) -> void:
	npc_save_data = data

	if npc_save_data.has("cat"):
		_load_cat_data(npc_save_data["cat"])

	if npc_save_data.has("warrior"):
		_load_warrior_data(npc_save_data["warrior"])


## ===== CHARACTER POOL SYSTEM =====
## Manages Layer4 characters that scroll with background Layer4 at 0.9 speed

## Initialize character pool with empty slots
func _initialize_character_pool() -> void:
	character_pool.clear()

	for i in range(MAX_POOL_SIZE):
		character_pool.append({
			"character": null,
			"is_active": false,
			"slot_index": i,
			"position": Vector2.ZERO,
			"character_type": ""  # "warrior", "cat", etc.
		})

	print("Character pool initialized with %d slots" % MAX_POOL_SIZE)


## Set the Layer4Objects container reference (called from main scene)
func set_layer4_container(container: Node2D) -> void:
	foreground_container = container
	print("Layer4Objects container set - characters will scroll with Layer4 at 0.9 speed")


## Add warrior to pool at a specific slot
## Add NPC to character pool at specified slot (data-driven approach)
## @param npc_type: Type of NPC from NPC_REGISTRY (e.g., "warrior", "archer", "mage")
## @param slot_index: Pool slot index (0-15)
## @param position: World position
## @param activate: Whether to activate the NPC immediately
## @param movement_bounds: X bounds for random movement (min_x, max_x)
## @return: The created NPC instance or null if failed
func add_npc_to_pool(npc_type: String, slot_index: int, position: Vector2 = Vector2.ZERO, activate: bool = false, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> Node2D:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		push_error("NPCManager: Invalid slot index: %d" % slot_index)
		return null

	if not is_valid_npc_type(npc_type):
		push_error("NPCManager: Unknown NPC type '%s'. Available types: %s" % [npc_type, str(get_registered_npc_types())])
		return null

	# Create a new NPC instance
	var new_npc = create_npc(npc_type)
	if not new_npc:
		return null

	if _add_character_to_slot(new_npc, slot_index, position, activate, npc_type, movement_bounds):
		return new_npc
	else:
		new_npc.queue_free()
		return null


## LEGACY: Add warrior to character pool (kept for backwards compatibility)
## Use add_npc_to_pool("warrior", ...) instead
func add_warrior_to_pool(slot_index: int, position: Vector2 = Vector2.ZERO, activate: bool = false, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> Node2D:
	return add_npc_to_pool("warrior", slot_index, position, activate, movement_bounds)


## LEGACY: Add archer to character pool (kept for backwards compatibility)
## Use add_npc_to_pool("archer", ...) instead
func add_archer_to_pool(slot_index: int, position: Vector2 = Vector2.ZERO, activate: bool = false, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> Node2D:
	return add_npc_to_pool("archer", slot_index, position, activate, movement_bounds)


## Internal: Add any character to a slot
func _add_character_to_slot(character: Node2D, slot_index: int, position: Vector2, activate: bool, char_type: String, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> bool:
	if not foreground_container:
		push_error("ForegroundCharacters container not set! Call set_layer4_container() first.")
		return false

	var slot = character_pool[slot_index]

	# Remove existing character if any
	if slot["character"] != null:
		push_warning("Slot %d already occupied, replacing character" % slot_index)
		_remove_character_from_slot(slot_index)

	# Add character to slot
	slot["character"] = character
	slot["position"] = position
	slot["is_active"] = activate
	slot["character_type"] = char_type
	slot["movement_bounds"] = movement_bounds  # Store for AI system

	# Add to scene (in Layer4Objects - will scroll with Layer4)
	foreground_container.add_child(character)
	character.position = position
	character.visible = activate

	# Set z-index based on Y position for proper depth sorting
	_update_character_z_index(character)

	# Configure character
	if not activate:
		_deactivate_character(character)
	else:
		_activate_character(character, movement_bounds)

	print("Added %s to pool slot %d (active: %s)" % [char_type, slot_index, activate])
	return true


## Activate a character in a slot
func activate_pool_character(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		return false

	var slot = character_pool[slot_index]
	if slot["character"] == null or slot["is_active"]:
		return false

	slot["is_active"] = true
	var character = slot["character"]
	character.visible = true
	_activate_character(character)

	print("Activated character in slot %d" % slot_index)
	return true


## Deactivate a character in a slot
func deactivate_pool_character(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		return false

	var slot = character_pool[slot_index]
	if slot["character"] == null or not slot["is_active"]:
		return false

	slot["is_active"] = false
	var character = slot["character"]
	character.visible = false
	_deactivate_character(character)

	print("Deactivated character in slot %d" % slot_index)
	return true


## Internal: Activate character logic
func _activate_character(character: Node2D, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> void:
	# Enable physics
	if character.has_method("set_physics_process"):
		character.set_physics_process(true)

	# Get character type for AI registration
	var char_type = get_npc_type(character)

	# Register with centralized AI system
	if char_type and NPC_REGISTRY.has(char_type):
		register_npc_ai(character, char_type)

		# Disable individual NPC's state timer (AI system handles it now)
		if character.has_node("StateTimer"):
			var timer = character.get_node("StateTimer")
			if timer is Timer:
				timer.stop()

		# DO NOT start controller's random movement timer!
		# The centralized AI system will call controller.move_to_position() as needed


## Internal: Deactivate character logic
func _deactivate_character(character: Node2D) -> void:
	# Disable physics
	if character.has_method("set_physics_process"):
		character.set_physics_process(false)

	# Unregister from AI system
	unregister_npc_ai(character)

	# Stop controller movement if available
	if character.has_method("get") and "controller" in character and character.controller:
		if character.controller.has_method("stop_random_movement"):
			character.controller.stop_random_movement()

	# Stop state timer
	if character.has_node("StateTimer"):
		var timer = character.get_node("StateTimer")
		if timer is Timer:
			timer.stop()


## Internal: Remove character from slot
func _remove_character_from_slot(slot_index: int) -> void:
	var slot = character_pool[slot_index]
	if slot["character"] != null:
		slot["character"].queue_free()
		slot["character"] = null
		slot["is_active"] = false
		slot["character_type"] = ""


## Update all active pooled characters
func update_pool_characters(delta: float) -> void:
	for slot in character_pool:
		if slot["is_active"] and slot["character"] != null:
			var character = slot["character"]
			# Update Warrior controllers
			if character is Warrior and character.controller:
				character.controller.update_movement(delta)


## Get active character count
func get_active_pool_count() -> int:
	var count = 0
	for slot in character_pool:
		if slot["is_active"]:
			count += 1
	return count


## Get all active pooled characters
func get_active_pool_characters() -> Array:
	var active = []
	for slot in character_pool:
		if slot["is_active"] and slot["character"] != null:
			active.append(slot["character"])
	return active


## ===== NPC AI SYSTEM =====
## Centralized autonomous behavior controller for all pooled NPCs

## Initialize the AI system
func _initialize_ai_system() -> void:
	# Create AI update timer
	_ai_timer = Timer.new()
	_ai_timer.wait_time = AI_UPDATE_INTERVAL
	_ai_timer.one_shot = false
	_ai_timer.timeout.connect(_on_ai_timer_timeout)
	add_child(_ai_timer)
	_ai_timer.start()

	# Create Z-index update timer for depth sorting
	_z_index_timer = Timer.new()
	_z_index_timer.wait_time = Z_INDEX_UPDATE_INTERVAL
	_z_index_timer.one_shot = false
	_z_index_timer.timeout.connect(_on_z_index_timer_timeout)
	add_child(_z_index_timer)
	_z_index_timer.start()

	print("NPCManager: AI system initialized with %0.1fs update interval" % AI_UPDATE_INTERVAL)


## Register NPC for AI control
func register_npc_ai(npc: Node2D, npc_type: String) -> void:
	if not NPC_REGISTRY.has(npc_type):
		push_error("NPCManager: Cannot register AI for unknown NPC type: %s" % npc_type)
		return

	var ai_profile = NPC_REGISTRY[npc_type].get("ai_profile", {})

	# Create AI state for this NPC
	_npc_ai_states[npc] = {
		"npc_type": npc_type,
		"ai_profile": ai_profile,
		"current_state": "Idle",
		"time_until_next_change": randf_range(
			ai_profile.get("state_change_min", 3.0),
			ai_profile.get("state_change_max", 8.0)
		),
		"movement_direction": Vector2.ZERO,
		"is_player_controlled": false
	}

	# Connect to controller signals for bidirectional communication
	if "controller" in npc and npc.controller:
		var controller = npc.controller

		# Connect movement signals
		if controller.has_signal("movement_started"):
			controller.movement_started.connect(_on_controller_movement_started.bind(npc))
		if controller.has_signal("movement_completed"):
			controller.movement_completed.connect(_on_controller_movement_completed.bind(npc))
		if controller.has_signal("movement_interrupted"):
			controller.movement_interrupted.connect(_on_controller_movement_interrupted.bind(npc))

		print("NPCManager: Connected controller signals for %s" % npc_type)

	print("NPCManager: Registered AI for %s (%s)" % [npc_type, npc.name])


## Unregister NPC from AI control
func unregister_npc_ai(npc: Node2D) -> void:
	if _npc_ai_states.has(npc):
		_npc_ai_states.erase(npc)
		print("NPCManager: Unregistered AI for NPC: %s" % npc.name)


## AI timer callback - update all NPC AI states
func _on_ai_timer_timeout() -> void:
	for npc in _npc_ai_states.keys():
		if not is_instance_valid(npc):
			_npc_ai_states.erase(npc)
			continue

		_update_npc_ai(npc)


## Update AI for a single NPC
func _update_npc_ai(npc: Node2D) -> void:
	var ai_state = _npc_ai_states[npc]

	# Skip if player controlled
	if ai_state["is_player_controlled"]:
		return

	# Count down to next state change
	ai_state["time_until_next_change"] -= AI_UPDATE_INTERVAL

	# Time to change state?
	if ai_state["time_until_next_change"] <= 0:
		_ai_change_state(npc, ai_state)


## Change NPC AI state (idle -> walking -> idle)
func _ai_change_state(npc: Node2D, ai_state: Dictionary) -> void:
	var ai_profile = ai_state["ai_profile"]

	# Get state weights
	var idle_weight = ai_profile.get("idle_weight", 60)
	var walk_weight = ai_profile.get("walk_weight", 40)

	# Weighted random state selection
	var total_weight = idle_weight + walk_weight
	var random_value = randf() * total_weight

	var new_state = "Idle"
	if random_value > idle_weight:
		new_state = "Walking"

	# Update AI state
	ai_state["current_state"] = new_state

	# Schedule next state change
	ai_state["time_until_next_change"] = randf_range(
		ai_profile.get("state_change_min", 3.0),
		ai_profile.get("state_change_max", 8.0)
	)

	# Apply state to NPC via controller or directly
	if new_state == "Walking":
		_ai_start_walking(npc, ai_state)
	else:
		_ai_start_idle(npc, ai_state)


## AI: Start NPC walking
func _ai_start_walking(npc: Node2D, ai_state: Dictionary) -> void:
	# Get movement bounds from character pool
	var movement_bounds = Vector2(100.0, 1052.0)
	for slot in character_pool:
		if slot["character"] == npc:
			movement_bounds = slot.get("movement_bounds", movement_bounds)
			break

	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		npc.current_state = "Walking"

	# Controller executes the movement behavior
	if "controller" in npc and npc.controller:
		if npc.controller.has_method("move_to_position"):
			# Generate random target position within bounds
			var target_x = randf_range(movement_bounds.x, movement_bounds.y)
			npc.controller.move_to_position(target_x)
			print("NPCManager AI: %s walking to %d" % [ai_state["npc_type"], target_x])


## AI: Start NPC idle
func _ai_start_idle(npc: Node2D, ai_state: Dictionary) -> void:
	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		npc.current_state = "Idle"

	# Controller stops movement
	if "controller" in npc and npc.controller:
		if npc.controller.has_method("stop_auto_movement"):
			npc.controller.stop_auto_movement()
			print("NPCManager AI: %s idling" % ai_state["npc_type"])


## Set NPC player control mode
func set_npc_player_controlled(npc: Node2D, controlled: bool) -> void:
	if _npc_ai_states.has(npc):
		_npc_ai_states[npc]["is_player_controlled"] = controlled
		print("NPCManager: NPC %s player_controlled = %s" % [npc.name, controlled])


## Get AI state for debugging
func get_npc_ai_state(npc: Node2D) -> Dictionary:
	return _npc_ai_states.get(npc, {})


## ===== CONTROLLER SIGNAL HANDLERS (Bidirectional Communication) =====

## Controller signals when movement starts
func _on_controller_movement_started(target_position: float, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	print("NPCManager AI: Received movement_started from %s controller (target: %s)" % [ai_state["npc_type"], target_position])

	# AI system is aware controller has started executing the movement command
	# Could use this to track state, cancel other actions, etc.


## Controller signals when movement completes successfully
func _on_controller_movement_completed(final_position: float, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	print("NPCManager AI: Received movement_completed from %s controller (final: %s)" % [ai_state["npc_type"], final_position])

	# Movement completed - update NPC state to Idle
	if "current_state" in npc:
		npc.current_state = "Idle"
	ai_state["current_state"] = "Idle"

	# This enables reactive behavior (e.g., could immediately start combat if enemy nearby)


## Controller signals when movement is interrupted/stopped early
func _on_controller_movement_interrupted(npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	print("NPCManager AI: Received movement_interrupted from %s controller" % ai_state["npc_type"])

	# Movement was stopped - update NPC state to Idle
	if "current_state" in npc:
		npc.current_state = "Idle"
	ai_state["current_state"] = "Idle"

	# AI could react by choosing a different target - timer will handle next decision


## ===== Z-INDEX / DEPTH SORTING SYSTEM =====

## Update z-index for all characters based on Y position
func _on_z_index_timer_timeout() -> void:
	_update_all_characters_z_index()


## Update z-index for a single character based on its Y position
func _update_character_z_index(character: Node2D) -> void:
	if character:
		# Z-index = Y position (characters lower on screen appear in front)
		character.z_index = int(character.position.y)


## Update z-index for all active characters
func _update_all_characters_z_index() -> void:
	# Update cat z-index
	if cat:
		_update_character_z_index(cat)

	# Update all pooled characters
	for slot in character_pool:
		if slot["is_active"] and slot["character"] != null:
			_update_character_z_index(slot["character"])


## ===== UI SPRITE CACHE SYSTEM =====
## Pre-cloned sprites for UI display (ChatUI, Modals, etc.)
## Performance optimization - avoids cloning sprites every time

## Initialize UI sprite cache - create pre-cloned sprites for each NPC type
func _initialize_ui_sprite_cache() -> void:
	# Create cat UI sprite (singleton instance)
	if cat and cat.has_node("AnimatedSprite2D"):
		var cat_sprite = cat.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if cat_sprite:
			var cat_ui_sprite = cat_sprite.duplicate() as AnimatedSprite2D
			ui_sprite_cache["cat"] = cat_ui_sprite
			print("NPCManager: Cat UI sprite cached")

	# Create warrior UI sprite (singleton instance)
	if warrior and warrior.has_node("AnimatedSprite2D"):
		var warrior_sprite = warrior.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if warrior_sprite:
			var warrior_ui_sprite = warrior_sprite.duplicate() as AnimatedSprite2D
			ui_sprite_cache["warrior"] = warrior_ui_sprite
			print("NPCManager: Warrior UI sprite cached")

	# Create UI sprites for all registered NPCs (data-driven)
	for npc_type in NPC_REGISTRY:
		# Skip warrior since it's already cached as singleton
		if npc_type == "warrior":
			continue

		await _cache_npc_ui_sprite(npc_type)

	print("NPCManager: UI sprite cache initialized with %d types" % ui_sprite_cache.size())


## Helper: Cache UI sprite for a single NPC type
func _cache_npc_ui_sprite(npc_type: String) -> void:
	var temp_npc = create_npc(npc_type)
	if not temp_npc:
		push_error("NPCManager: Failed to create temporary NPC for UI caching: %s" % npc_type)
		return

	add_child(temp_npc)
	await get_tree().process_frame  # Wait for NPC to initialize

	if temp_npc.has_node("AnimatedSprite2D"):
		var npc_sprite = temp_npc.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if npc_sprite:
			var npc_ui_sprite = npc_sprite.duplicate() as AnimatedSprite2D
			ui_sprite_cache[npc_type] = npc_ui_sprite
			print("NPCManager: %s UI sprite cached" % npc_type.capitalize())

	# Unregister from InputManager before freeing
	if InputManager:
		InputManager.unregister_interactive_object(temp_npc)

	temp_npc.queue_free()


## Get cached UI sprite for an NPC type (e.g., "cat", "warrior")
## Returns the pre-cloned sprite ready to be added to UI
## IMPORTANT: Do NOT duplicate or modify this sprite - use it directly
func get_ui_sprite(npc_type: String) -> AnimatedSprite2D:
	if ui_sprite_cache.has(npc_type) and ui_sprite_cache[npc_type] != null:
		return ui_sprite_cache[npc_type]

	push_warning("NPCManager: No UI sprite cached for type: ", npc_type)
	return null


## Get NPC type name from NPC node (used to look up cached sprite)
## Uses class name matching against NPC_REGISTRY for automatic type detection
func get_npc_type(npc: Node2D) -> String:
	# Special case: Cat
	if npc is Cat:
		return "cat"

	# Check against registry using class name
	var npc_class_name = npc.get_class()
	for npc_type in NPC_REGISTRY:
		var registry_class = NPC_REGISTRY[npc_type]["class_name"]
		if npc_class_name == registry_class:
			return npc_type

	# Legacy fallback for backwards compatibility
	if npc is Warrior:
		return "warrior"
	elif npc is Archer:
		return "archer"

	push_warning("NPCManager: Unknown NPC type for %s" % npc)
	return ""
