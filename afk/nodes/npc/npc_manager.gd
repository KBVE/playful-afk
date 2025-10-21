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

## ===== DUAL POOL SYSTEM =====

## PERSISTENT POOL - Named NPCs with permanent stats (companions, named characters)
## Pool stores character instances, stats stored separately by ULID
## Example: "Warrior Companion", "Archer Guard", "Merchant Bob"
const MAX_PERSISTENT_POOL_SIZE: int = 8
var persistent_pool: Array[Dictionary] = []  # Each entry: {character, ulid, is_active, npc_type, npc_name, ...}

## GENERIC POOL - Temporary NPCs with fresh stats each spawn (enemies, random NPCs)
## Pool recycles character instances, new stats generated per spawn
## Example: "Goblin", "Bandit", "Wolf"
const MAX_GENERIC_POOL_SIZE: int = 16
var generic_pool: Array[Dictionary] = []  # Each entry: {character, is_active, npc_type, ...}

## STATS DATABASE - All NPC stats indexed by ULID
## Key: ULID string, Value: NPCStats instance
var stats_database: Dictionary = {}

## Container for all NPCs
var foreground_container: Node2D = null

## Background reference for heightmap queries
var background_reference: Control = null

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
	# Initialize dual pool system
	_initialize_persistent_pool()
	_initialize_generic_pool()

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


## Set the Layer4Objects container reference (called from main scene)
func set_layer4_container(container: Node2D) -> void:
	foreground_container = container

	# Add any pre-allocated NPCs to the container
	for slot in generic_pool:
		if slot["character"] and not slot["character"].get_parent():
			foreground_container.add_child(slot["character"])


## Set the background reference for heightmap queries (called from main scene)
func set_background_reference(background: Control) -> void:
	background_reference = background

	for slot in persistent_pool:
		if slot["character"] and not slot["character"].get_parent():
			foreground_container.add_child(slot["character"])


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
## Y position is now dynamically queried from background heightmap based on X
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
		"is_player_controlled": false,
		"movement_bounds_x": Vector2(50.0, 1100.0)  # Full screen width (with margins)
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

	# Check if NPC reached waypoint and needs to continue to final target
	if ai_state.get("has_waypoint", false) and ai_state.get("current_state") == "Walking":
		var waypoint = ai_state.get("waypoint", Vector2.ZERO)
		var distance_to_waypoint = npc.position.distance_to(waypoint)

		# If close enough to waypoint (within 20px), move to final target
		if distance_to_waypoint < 20.0:
			var final_target = ai_state.get("final_target", Vector2.ZERO)
			ai_state["has_waypoint"] = false  # Clear waypoint

			# Move to final target
			if "controller" in npc and npc.controller:
				npc.controller.move_to_position(final_target.x)
				_ai_tween_y_position(npc, final_target.y, ai_state)
				print("NPCManager AI: %s reached waypoint, continuing to final target (%.0f, %.0f)" % [ai_state["npc_type"], final_target.x, final_target.y])

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
	# Get movement bounds from AI state
	var movement_bounds_x = ai_state.get("movement_bounds_x", Vector2(50.0, 1100.0))  # Full screen width

	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		npc.current_state = "Walking"

	# Controller executes the movement behavior
	if "controller" in npc and npc.controller:
		if npc.controller.has_method("move_to_position"):
			# Try to find a safe target position (max 10 attempts)
			var target_pos = Vector2.ZERO
			var is_safe = false
			var attempts = 0

			while attempts < 10 and not is_safe:
				# Pick random X position
				var target_x = randf_range(movement_bounds_x.x, movement_bounds_x.y)

				# Get Y bounds at that X position
				var target_y = 0.0
				if background_reference and background_reference.has_method("get_walkable_y_bounds"):
					var y_bounds = background_reference.get_walkable_y_bounds(target_x)
					target_y = randf_range(y_bounds.x, y_bounds.y)
				else:
					target_y = npc.position.y  # Keep current Y if no background

				target_pos = Vector2(target_x, target_y)

				# Check if this target position is inside the walkable polygon
				if background_reference and background_reference.has_method("is_position_in_walkable_area"):
					is_safe = background_reference.is_position_in_walkable_area(target_pos)
				else:
					is_safe = true  # Fallback: allow movement if no background reference

				attempts += 1

			# If no safe position found after 10 attempts, just idle instead
			if not is_safe:
				print("NPCManager AI: No safe position found for %s after 10 attempts, going idle" % ai_state["npc_type"])
				_ai_start_idle(npc, ai_state)
				return

			# Waypoint pathfinding: Complex → Safe Rectangle → Complex
			# Check if we need a waypoint through the safe zone
			var use_waypoint = false
			var waypoint_pos = Vector2.ZERO

			if background_reference and background_reference.has_method("is_in_safe_rectangle"):
				var start_in_safe = background_reference.is_in_safe_rectangle(npc.position)
				var target_in_safe = background_reference.is_in_safe_rectangle(target_pos)

				# If start and target are in different zones, use waypoint
				if not start_in_safe or not target_in_safe:
					if background_reference.has_method("get_safe_waypoint"):
						waypoint_pos = background_reference.get_safe_waypoint(npc.position, target_pos)
						use_waypoint = true

			# Store waypoint in AI state for multi-step movement
			if use_waypoint:
				ai_state["has_waypoint"] = true
				ai_state["waypoint"] = waypoint_pos
				ai_state["final_target"] = target_pos

				# Move to waypoint first
				npc.controller.move_to_position(waypoint_pos.x)
				_ai_tween_y_position(npc, waypoint_pos.y, ai_state)
				print("NPCManager AI: %s moving to waypoint (%.0f, %.0f) then to target (%.0f, %.0f)" % [ai_state["npc_type"], waypoint_pos.x, waypoint_pos.y, target_pos.x, target_pos.y])
			else:
				# Direct movement (no waypoint needed)
				ai_state["has_waypoint"] = false
				npc.controller.move_to_position(target_pos.x)
				_ai_tween_y_position(npc, target_pos.y, ai_state)
				print("NPCManager AI: %s walking directly to (%.0f, %.0f)" % [ai_state["npc_type"], target_pos.x, target_pos.y])


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


## AI: Smoothly tween Y position with natural curve
func _ai_tween_y_position(npc: Node2D, target_y: float, ai_state: Dictionary) -> void:
	# Kill any existing Y tween for this NPC
	if ai_state.has("y_tween") and ai_state["y_tween"]:
		var old_tween = ai_state["y_tween"]
		if old_tween.is_valid():
			old_tween.kill()

	# Calculate distance-based duration (longer distance = longer time)
	var distance = abs(target_y - npc.position.y)
	var duration = clamp(distance / 100.0, 1.0, 3.0)  # 1-3 seconds based on distance

	# Create smooth tween with ease in-out curve
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)  # Sine curve for natural arc movement
	tween.tween_property(npc, "position:y", target_y, duration)

	# Store tween reference in AI state for cleanup
	ai_state["y_tween"] = tween


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
	var max_z_index = 0

	# Update all pooled characters from generic and persistent pools
	for slot in generic_pool:
		if slot["is_active"] and slot["character"] != null:
			_update_character_z_index(slot["character"])
			max_z_index = max(max_z_index, slot["character"].z_index)

	for slot in persistent_pool:
		if slot["is_active"] and slot["character"] != null:
			_update_character_z_index(slot["character"])
			max_z_index = max(max_z_index, slot["character"].z_index)

	# Cat always stays in front (highest z-index + 1)
	if cat:
		cat.z_index = max_z_index + 1


## ===== DUAL POOL MANAGEMENT =====

## Initialize the persistent pool with empty slots
func _initialize_persistent_pool() -> void:
	persistent_pool.clear()
	for i in range(MAX_PERSISTENT_POOL_SIZE):
		persistent_pool.append({
			"character": null,
			"ulid": "",  # ULID key to look up stats in stats_database
			"is_active": false,
			"slot": i,
			"npc_type": "",
			"npc_name": "",  # Display name (e.g., "Warrior Companion")
			"movement_bounds": Vector2(100.0, 1052.0)
		})
	print("NPCManager: Persistent pool initialized with %d slots" % MAX_PERSISTENT_POOL_SIZE)


## Initialize the generic pool with pre-allocated NPCs
func _initialize_generic_pool() -> void:
	generic_pool.clear()

	# Pre-allocate warriors (4-8 instances)
	var num_warriors = 6
	for i in range(num_warriors):
		_preallocate_generic_npc("warrior", i)

	# Pre-allocate archers (4-8 instances)
	var num_archers = 6
	for i in range(num_archers):
		_preallocate_generic_npc("archer", num_warriors + i)

	# Fill remaining slots with empty entries
	for i in range(num_warriors + num_archers, MAX_GENERIC_POOL_SIZE):
		generic_pool.append({
			"character": null,
			"is_active": false,
			"slot": i,
			"npc_type": ""
		})

	print("NPCManager: Generic pool initialized with %d warriors, %d archers" % [num_warriors, num_archers])


## Pre-allocate a generic NPC instance (but don't activate it yet)
func _preallocate_generic_npc(npc_type: String, slot_index: int) -> void:
	if not NPC_REGISTRY.has(npc_type):
		push_error("NPCManager: Cannot preallocate unknown NPC type: %s" % npc_type)
		return

	# Load and instantiate the NPC scene
	var npc_scene = load(NPC_REGISTRY[npc_type]["scene"])
	var npc = npc_scene.instantiate()

	# Add to scene but keep hidden
	if foreground_container:
		foreground_container.add_child(npc)

	npc.visible = false
	npc.position = Vector2.ZERO
	npc.process_mode = Node.PROCESS_MODE_DISABLED

	# Store in pool
	generic_pool.append({
		"character": npc,
		"is_active": false,
		"slot": slot_index,
		"npc_type": npc_type
	})


## Add a persistent NPC (keeps stats across activations)
func add_persistent_npc(
	npc_type: String,
	npc_name: String,
	position: Vector2,
	initial_stats: NPCStats = null,
	activate: bool = true,
	movement_bounds: Vector2 = Vector2(100.0, 1052.0)
) -> Node2D:
	# Find empty slot in persistent pool
	var slot_index = -1
	for i in range(persistent_pool.size()):
		if persistent_pool[i]["character"] == null:
			slot_index = i
			break

	if slot_index == -1:
		push_error("NPCManager: Persistent pool is full!")
		return null

	# Create NPC instance
	if not NPC_REGISTRY.has(npc_type):
		push_error("NPCManager: Unknown NPC type: %s" % npc_type)
		return null

	var npc_scene = load(NPC_REGISTRY[npc_type]["scene"])
	var npc = npc_scene.instantiate()

	# Create or assign stats
	var npc_stats = initial_stats if initial_stats else NPCStats.new()

	# Store stats in database by ULID
	stats_database[npc_stats.ulid] = npc_stats

	# Store in persistent pool
	var slot = persistent_pool[slot_index]
	slot["character"] = npc
	slot["ulid"] = npc_stats.ulid  # Store ULID reference
	slot["is_active"] = activate
	slot["npc_type"] = npc_type
	slot["npc_name"] = npc_name
	slot["movement_bounds"] = movement_bounds

	# Add to scene
	if foreground_container:
		foreground_container.add_child(npc)
		npc.position = position
		npc.visible = activate

		# Assign stats to NPC (NPC stores reference)
		if "stats" in npc:
			npc.stats = npc_stats

		# Set z-index
		_update_character_z_index(npc)

		# Register AI if active
		if activate:
			register_npc_ai(npc, npc_type)

	print("NPCManager: Added persistent NPC '%s' (%s) to slot %d (ULID: %s)" % [
		npc_name, npc_type, slot_index, npc_stats.ulid
	])

	return npc


## Get a generic NPC from pool (creates fresh stats each time)
## Y bounds are now dynamically queried from background heightmap based on movement
func get_generic_npc(npc_type: String, position: Vector2) -> Node2D:
	# Find inactive NPC in generic pool
	var slot_index = -1
	for i in range(generic_pool.size()):
		var slot = generic_pool[i]
		if not slot["is_active"] and (slot["npc_type"] == npc_type or slot["character"] == null):
			slot_index = i
			break

	if slot_index == -1:
		push_error("NPCManager: No available generic NPCs of type %s" % npc_type)
		return null

	var slot = generic_pool[slot_index]

	# Create NPC if slot is empty
	if slot["character"] == null:
		if not NPC_REGISTRY.has(npc_type):
			push_error("NPCManager: Unknown NPC type: %s" % npc_type)
			return null

		var npc_scene = load(NPC_REGISTRY[npc_type]["scene"])
		var npc = npc_scene.instantiate()

		slot["character"] = npc
		slot["npc_type"] = npc_type

		if foreground_container:
			foreground_container.add_child(npc)

	var npc = slot["character"]

	# Generate FRESH stats for this spawn with random name
	var fresh_stats = NPCStats.new(100.0, 100.0, 100.0, 100.0, NPCStats.Emotion.NEUTRAL, npc_type)

	# Store in database (use hex string as key for dictionary compatibility)
	var ulid_key = ULID.to_hex(fresh_stats.ulid)
	stats_database[ulid_key] = fresh_stats

	# Assign to NPC
	if "stats" in npc:
		npc.stats = fresh_stats

	# Activate NPC
	slot["is_active"] = true
	npc.position = position
	npc.visible = true
	npc.process_mode = Node.PROCESS_MODE_INHERIT
	_update_character_z_index(npc)

	# Register with AI system for autonomous behavior (Y queried from heightmap)
	register_npc_ai(npc, npc_type)

	print("NPCManager: Spawned generic %s '%s' (ULID: %s)" % [npc_type, fresh_stats.npc_name, ULID.to_str(fresh_stats.ulid)])

	return npc


## Return generic NPC to pool
func return_generic_npc(npc: Node2D) -> void:
	# Find NPC in generic pool
	for slot in generic_pool:
		if slot["character"] == npc:
			slot["is_active"] = false
			npc.visible = false
			npc.position = Vector2.ZERO

			# Remove stats from database (generic NPCs don't persist stats)
			if "stats" in npc and npc.stats:
				var ulid_key = ULID.to_hex(npc.stats.ulid)
				stats_database.erase(ulid_key)
				npc.stats = null

			# Clear AI state
			if _npc_ai_states.has(npc):
				_npc_ai_states.erase(npc)

			print("NPCManager: Returned generic NPC to pool")
			return

	push_warning("NPCManager: NPC not found in generic pool")


## Get NPC stats by binary ULID
func get_stats(ulid: PackedByteArray) -> NPCStats:
	var ulid_key = ULID.to_hex(ulid)
	return stats_database.get(ulid_key, null)


## Get NPC stats by hex string key (for internal use)
func get_stats_by_key(ulid_key: String) -> NPCStats:
	return stats_database.get(ulid_key, null)


## Get persistent NPC stats by name
func get_persistent_npc_stats_by_name(npc_name: String) -> NPCStats:
	for slot in persistent_pool:
		if slot["npc_name"] == npc_name and slot.has("ulid"):
			return stats_database.get(slot["ulid"], null)
	return null


## Save all NPC stats (both persistent and generic currently active)
func save_all_stats() -> Dictionary:
	var saved_data = {}

	# Save all stats from database with metadata
	for ulid_key in stats_database:
		var stats = stats_database[ulid_key]

		# Find if this is a persistent NPC
		var npc_name = ""
		var npc_type = ""
		for slot in persistent_pool:
			if slot.has("ulid") and slot["ulid"] == ulid_key:
				npc_name = slot["npc_name"]
				npc_type = slot["npc_type"]
				break

		saved_data[ulid_key] = {
			"stats": stats.to_dict(),
			"npc_name": npc_name,
			"npc_type": npc_type,
			"is_persistent": npc_name != ""
		}

	return saved_data


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
