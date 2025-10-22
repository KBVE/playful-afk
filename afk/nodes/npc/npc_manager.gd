extends Node

## NPCManager - Global NPC Management System
## Provides centralized access to all NPCs in the game, especially the virtual pet
## Access via: NPCManager.cat anywhere in your code

## ===== NPC TYPE SYSTEMS =====
## Core enums that define NPC behavior and combat

## Faction enum - determines who can attack whom
enum Faction {
	ALLY,      # Player's allies (warriors, archers, cat, etc.) - don't attack each other
	MONSTER,   # Hostile creatures (chickens, etc.) - attack allies
	NEUTRAL    # Neutral NPCs that don't participate in combat
}

## Combat Type enum - determines how an NPC fights
enum CombatType {
	NONE,      # Non-combatant (cat, passive NPCs)
	MELEE,     # Close-range physical attacks (warriors, knights)
	RANGED,    # Long-range projectile attacks (archers, crossbowmen)
	MAGIC      # Spell-based attacks (mages, wizards)
}

## NPC State enum (using bitwise flags for easy combinations)
## Can combine states: e.g., WALKING | COMBAT | PURSUING | HURT
## NOTE: Some states are behavioral (COMBAT, PURSUING), others are visual (ATTACKING, DAMAGED, DEAD)
enum NPCState {
	IDLE = 1 << 0,        # 1:   Idle (not moving, not attacking)
	WALKING = 1 << 1,     # 2:   Walking/moving
	ATTACKING = 1 << 2,   # 4:   Currently attacking (animation playing)
	WANDERING = 1 << 3,   # 8:   Normal wandering/idle behavior (no combat)
	COMBAT = 1 << 4,      # 16:  Engaged in combat
	RETREATING = 1 << 5,  # 32:  Retreating from enemy (archer kiting)
	PURSUING = 1 << 6,    # 64:  Moving towards enemy
	HURT = 1 << 7,        # 128: Low health - triggers defensive behavior (not the same as DAMAGED animation)
	DAMAGED = 1 << 8,     # 256: Taking damage - plays hurt/damage animation
	DEAD = 1 << 9         # 512: Dead - plays death animation
}

## Monster Type enum - additional categorization for monsters
enum MonsterType {
	ANIMAL,      # Animal creatures (chicken, rabbit, etc.)
	DEMON,       # Demonic/evil creatures
	PASSIVE,     # Doesn't attack/do damage (can be combined with other types)
	AGGRESSIVE   # Actively seeks combat and attacks
}

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
	},
	"chicken": {
		"scene": "res://nodes/npc/chicken/chicken.tscn",
		"class_name": "Chicken",
		"category": "monster",
		"monster_types": [MonsterType.ANIMAL, MonsterType.PASSIVE],
		"ai_profile": {
			"idle_weight": 70,      # Chickens prefer to stay idle
			"walk_weight": 30,
			"state_change_min": 2.0,  # Faster state changes
			"state_change_max": 5.0,
			"movement_speed": 0.6   # Slower movement (it's a chicken!)
		}
	},
	"mushroom": {
		"scene": "res://nodes/npc/mushroom/mushroom.tscn",
		"class_name": "Mushroom",
		"category": "monster",
		"monster_types": [MonsterType.AGGRESSIVE],
		"ai_profile": {
			"idle_weight": 50,      # Mushrooms are more active
			"walk_weight": 50,
			"state_change_min": 1.5,  # Quick state changes
			"state_change_max": 4.0,
			"movement_speed": 0.7   # Medium speed
		}
	},
	"goblin": {
		"scene": "res://nodes/npc/goblin/goblin.tscn",
		"class_name": "Goblin",
		"category": "monster",
		"monster_types": [MonsterType.AGGRESSIVE],
		"ai_profile": {
			"idle_weight": 40,      # Goblins are aggressive
			"walk_weight": 60,      # Move around more than mushrooms
			"state_change_min": 1.0,  # Very quick state changes
			"state_change_max": 3.0,
			"movement_speed": 0.8   # Faster than mushrooms
		}
	},
	"eyebeast": {
		"scene": "res://nodes/npc/eyebeast/eyebeast.tscn",
		"class_name": "Eyebeast",
		"category": "monster",
		"monster_types": [MonsterType.AGGRESSIVE],
		"ai_profile": {
			"idle_weight": 30,      # Eyebeasts are very aggressive
			"walk_weight": 70,      # Constantly moving (flying)
			"state_change_min": 0.8,  # Very quick state changes (agile flyer)
			"state_change_max": 2.5,
			"movement_speed": 0.9   # Fastest monster (flying)
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

# UI Sprite Cache - Pre-cloned sprites for UI display (performance optimization)
# Automatically populated from NPC_REGISTRY + cat singleton
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
## Current allocation: 6 warriors + 6 archers + 8 chickens + 6 mushrooms + 6 goblins + 6 eyebeasts = 38 total
const MAX_GENERIC_POOL_SIZE: int = 40
var generic_pool: Array[Dictionary] = []  # Each entry: {character, is_active, npc_type, ...}

## STATS DATABASE - All NPC stats indexed by ULID
## Key: ULID string, Value: NPCStats instance
var stats_database: Dictionary = {}

## Container for all NPCs
var foreground_container: Node2D = null

## Background reference for heightmap queries
var background_reference: Control = null

# Emoji Manager for chat bubbles
var emoji_manager: EmojiManager = null

## ===== RELEASE EFFECT POOL =====
## Pool of release effects for death animations

# Release effect pool
const RELEASE_POOL_SIZE: int = 4
var release_effect_pool: Array[Node2D] = []
var release_effect_scene: PackedScene = preload("res://nodes/npc/common/release.tscn")

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
	# Initialize character pool (empty slots)
	# Initialize dual pool system
	_initialize_persistent_pool()
	_initialize_generic_pool()

	# Initialize UI sprite cache (create pre-cloned sprites for UI)
	_initialize_ui_sprite_cache()

	# Initialize AI system
	_initialize_ai_system()

	# Initialize Emoji Manager for chat bubbles
	_initialize_emoji_manager()

	# Initialize Release Effect Pool for death animations
	# (Called after foreground_container is potentially set)
	# NOTE: Pool will be empty until set_layer4_container is called

	# Connect to save/load events
	EventManager.game_saved.connect(_on_game_saved)
	EventManager.game_loaded.connect(_on_game_loaded)

	# Connect to EnvironmentManager events
	if EnvironmentManager and EnvironmentManager.has_signal("catflag_spawned"):
		EnvironmentManager.catflag_spawned.connect(_on_catflag_spawned)


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

		# Connect cat's call for help signal
		if cat.has_signal("call_for_help"):
			cat.call_for_help.connect(_on_cat_call_for_help)

		# Load saved data if available
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])


## Handle cat calling for help when enemies are nearby
func _on_cat_call_for_help(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return

	# Find idle allies (warriors, archers) to send to help
	for npc in _npc_ai_states.keys():
		if not is_instance_valid(npc):
			continue

		# Skip if NPC is already in combat
		var ai_state = _npc_ai_states.get(npc)
		if ai_state.get("combat_target"):
			continue

		# Check if NPC is an ally (warrior or archer)
		var npc_type = ai_state.get("npc_type", "")
		if npc_type not in ["warrior", "archer"]:
			continue

		# Check if NPC is idle (not already moving to a target)
		var combat_type = CombatType.NONE
		if "combat_type" in npc:
			combat_type = npc.combat_type

		# Send this ally to engage the enemy
		var movement_target = _get_movement_target(npc)
		if movement_target.has_method("move_to_position"):
			# Set the enemy as combat target
			ai_state["combat_target"] = enemy
			ai_state["time_until_next_change"] = 2.0

			# Move toward the enemy
			movement_target.move_to_position(enemy.global_position.x)
			_ai_tween_y_position(npc, enemy.global_position.y, ai_state)

			# Set NPC to walking state
			if "current_state" in npc:
				npc.current_state = NPCState.WALKING


## Handle catflag being spawned - send idle NPCs to flag location
func _on_catflag_spawned(flag: Node2D, flag_position: Vector2) -> void:
	if not is_instance_valid(flag):
		return

	# Find idle allies (warriors, archers) to send to flag
	for npc in _npc_ai_states.keys():
		if not is_instance_valid(npc):
			continue

		# Skip if NPC is already in combat
		var ai_state = _npc_ai_states.get(npc)
		if ai_state.get("combat_target"):
			continue

		# Check if NPC is an ally (warrior or archer)
		var npc_type = ai_state.get("npc_type", "")
		if npc_type not in ["warrior", "archer"]:
			continue

		# Send this ally to the flag location
		var movement_target = _get_movement_target(npc)
		if movement_target.has_method("move_to_position"):
			# Move toward the flag position
			movement_target.move_to_position(flag_position.x)
			_ai_tween_y_position(npc, flag_position.y, ai_state)

			# Set NPC to walking state
			if "current_state" in npc:
				npc.current_state = NPCState.WALKING

			# Store flag as rally point (not combat target)
			ai_state["rally_point"] = flag_position
			ai_state["time_until_next_change"] = 2.0


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

## Initialize the warrior NPC
# NOTE: Warrior singleton removed - warriors are now managed through the generic pool system
# All warrior save/load is handled by the pool save system




## Handle game save event
func _on_game_saved(success: bool) -> void:
	if success:
		npc_save_data["cat"] = save_cat_data()
		# Warrior save removed - now handled by pool system
		print("NPC data saved")


## Handle game load event
func _on_game_loaded(success: bool) -> void:
	if success:
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])
		# Warrior load removed - now handled by pool system
		print("NPC data loaded")


## Get all NPC data for saving to file
func get_save_data() -> Dictionary:
	return {
		"cat": save_cat_data()
		# Warrior save removed - now handled by pool system
	}


## Load all NPC data from save file
func load_save_data(data: Dictionary) -> void:
	npc_save_data = data

	if npc_save_data.has("cat"):
		_load_cat_data(npc_save_data["cat"])

	# Warrior load removed - now handled by pool system


## Set the Layer4Objects container reference (called from main scene)
func set_layer4_container(container: Node2D) -> void:
	foreground_container = container

	# Add any pre-allocated NPCs to the container
	for slot in generic_pool:
		if slot["character"] and not slot["character"].get_parent():
			foreground_container.add_child(slot["character"])

	# Initialize release effect pool now that we have foreground_container
	_initialize_release_effect_pool()


## Set the background reference for heightmap queries (called from main scene)
func set_background_reference(background: Control) -> void:
	background_reference = background

	for slot in persistent_pool:
		if slot["character"] and not slot["character"].get_parent():
			foreground_container.add_child(slot["character"])


## ===== SAFE MOVEMENT HELPERS =====

## Clamp a position to safe bounds using background reference
## This is the centralized function for ALL movement - ensures NPCs stay in bounds
func clamp_to_safe_bounds(position: Vector2) -> Vector2:
	if not background_reference:
		return position

	# Check if position is in safe rectangle
	if background_reference.has_method("is_in_safe_rectangle"):
		if background_reference.is_in_safe_rectangle(position):
			return position  # Already safe

	# Position is unsafe - clamp to nearest point in safe rectangle
	# Get safe rectangle from background
	if "safe_rectangle" in background_reference:
		var safe_rect = background_reference.safe_rectangle
		var clamped_x = clamp(position.x, safe_rect.position.x, safe_rect.position.x + safe_rect.size.x)
		var clamped_y = clamp(position.y, safe_rect.position.y, safe_rect.position.y + safe_rect.size.y)
		return Vector2(clamped_x, clamped_y)

	return position


## Get a safe Y position for a given X coordinate
## Uses background heightmap to ensure NPCs stay on walkable terrain
func get_safe_y_for_x(x: float, current_y: float) -> float:
	if not background_reference or not background_reference.has_method("get_walkable_y_bounds"):
		return current_y

	var y_bounds = background_reference.get_walkable_y_bounds(x)
	# Clamp to walkable range (y_bounds.x = min_y, y_bounds.y = max_y)
	return clamp(current_y, y_bounds.x, y_bounds.y)


## Move NPC to target position with automatic bounds checking
## This is the ONE function all movement should use
func move_npc_to_position_safe(npc: Node2D, target_x: float, target_y: float = -1.0) -> void:
	if not is_instance_valid(npc):
		return

	# If no target_y specified, calculate safe Y for the target X
	if target_y < 0:
		target_y = get_safe_y_for_x(target_x, npc.global_position.y)

	# Create target position
	var target_pos = Vector2(target_x, target_y)

	# Clamp to safe bounds
	var safe_pos = clamp_to_safe_bounds(target_pos)

	# Get the movement target (controller or NPC itself)
	var movement_target = _get_movement_target(npc)

	# Move to safe position
	if movement_target and movement_target.has_method("move_to_position"):
		movement_target.move_to_position(safe_pos.x)

		# Tween Y position if NPC has AI state
		var ai_state = _npc_ai_states.get(npc)
		if ai_state:
			_ai_tween_y_position(npc, safe_pos.y, ai_state)
		else:
			# No AI state, just set position directly
			npc.global_position.y = safe_pos.y


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


## Initialize Emoji Manager for chat bubbles
func _initialize_emoji_manager() -> void:
	emoji_manager = EmojiManager.new()
	add_child(emoji_manager)
	print("NPCManager: Emoji Manager initialized for chat bubbles")


## Initialize Release Effect Pool for death animations
func _initialize_release_effect_pool() -> void:
	# Pre-allocate release effect pool
	for i in range(RELEASE_POOL_SIZE):
		var effect = release_effect_scene.instantiate()
		effect.visible = false
		effect.scale = Vector2(0.5, 0.5)  # Scale down to 80%

		# Add to foreground container if available, otherwise add to NPCManager
		if foreground_container:
			foreground_container.add_child(effect)
		else:
			add_child(effect)

		release_effect_pool.append(effect)

	print("NPCManager: Release Effect Pool initialized with %d effects" % RELEASE_POOL_SIZE)


## Get available release effect from pool (or create new if all busy)
func _get_release_effect() -> Node2D:
	# Find first inactive effect (check if valid first)
	for effect in release_effect_pool:
		if is_instance_valid(effect) and not effect.visible:
			return effect

	# Clean up any freed nodes from pool
	release_effect_pool = release_effect_pool.filter(func(effect): return is_instance_valid(effect))

	# All busy - create a new one and add to pool
	print("NPCManager: All release effects busy, creating new one")
	var new_effect = release_effect_scene.instantiate()
	new_effect.scale = Vector2(0.5, 0.5)  # Scale down to 80%

	if foreground_container:
		foreground_container.add_child(new_effect)
	else:
		add_child(new_effect)

	release_effect_pool.append(new_effect)
	return new_effect


## Play release effect at position when NPC dies
func play_release_effect(position: Vector2, on_midpoint: Callable) -> void:
	var effect = _get_release_effect()
	if effect:
		# Connect to midpoint signal (one-shot)
		if effect.has_signal("midpoint_reached"):
			effect.midpoint_reached.connect(on_midpoint, CONNECT_ONE_SHOT)

		# Play effect at position
		effect.play_at(position)


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
		"current_state": NPCState.IDLE,  # Use enum instead of string
		"time_until_next_change": randf_range(
			ai_profile.get("state_change_min", 3.0),
			ai_profile.get("state_change_max", 8.0)
		),
		"movement_direction": Vector2.ZERO,
		"is_player_controlled": false,
		"movement_bounds_x": Vector2(50.0, 1100.0)  # Full screen width (with margins)
	}

	# Connect to movement signals for bidirectional communication
	# Try controller first (warrior), then direct NPC signals (archer)
	var signal_source = null
	if "controller" in npc and npc.controller:
		signal_source = npc.controller
	else:
		signal_source = npc

	if signal_source:
		# Connect movement signals if they exist (check not already connected)
		if signal_source.has_signal("movement_started"):
			if not signal_source.movement_started.is_connected(_on_controller_movement_started):
				signal_source.movement_started.connect(_on_controller_movement_started.bind(npc))
		if signal_source.has_signal("movement_completed"):
			if not signal_source.movement_completed.is_connected(_on_controller_movement_completed):
				signal_source.movement_completed.connect(_on_controller_movement_completed.bind(npc))
		if signal_source.has_signal("movement_interrupted"):
			if not signal_source.movement_interrupted.is_connected(_on_controller_movement_interrupted):
				signal_source.movement_interrupted.connect(_on_controller_movement_interrupted.bind(npc))

		# Connect state change signal for tracking (check not already connected)
		if signal_source.has_signal("state_changed"):
			if not signal_source.state_changed.is_connected(_on_npc_state_changed):
				signal_source.state_changed.connect(_on_npc_state_changed.bind(npc))


## Unregister NPC from AI control
func unregister_npc_ai(npc: Node2D) -> void:
	if _npc_ai_states.has(npc):
		_npc_ai_states.erase(npc)


## AI timer callback - update all NPC AI states
func _on_ai_timer_timeout() -> void:
	for npc in _npc_ai_states.keys():
		if not is_instance_valid(npc):
			_npc_ai_states.erase(npc)
			continue

		_update_npc_ai(npc)


## Get cached viewport center X position (uses GameplayCache singleton)
func _get_viewport_center_x() -> float:
	if GameplayCache:
		return GameplayCache.get_viewport_center_x()
	# Fallback if GameplayCache not loaded yet
	return get_tree().root.get_viewport_rect().size.x / 2.0


## Get movement target (controller or direct NPC)
func _get_movement_target(npc: Node2D) -> Node2D:
	if "controller" in npc and npc.controller:
		return npc.controller
	return npc


## Update AI for a single NPC
func _update_npc_ai(npc: Node2D) -> void:
	var ai_state = _npc_ai_states[npc]

	# Skip if player controlled
	if ai_state["is_player_controlled"]:
		return

	# Get NPC type (unused but kept for future debugging)
	var _npc_type = ai_state.get("npc_type", "")

	# COMBAT BEHAVIOR - Check for nearby enemies first (highest priority)
	if CombatManager:
		# Don't do anything if currently attacking (animation playing)
		if CombatManager.has_state(npc, NPCManager.NPCState.ATTACKING):
			return

		# Find nearest enemy
		var target = CombatManager.find_nearest_target(npc, 300.0)

		if target:
			# Get NPC's combat type directly from property (use enum instead of string comparison for performance)
			var combat_type = npc.combat_type if "combat_type" in npc else CombatType.NONE

			# MELEE COMBAT (Warriors, Knights, etc.)
			if combat_type == NPCManager.CombatType.MELEE:
				var movement_target = _get_movement_target(npc)
				var distance_to_target = npc.global_position.distance_to(target.global_position)

				# IMPORTANT: Flip sprite to face target BEFORE checking can_melee_attack
				# The facing check happens inside can_melee_attack, so we need to face first
				if "animated_sprite" in npc and npc.animated_sprite:
					var to_target = target.global_position - npc.global_position
					npc.animated_sprite.flip_h = to_target.x < 0

				if CombatManager.can_melee_attack(npc, target):
					# In range and facing - ATTACK!
					# Stop warrior movement before attacking (warrior must stand still to swing)
					if movement_target.has_method("stop_auto_movement"):
						movement_target.stop_auto_movement()

					# Set NPC to attacking state (triggers attack animation)
					if "current_state" in npc:
						npc.current_state = NPCState.ATTACKING  # Use enum

					# Execute combat logic (damage calculation, state tracking)
					CombatManager.start_melee_attack(npc, target)
					ai_state["combat_target"] = target
					ai_state["time_until_next_change"] = 2.0
					return
				# Check if warrior is in combat range but on cooldown - STAY IN POSITION
				elif distance_to_target <= CombatManager.WARRIOR_MELEE_RANGE:
					# Warrior is close enough to attack but on cooldown
					# Stop movement and wait for cooldown
					if movement_target.has_method("stop_auto_movement"):
						movement_target.stop_auto_movement()
					ai_state["combat_target"] = target
					ai_state["time_until_next_change"] = 0.5  # Check again soon
					return
				else:
					# Not in range - move towards enemy
					# Only issue new movement command if:
					# 1. No combat target set yet, OR
					# 2. Target has moved significantly (>20px), OR
					# 3. NPC is idle (not currently moving)
					var should_move = false
					var last_target = ai_state.get("combat_target")
					var is_moving = movement_target.has_method("is_moving") and movement_target.is_moving()

					if last_target == null or last_target != target:
						should_move = true  # New target
					elif not is_moving:
						should_move = true  # NPC stopped moving
					elif last_target.global_position.distance_to(target.global_position) > 20.0:
						should_move = true  # Target moved significantly

					if should_move and movement_target.has_method("move_to_position"):
						movement_target.move_to_position(target.global_position.x)
						_ai_tween_y_position(npc, target.global_position.y, ai_state)
						ai_state["combat_target"] = target
						ai_state["last_combat_target_pos"] = target.global_position
						ai_state["time_until_next_change"] = 2.0
					return

			# RANGED COMBAT + KITING (Archers, Crossbowmen, etc.)
			elif combat_type == NPCManager.CombatType.RANGED:
				var movement_target = _get_movement_target(npc)
				var distance_to_target = npc.global_position.distance_to(target.global_position)

				# Flip sprite to face target
				if "animated_sprite" in npc and npc.animated_sprite:
					var to_target = target.global_position - npc.global_position
					npc.animated_sprite.flip_h = to_target.x < 0

				# Too close! RETREAT (kiting behavior)
				if CombatManager.should_archer_retreat(npc, target):
					# Calculate retreat direction considering ALL nearby enemies (not just one)
					var retreat_direction = Vector2.ZERO
					var nearby_enemies: Array[Node2D] = []

					# Find all enemies within threat range (150px)
					var all_potential_targets = CombatManager.find_all_valid_targets(npc, 150.0)
					for enemy in all_potential_targets:
						if is_instance_valid(enemy):
							nearby_enemies.append(enemy)

					# Calculate weighted retreat direction away from all threats
					if nearby_enemies.size() > 0:
						for enemy in nearby_enemies:
							var to_enemy = npc.global_position - enemy.global_position
							var distance = to_enemy.length()
							# Closer enemies have more weight (inverse distance)
							var weight = 1.0 / max(distance, 1.0)
							retreat_direction += to_enemy.normalized() * weight
						retreat_direction = retreat_direction.normalized()
					else:
						# Fallback: just move away from primary target
						retreat_direction = (npc.global_position - target.global_position).normalized()

					# Use health-based kiting range (extends range when hurt)
					var retreat_distance = CombatManager.get_optimal_kiting_range(npc)
					var retreat_pos = npc.global_position + (retreat_direction * retreat_distance)

					# Clamp retreat position to safe rectangle bounds
					if background_reference and background_reference.has_method("is_in_safe_rectangle"):
						# If retreat position is out of safe bounds, try to find a valid position
						if not background_reference.is_in_safe_rectangle(retreat_pos):
							# Try moving parallel to the enemy instead of directly away
							var parallel_right = Vector2(-retreat_direction.y, retreat_direction.x)
							var parallel_left = Vector2(retreat_direction.y, -retreat_direction.x)

							# Try right parallel
							var alt_pos1 = npc.global_position + (parallel_right * retreat_distance * 0.5)
							if background_reference.is_in_safe_rectangle(alt_pos1):
								retreat_pos = alt_pos1
							# Try left parallel
							elif background_reference.is_in_safe_rectangle(npc.global_position + (parallel_left * retreat_distance * 0.5)):
								retreat_pos = npc.global_position + (parallel_left * retreat_distance * 0.5)
							# Last resort: move toward nearest safe rectangle edge
							else:
								if background_reference.has_method("get_random_safe_position"):
									retreat_pos = background_reference.get_random_safe_position()
								else:
									retreat_pos = npc.global_position

					# Only retreat if not already retreating or target moved significantly
					var should_retreat = false
					var last_retreat_pos = ai_state.get("last_retreat_pos", Vector2.ZERO)
					var last_retreat_time = ai_state.get("last_retreat_time", 0.0)
					var current_time = Time.get_ticks_msec() / 1000.0
					var is_moving = movement_target.has_method("is_moving") and movement_target.is_moving()

					# Add cooldown to prevent excessive retreat recalculations (reduces tweaking)
					var retreat_cooldown = 0.5  # Only update retreat every 0.5 seconds
					var time_since_last_retreat = current_time - last_retreat_time

					if not is_moving and time_since_last_retreat >= retreat_cooldown:
						should_retreat = true  # Not currently moving and cooldown passed
					elif retreat_pos.distance_to(last_retreat_pos) > 50.0 and time_since_last_retreat >= retreat_cooldown:
						should_retreat = true  # Retreat position changed significantly (increased from 20 to 50px)

					if should_retreat and movement_target.has_method("move_to_position"):
						movement_target.move_to_position(retreat_pos.x)
						_ai_tween_y_position(npc, retreat_pos.y, ai_state)
						ai_state["combat_target"] = target
						ai_state["last_retreat_pos"] = retreat_pos
						ai_state["last_retreat_time"] = current_time
						ai_state["time_until_next_change"] = 1.0
					return

				# In good range - ATTACK!
				elif CombatManager.can_ranged_attack(npc, target):
					# Stop archer movement before attacking (archer must stand still to shoot)
					if movement_target.has_method("stop_auto_movement"):
						movement_target.stop_auto_movement()

					# Set NPC to attacking state (triggers attack animation)
					if "current_state" in npc:
						npc.current_state = NPCState.ATTACKING  # Use enum

					# Execute combat logic (projectile firing, state tracking)
					CombatManager.start_ranged_attack(npc, target, "arrow")
					ai_state["time_until_next_change"] = 2.0
					return

				# Too far - move closer
				elif distance_to_target > CombatManager.ARCHER_MAX_RANGE:
					# Only move if not already pursuing or target moved significantly
					var should_pursue = false
					var last_target = ai_state.get("combat_target")
					var is_pursuing = movement_target.has_method("is_moving") and movement_target.is_moving()

					if last_target == null or last_target != target:
						should_pursue = true  # New target
					elif not is_pursuing:
						should_pursue = true  # Stopped moving
					elif last_target.global_position.distance_to(target.global_position) > 20.0:
						should_pursue = true  # Target moved significantly

					if should_pursue and movement_target.has_method("move_to_position"):
						movement_target.move_to_position(target.global_position.x)
						_ai_tween_y_position(npc, target.global_position.y, ai_state)
						ai_state["combat_target"] = target
						ai_state["last_combat_target_pos"] = target.global_position
						ai_state["time_until_next_change"] = 2.0
					return

		# No enemies nearby - exit combat mode
		elif CombatManager.is_in_combat(npc):
			CombatManager.end_combat(npc)

	# MONSTER ROAMING BEHAVIOR - All monsters roam with bounds checking (passive and aggressive)
	# Passive monsters (chickens) roam but don't attack, aggressive monsters (mushrooms) attack + roam
	if npc is Monster:
		# Check if already has combat target (handled above)
		if not ai_state.get("combat_target"):
			var movement_target = _get_movement_target(npc)
			var is_moving = movement_target.has_method("is_moving") and movement_target.is_moving()

			# Check if monster is outside safe rectangle or hasn't picked a roam target yet
			var needs_new_target = false
			if background_reference and background_reference.has_method("is_in_safe_rectangle"):
				if not background_reference.is_in_safe_rectangle(npc.global_position):
					needs_new_target = true
				elif not ai_state.has("roam_target"):
					needs_new_target = true
				elif ai_state.has("roam_target"):
					# Check if reached target (within 30 pixels)
					var roam_target = ai_state.get("roam_target", Vector2.ZERO)
					var distance_to_target = npc.global_position.distance_to(roam_target)
					if distance_to_target < 30.0:
						needs_new_target = true

			# Pick a random position in safe rectangle and move there
			if needs_new_target and background_reference:
				# Get a safe target position (or clamp current position if out of bounds)
				var safe_pos: Vector2
				if background_reference.has_method("is_in_safe_rectangle") and not background_reference.is_in_safe_rectangle(npc.global_position):
					# Out of bounds - move towards center of safe rectangle
					if "safe_rectangle" in background_reference:
						var safe_rect = background_reference.safe_rectangle
						safe_pos = Vector2(
							safe_rect.position.x + safe_rect.size.x / 2,
							safe_rect.position.y + safe_rect.size.y / 2
						)
				elif background_reference.has_method("get_random_safe_position"):
					# In bounds - pick random safe target
					safe_pos = background_reference.get_random_safe_position()
				else:
					return  # Can't get safe position

				# Otherwise use direct _move_direction for monsters without controllers
				if "_move_direction" in npc:
					var direction = (safe_pos - npc.global_position).normalized()
					npc._move_direction = direction
					npc.current_state = NPCState.WALKING
					ai_state["roam_target"] = safe_pos
					ai_state["time_until_next_change"] = 5.0

	# Check if NPC reached waypoint and needs to continue to final target
	if ai_state.get("has_waypoint", false) and ai_state.get("current_state") == NPCState.WALKING:
		var waypoint = ai_state.get("waypoint", Vector2.ZERO)
		var distance_to_waypoint = npc.position.distance_to(waypoint)

		# If close enough to waypoint (within 20px), move to final target
		if distance_to_waypoint < 20.0:
			var final_target = ai_state.get("final_target", Vector2.ZERO)
			ai_state["has_waypoint"] = false  # Clear waypoint

			# Move to final target (controller or direct)
			var has_controller = "controller" in npc and npc.controller
			var movement_target = npc.controller if has_controller else npc

			if movement_target.has_method("move_to_position"):
				movement_target.move_to_position(final_target.x)
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

	var new_state = NPCState.IDLE  # Use enum
	if random_value > idle_weight:
		new_state = NPCState.WALKING  # Use enum

	# Update AI state
	ai_state["current_state"] = new_state

	# Schedule next state change
	ai_state["time_until_next_change"] = randf_range(
		ai_profile.get("state_change_min", 3.0),
		ai_profile.get("state_change_max", 8.0)
	)

	# Apply state to NPC via controller or directly
	if new_state == NPCState.WALKING:
		_ai_start_walking(npc, ai_state)
	else:
		_ai_start_idle(npc, ai_state)


## AI: Start NPC walking
func _ai_start_walking(npc: Node2D, ai_state: Dictionary) -> void:
	# Get movement bounds from AI state
	var movement_bounds_x = ai_state.get("movement_bounds_x", Vector2(50.0, 1100.0))  # Full screen width

	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		npc.current_state = NPCState.WALKING  # Use enum

	# Check if NPC has controller or direct movement
	var has_controller = "controller" in npc and npc.controller
	var has_move_to_position = npc.has_method("move_to_position")

	# Execute movement behavior (controller or direct)
	if has_controller or has_move_to_position:
		var movement_target = npc.controller if has_controller else npc
		if movement_target.has_method("move_to_position"):
			# Pick random X position
			var target_x = randf_range(movement_bounds_x.x, movement_bounds_x.y)

			# Get safe Y for that X position
			var target_y = get_safe_y_for_x(target_x, npc.global_position.y)

			# Create target position
			var target_pos = Vector2(target_x, target_y)

			# Clamp to safe bounds (this ensures chickens stay in bounds!)
			target_pos = clamp_to_safe_bounds(target_pos)

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
				movement_target.move_to_position(waypoint_pos.x)
				_ai_tween_y_position(npc, waypoint_pos.y, ai_state)
				print("NPCManager AI: %s moving to waypoint (%.0f, %.0f) then to target (%.0f, %.0f)" % [ai_state["npc_type"], waypoint_pos.x, waypoint_pos.y, target_pos.x, target_pos.y])
			else:
				# Direct movement (no waypoint needed)
				ai_state["has_waypoint"] = false
				movement_target.move_to_position(target_pos.x)
				_ai_tween_y_position(npc, target_pos.y, ai_state)
				print("NPCManager AI: %s walking directly to (%.0f, %.0f)" % [ai_state["npc_type"], target_pos.x, target_pos.y])


## AI: Start NPC idle
func _ai_start_idle(npc: Node2D, ai_state: Dictionary) -> void:
	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		npc.current_state = NPCState.IDLE  # Use enum

	# Stop movement (controller or direct)
	var has_controller = "controller" in npc and npc.controller
	var movement_target = npc.controller if has_controller else npc

	if movement_target.has_method("stop_auto_movement"):
		movement_target.stop_auto_movement()
		# print("NPCManager AI: %s idling" % ai_state["npc_type"])


## AI: Smoothly tween Y position with natural curve
func _ai_tween_y_position(npc: Node2D, target_y: float, ai_state: Dictionary) -> void:
	# Calculate distance to target Y
	var distance = abs(target_y - npc.position.y)

	# Skip if change is too small (< 5px) - prevents excessive tweaking
	if distance < 5.0:
		return

	# For combat situations (archers kiting), use instant movement for small changes
	# This prevents the "tweaking" effect during kiting
	var in_combat = ai_state.get("combat_target") != null
	if in_combat and distance < 20.0:
		# Small Y adjustment during combat - just set it instantly
		npc.position.y = target_y
		return

	# Kill any existing Y tween for this NPC
	if ai_state.has("y_tween") and ai_state["y_tween"]:
		var old_tween = ai_state["y_tween"]
		if old_tween.is_valid():
			old_tween.kill()

	# Calculate distance-based duration (longer distance = longer time)
	var duration = clamp(distance / 100.0, 0.5, 2.0)  # 0.5-2 seconds (faster than before)

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
		# print("NPCManager: NPC %s player_controlled = %s" % [npc.name, controlled])


## Get AI state for debugging
func get_npc_ai_state(npc: Node2D) -> Dictionary:
	return _npc_ai_states.get(npc, {})


## ===== CONTROLLER SIGNAL HANDLERS (Bidirectional Communication) =====

## Controller signals when movement starts
func _on_controller_movement_started(target_position: float, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: Received movement_started from %s controller (target: %s)" % [ai_state["npc_type"], target_position])

	# AI system is aware controller has started executing the movement command
	# Could use this to track state, cancel other actions, etc.


## Controller signals when movement completes successfully
func _on_controller_movement_completed(final_position: float, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: Received movement_completed from %s controller (final: %s)" % [ai_state["npc_type"], final_position])

	# Movement completed - update NPC state to Idle
	if "current_state" in npc:
		npc.current_state = NPCState.IDLE  # Use enum
	ai_state["current_state"] = NPCState.IDLE  # Use enum

	# This enables reactive behavior (e.g., could immediately start combat if enemy nearby)


## Controller signals when movement is interrupted/stopped early
func _on_controller_movement_interrupted(npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: Received movement_interrupted from %s controller" % ai_state["npc_type"])

	# Movement was stopped - update NPC state to Idle
	if "current_state" in npc:
		npc.current_state = NPCState.IDLE  # Use enum
	ai_state["current_state"] = NPCState.IDLE  # Use enum

	# AI could react by choosing a different target - timer will handle next decision


## NPC signals when state changes (bidirectional communication)
func _on_npc_state_changed(old_state: int, new_state: int, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: %s state changed from %d to %d" % [ai_state["npc_type"], old_state, new_state])

	# Track the state change in AI system
	ai_state["current_state"] = new_state

	# Try to show state-based emoji (10% chance)
	if emoji_manager:
		emoji_manager.try_show_state_emoji(npc, old_state, new_state)


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


## ===== STATS CREATION =====

## Create stats for a specific NPC type with configured values
func _create_stats_for_type(npc_type: String) -> NPCStats:
	match npc_type:
		"warrior":
			return NPCStats.new(
				100.0,  # HP
				50.0,   # Mana
				100.0,  # Energy
				100.0,  # Hunger
				15.0,   # Attack
				10.0,   # Defense
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		"archer":
			return NPCStats.new(
				80.0,   # HP (less than warrior)
				75.0,   # Mana (more than warrior)
				100.0,  # Energy
				100.0,  # Hunger
				12.0,   # Attack (ranged)
				5.0,    # Defense (low)
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		"chicken":
			return NPCStats.new(
				1000.0, # HP (high for testing!)
				0.0,    # Mana (chickens don't use mana)
				50.0,   # Energy
				100.0,  # Hunger
				0.0,    # Attack (passive - can't attack)
				2.0,    # Defense (very low)
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		"mushroom":
			return NPCStats.new(
				120.0,  # HP (high - needs to survive against multiple enemies)
				0.0,    # Mana (mushrooms don't use mana)
				75.0,   # Energy
				100.0,  # Hunger
				8.0,    # Attack (melee damage)
				8.0,    # Defense (medium)
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		"goblin":
			return NPCStats.new(
				100.0,  # HP (medium - glass cannon)
				0.0,    # Mana (goblins don't use mana)
				80.0,   # Energy (high - very active)
				100.0,  # Hunger
				12.0,   # Attack (high melee damage - hits harder than mushrooms)
				5.0,    # Defense (low - fragile)
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		"eyebeast":
			return NPCStats.new(
				80.0,   # HP (low - flying glass cannon)
				0.0,    # Mana (eyebeasts don't use mana)
				90.0,   # Energy (very high - constantly flying)
				100.0,  # Hunger
				15.0,   # Attack (very high ranged damage - eye beam)
				3.0,    # Defense (very low - extremely fragile)
				NPCStats.Emotion.NEUTRAL,
				npc_type
			)
		_:
			# Default stats for unknown NPCs
			return NPCStats.new(100.0, 100.0, 100.0, 100.0, 10.0, 5.0, NPCStats.Emotion.NEUTRAL, npc_type)


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

	# Pre-allocate chickens (monsters)
	var num_chickens = 8
	for i in range(num_chickens):
		_preallocate_generic_npc("chicken", num_warriors + num_archers + i)

	# Pre-allocate mushrooms (aggressive monsters)
	var num_mushrooms = 6
	for i in range(num_mushrooms):
		_preallocate_generic_npc("mushroom", num_warriors + num_archers + num_chickens + i)

	# Pre-allocate goblins (aggressive monsters - fast glass cannons)
	var num_goblins = 6
	for i in range(num_goblins):
		_preallocate_generic_npc("goblin", num_warriors + num_archers + num_chickens + num_mushrooms + i)

	# Pre-allocate eyebeasts (aggressive flying monsters - ranged glass cannons)
	var num_eyebeasts = 6
	for i in range(num_eyebeasts):
		_preallocate_generic_npc("eyebeast", num_warriors + num_archers + num_chickens + num_mushrooms + num_goblins + i)

	# Fill remaining slots with empty entries
	var total_preallocated = num_warriors + num_archers + num_chickens + num_mushrooms + num_goblins + num_eyebeasts
	for i in range(total_preallocated, MAX_GENERIC_POOL_SIZE):
		generic_pool.append({
			"character": null,
			"is_active": false,
			"slot": i,
			"npc_type": ""
		})

	print("NPCManager: Generic pool initialized with %d warriors, %d archers, %d chickens, %d mushrooms, %d goblins, %d eyebeasts" % [num_warriors, num_archers, num_chickens, num_mushrooms, num_goblins, num_eyebeasts])


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
	# Validate NPC type exists in registry
	if not NPC_REGISTRY.has(npc_type):
		push_error("NPCManager: Cannot spawn unknown NPC type '%s'. Valid types: %s" % [npc_type, str(NPC_REGISTRY.keys())])
		return null

	# Check pool health BEFORE attempting to get NPC (warns if >80% utilized)
	check_pool_health(npc_type)

	# Find inactive NPC in generic pool
	var slot_index = -1
	for i in range(generic_pool.size()):
		var slot = generic_pool[i]
		if not slot["is_active"] and (slot["npc_type"] == npc_type or slot["character"] == null):
			slot_index = i
			break

	if slot_index == -1:
		# Pool exhausted - check if we can expand
		var stats = get_pool_stats(npc_type)

		# Check if we have room to expand
		if generic_pool.size() >= MAX_GENERIC_POOL_SIZE:
			push_error("NPCManager: Pool exhausted for '%s' and MAX_GENERIC_POOL_SIZE (%d) reached! Cannot expand further." % [npc_type, MAX_GENERIC_POOL_SIZE])
			print_pool_stats()
			return null

		# Dynamically expand the pool for this type
		push_warning("NPCManager: Pool exhausted for '%s' (%d/%d active). Auto-expanding pool by 1 slot..." % [
			npc_type,
			stats["active"],
			stats["total"]
		])

		# Add a new slot and allocate it
		var new_slot_index = generic_pool.size()
		_preallocate_generic_npc(npc_type, new_slot_index)
		slot_index = new_slot_index

		print("NPCManager: Pool expanded! '%s' now has %d total slots." % [npc_type, get_pool_stats(npc_type)["total"]])

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

	# Generate FRESH stats for this spawn with random name (configured per NPC type)
	var fresh_stats = _create_stats_for_type(npc_type)

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

	# Connect to death signal for release animation (if monster)
	if npc.has_signal("monster_died"):
		# Check if already connected to avoid duplicate connections
		if not npc.monster_died.is_connected(_on_npc_died):
			npc.monster_died.connect(_on_npc_died.bind(npc))


	return npc


## Handle NPC death - play release animation and return to pool
func _on_npc_died(npc: Node2D) -> void:
	if not is_instance_valid(npc):
		return


	# Play release effect at NPC's position
	# On midpoint (frame 5), return NPC to pool
	play_release_effect(npc.global_position, func():
		return_generic_npc(npc)
	)


## Return generic NPC to pool
func return_generic_npc(npc: Node2D) -> void:
	# Find NPC in generic pool
	for slot in generic_pool:
		if slot["character"] == npc:
			slot["is_active"] = false
			npc.visible = false
			npc.position = Vector2.ZERO

			# Reset stats to full (keeps level/attack/defense but resets HP/mana/energy/hunger)
			if "stats" in npc and npc.stats:
				npc.stats.reset_to_full()
				var ulid_key = ULID.to_hex(npc.stats.ulid)
				stats_database.erase(ulid_key)
				npc.stats = null

			# Reset NPC state flags
			if "current_state" in npc:
				npc.current_state = NPCState.IDLE

			# Clear AI state
			if _npc_ai_states.has(npc):
				_npc_ai_states.erase(npc)

			print("NPCManager: Returned generic NPC to pool")
			return

	push_warning("NPCManager: NPC not found in generic pool")


## Get all available monster types from the generic pool
func get_available_monster_types() -> Array:
	var monster_types = []
	var seen_types = {}

	for slot in generic_pool:
		var npc_type = slot.get("npc_type", "")
		if npc_type.is_empty():
			continue

		# Check if this is a monster type (has "monster" category in registry)
		if NPC_REGISTRY.has(npc_type):
			var registry_entry = NPC_REGISTRY[npc_type]
			if registry_entry.get("category", "") == "monster":
				# Only add each type once
				if not seen_types.has(npc_type):
					monster_types.append(npc_type)
					seen_types[npc_type] = true

	return monster_types


## Get pool statistics for a specific NPC type
func get_pool_stats(npc_type: String) -> Dictionary:
	var total = 0
	var active = 0
	var inactive = 0

	for slot in generic_pool:
		if slot["npc_type"] == npc_type:
			total += 1
			if slot["is_active"]:
				active += 1
			else:
				inactive += 1

	return {
		"type": npc_type,
		"total": total,
		"active": active,
		"inactive": inactive,
		"utilization": (float(active) / float(total) * 100.0) if total > 0 else 0.0
	}


## Check if pool is near exhaustion (>80% utilized) and warn
func check_pool_health(npc_type: String) -> bool:
	var stats = get_pool_stats(npc_type)
	var is_healthy = stats["utilization"] < 80.0

	if not is_healthy:
		push_warning("NPCManager: Pool for '%s' is %d%% utilized (%d/%d active). Consider increasing pool size!" % [
			npc_type,
			int(stats["utilization"]),
			stats["active"],
			stats["total"]
		])

	return is_healthy


## Print all pool statistics (for debugging)
func print_pool_stats() -> void:
	print("=== NPCManager Pool Statistics ===")

	# Count by type
	var type_counts = {}
	for slot in generic_pool:
		var npc_type = slot["npc_type"]
		if npc_type == "":
			continue

		if not type_counts.has(npc_type):
			type_counts[npc_type] = {"total": 0, "active": 0}

		type_counts[npc_type]["total"] += 1
		if slot["is_active"]:
			type_counts[npc_type]["active"] += 1

	# Print stats for each type
	for npc_type in type_counts.keys():
		var stats = type_counts[npc_type]
		var utilization = float(stats["active"]) / float(stats["total"]) * 100.0
		print("  %s: %d/%d active (%.1f%% utilized)" % [
			npc_type,
			stats["active"],
			stats["total"],
			utilization
		])

	print("==================================")


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

	# Create UI sprites for all registered NPCs (data-driven)
	for npc_type in NPC_REGISTRY:
		# Skip cat since it's already cached as singleton
		if npc_type == "cat":
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

	# Check against registry using script's class_name
	# First try to get the script's global class name (from class_name declaration)
	var script = npc.get_script()
	if script:
		var script_class_name = script.get_global_name()
		if script_class_name != "":
			for npc_type in NPC_REGISTRY:
				var registry_class = NPC_REGISTRY[npc_type]["class_name"]
				if script_class_name == registry_class:
					return npc_type

	# Fallback: Check using class name string matching
	# This works because class_name declarations are available at runtime
	var npc_class_name = npc.get_class()
	for npc_type in NPC_REGISTRY:
		var registry_class = NPC_REGISTRY[npc_type]["class_name"]
		if npc_class_name == registry_class:
			return npc_type

	push_warning("NPCManager: Unknown NPC type for %s (class: %s)" % [npc, npc_class_name])
	return ""
