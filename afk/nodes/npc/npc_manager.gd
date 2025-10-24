extends Node

## NPCManager - Global NPC Management System
## Provides centralized access to all NPCs in the game, especially the virtual pet
## Access via: NPCManager.cat anywhere in your code

## DEPRECATED: Preload NPCStats for backward compatibility
## Stats are now managed by Rust NPCDataWarehouse, but legacy code still uses NPCStats
const NPCStats = preload("res://nodes/npc/npc_stats.gd")

## ===== NPC STATE SYSTEM =====
## Unified bitwise flag system for ALL NPC states, types, and behaviors
## Consolidates behavioral states, combat types, and factions into one performant system

## NPC State enum - BEHAVIORAL states only (dynamic, changes during gameplay)
## Can combine states: e.g., WALKING | COMBAT
##
## These states change dynamically during gameplay based on NPC behavior.
## For static properties (combat type, faction), use NPCStaticState instead.
##
## Usage Examples:
##   Idle warrior:     IDLE
##   Walking monster:  WALKING
##   Attacking ally:   ATTACKING | COMBAT
enum NPCState {
	# Behavioral States (bits 0-5) - Change during gameplay (SIMPLIFIED)
	IDLE = 1 << 0,        # 1:  Idle (not moving, not attacking)
	WALKING = 1 << 1,     # 2:  Walking/moving
	ATTACKING = 1 << 2,   # 4:  Currently attacking (animation playing)
	COMBAT = 1 << 3,      # 8:  Engaged in combat
	DAMAGED = 1 << 4,     # 16: Taking damage - plays hurt/damage animation
	DEAD = 1 << 5         # 32: Dead - plays death animation
}

## Static/Immutable NPC properties (set once, never change)
## These should NEVER be modified during gameplay - only read
enum NPCStaticState {
	# Combat Types (0-3) - Each NPC has exactly ONE combat type (immutable)
	MELEE = 1 << 0,      # 1:   Melee attacker (warriors, knights, goblins)
	RANGED = 1 << 1,     # 2:   Ranged attacker (archers, crossbowmen)
	MAGIC = 1 << 2,      # 4:   Magic attacker (mages, wizards)
	HEALER = 1 << 3,     # 8:   Healer/support (clerics, druids)

	# Factions (4-6) - Determines who can attack whom (immutable)
	ALLY = 1 << 4,       # 16:  Player's allies - don't attack each other
	MONSTER = 1 << 5,    # 32:  Hostile creatures - attack allies
	PASSIVE = 1 << 6,    # 64:  Doesn't attack/do damage (chickens, critters)
}

# Virtual Pet Reference
var cat: Cat = null
var cat_scene: PackedScene = preload("res://nodes/npc/cat/cat.tscn")

## ===== STATE HISTORY SYSTEM =====
## Centralized state tracking for all NPCs
## Maps ULID -> Single state entry with 3-state history
## Entry: { "timestamp": int, "historic_state": int, "current_state": int, "new_state": int, "reason": String }
## This gives us: historic_state (last known), current_state (before this change), new_state (after this change)
## Only stores ONE entry per NPC - memory usage = O(active NPCs)
## Cleaned up when NPC returns to pool
var historic_state: Dictionary = {}

## Signal for requesting state changes from other systems
## Other systems should emit this instead of directly modifying NPC state
signal request_state_change(npc: Node2D, new_state: int, reason: String)

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
		"ai_profile": {
			"idle_weight": 30,      # Eyebeasts are very aggressive
			"walk_weight": 70,      # Constantly moving (flying)
			"state_change_min": 0.8,  # Very quick state changes (agile flyer)
			"state_change_max": 2.5,
			"movement_speed": 0.9   # Fastest monster (flying)
		}
	},
	"skeleton": {
		"scene": "res://nodes/npc/skeleton/skeleton.tscn",
		"class_name": "Skeleton",
		"category": "monster",
		"ai_profile": {
			"idle_weight": 35,      # Skeletons are aggressive
			"walk_weight": 65,      # Move around steadily
			"state_change_min": 1.2,  # Medium state changes
			"state_change_max": 3.5,
			"movement_speed": 0.75  # Medium speed
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
## Current allocation: 6 warriors + 6 archers + 8 chickens + 6 mushrooms + 6 goblins + 6 eyebeasts + 6 skeletons = 44 total
const MAX_GENERIC_POOL_SIZE: int = 50
var generic_pool: Array[Dictionary] = []  # Each entry: {character, is_active, npc_type, ...}

## MIGRATION COMPLETE: NPC stats are now stored in Rust NPCDataWarehouse
## Use get_stats_by_key(ulid_key) to fetch stats from Rust

## HEALTHBAR POOL - Pooled healthbars for NPCs
## Pre-allocated healthbars that are assigned to NPCs when spawned
const MAX_HEALTHBAR_POOL_SIZE: int = 50  # Match generic pool size
var healthbar_pool: Array[Dictionary] = []  # Each entry: {healthbar: HealthBar, is_active: bool, npc: Node2D}
var healthbar_scene: PackedScene = null

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

	# Connect to our own state change signal
	request_state_change.connect(_handle_state_change_request)

	# Connect to EventManager for bidirectional communication
	if EventManager:
		# Listen to state change requests from EventManager (debounced pathway)
		EventManager.npc_state_change_requested.connect(_handle_state_change_request)

	# Connect to CombatManager for bidirectional communication
	if CombatManager:
		# Listen to combat events from CombatManager
		CombatManager.combat_started.connect(_on_combat_started)
		CombatManager.combat_ended.connect(_on_combat_ended)
		CombatManager.damage_dealt.connect(_on_damage_dealt)
		CombatManager.target_killed.connect(_on_target_killed)

	# RUST COMBAT: Enable combat system
	NPCDataWarehouse.start_combat_system()

	# RUST COMBAT: Create fixed combat tick timer (16ms = 60 ticks per second)
	var combat_tick_timer = Timer.new()
	combat_tick_timer.name = "CombatTickTimer"
	combat_tick_timer.wait_time = 0.016  # 16ms = 60 ticks/second
	combat_tick_timer.autostart = true
	combat_tick_timer.timeout.connect(_on_combat_tick)
	add_child(combat_tick_timer)


## ===== COMBAT TICK =====

## Combat tick handler (called by timer at fixed 60Hz rate)
func _on_combat_tick() -> void:
	# RUST COMBAT: Tick combat logic and get events
	# Pass fixed delta of 0.016 (60 ticks per second)
	var events_json = NPCDataWarehouse.tick_combat(0.016)

	for event_json in events_json:
		var event = JSON.parse_string(event_json)
		if event:
			_handle_combat_event(event)
		else:
			push_error("[COMBAT ERROR] Failed to parse combat event JSON: %s" % event_json)


## Handle combat event from Rust (animations, damage numbers, VFX)
func _handle_combat_event(event: Dictionary) -> void:
	# DEFENSIVE: Validate event has required fields
	if not "event_type" in event:
		push_error("[COMBAT ERROR] Event missing event_type field")
		return

	# Special handling for spawn events - they don't have ULIDs yet
	if event.event_type == "spawn":
		if "attacker_ulid" in event and event.attacker_ulid != "":
			var npc_type = event.attacker_ulid
			# Check if it's an ally or monster to determine spawn position
			var is_ally = (npc_type == "warrior" or npc_type == "archer")
			var spawn_pos: Vector2
			var initial_target: Vector2

			if is_ally:
				# Allies spawn on left side
				spawn_pos = _calculate_ally_spawn_position()
				var viewport_size = get_viewport().get_visible_rect().size
				initial_target = Vector2(viewport_size.x / 2, spawn_pos.y)
			else:
				# Monsters spawn on right side
				spawn_pos = _calculate_spawn_position()
				var viewport_size = get_viewport().get_visible_rect().size
				initial_target = Vector2(viewport_size.x / 2, spawn_pos.y)

			# Spawn the NPC
			_spawn_monster(npc_type, spawn_pos, initial_target)
		return  # Spawn event handled, exit early

	# For non-spawn events, look up NPCs by ULID
	var attacker: Node2D = null
	var target: Node2D = null

	if "attacker_ulid" in event:
		attacker = _find_npc_by_ulid(event.attacker_ulid)
	if "target_ulid" in event:
		target = _find_npc_by_ulid(event.target_ulid)

	# DEFENSIVE: Check for missing NPCs (should not happen if Rust properly cleaned up)
	if "attacker_ulid" in event and not attacker:
		if not has_meta("_logged_missing_" + event.attacker_ulid):
			push_error("[COMBAT ERROR] Could not find attacker with ULID: %s" % event.attacker_ulid)
			set_meta("_logged_missing_" + event.attacker_ulid, true)
		return

	if "target_ulid" in event and not target:
		if not has_meta("_logged_missing_" + event.target_ulid):
			push_error("[COMBAT ERROR] Could not find target with ULID: %s" % event.target_ulid)
			set_meta("_logged_missing_" + event.target_ulid, true)
		return

	# DEFENSIVE: Validate attacker and target are different NPCs
	if attacker and target and attacker == target:
		push_error("[COMBAT ERROR] NPC is attacking itself! Attacker: %s" % event.attacker_ulid)
		return

	match event.event_type:
		"attack":
			# VISUAL ONLY: Sync state from Rust and emit signals
			if attacker and target:
				EventManager.combat_started.emit(attacker, target)
				# Sync attacker state from Rust (ATTACKING flag already set by Rust)
				if attacker.stats and attacker.stats.ulid:
					var attacker_state = NPCDataWarehouse.get_npc_behavioral_state(attacker.stats.ulid)
					if "current_state" in attacker and attacker.current_state != attacker_state:
						attacker.current_state = attacker_state
		"damage":
			# VISUAL ONLY: Sync state and HP from Rust, update healthbar
			if attacker and target and "amount" in event:
				EventManager.damage_dealt.emit(attacker, target, event.amount)
				# Sync target state from Rust (DAMAGED flag already set by Rust)
				if target.stats and target.stats.ulid:
					var target_state = NPCDataWarehouse.get_npc_behavioral_state(target.stats.ulid)
					if "current_state" in target and target.current_state != target_state:
						target.current_state = target_state
					# Update healthbar (read HP from Rust)
					var current_hp = NPCDataWarehouse.get_npc_hp(target.stats.ulid)
					target.stats.hp = current_hp  # Sync from Rust
					# Emit damage_taken signal for healthbar update
					if target.has_signal("damage_taken"):
						target.damage_taken.emit(event.amount, current_hp, target.stats.max_hp)
				# TODO: Show damage number floating text
		"death":
			# VISUAL ONLY: Sync state from Rust and despawn
			if attacker and target:
				EventManager.target_killed.emit(attacker, target)
				# Sync target state from Rust (DEAD flag already set by Rust)
				if target.stats and target.stats.ulid:
					var target_state = NPCDataWarehouse.get_npc_behavioral_state(target.stats.ulid)
					if "current_state" in target:
						target.current_state = target_state
				# Schedule despawn after death animation
				get_tree().create_timer(1.0).timeout.connect(func(): _despawn_dead_npc(target))
		"projectile":
			# PROJECTILE EVENT: Store projectile data on attacker for delayed firing
			# Arrow will be fired during attack animation (frame-based)
			# event.attacker_animation contains projectile type (e.g., "arrow")
			# event.target_x, event.target_y contain target position
			if attacker and target:
				# Store projectile data on attacker NPC to be fired during animation
				attacker.set_meta("pending_projectile", {
					"type": event.attacker_animation,  # "arrow"
					"target": target,
					"target_pos": Vector2(event.target_x, event.target_y),
					"speed": 300.0
				})
		_:
			push_error("[COMBAT] Unknown event type: %s" % event.event_type)


## Despawn a dead NPC and return to pool
func _despawn_dead_npc(npc: Node2D) -> void:
	if not npc or not is_instance_valid(npc):
		return

	# Play release effect (particle animation)
	# On midpoint (when particles converge), actually despawn the NPC
	var npc_position = npc.global_position
	play_release_effect(npc_position, func():
		_complete_npc_despawn(npc)
	)


## Complete NPC despawn after release effect finishes
func _complete_npc_despawn(npc: Node2D) -> void:
	if not npc or not is_instance_valid(npc):
		return

	# IMPORTANT: Return healthbar to pool FIRST (before resetting NPC)
	return_healthbar(npc)

	# Get NPC type to find the right pool
	var npc_type: String = ""
	var found_in_pool: bool = false

	# Search generic pool first (monsters are here)
	for slot in generic_pool:
		if slot.has("character") and slot["character"] == npc:
			if slot.has("npc_type"):
				npc_type = slot["npc_type"]

			# Deactivate and hide
			slot["is_active"] = false
			npc.visible = false
			npc.position = Vector2.ZERO
			npc.process_mode = Node.PROCESS_MODE_DISABLED

			# Clean up stats and ULID
			if "stats" in npc and npc.stats:
				var ulid_key = ULID.to_hex(npc.stats.ulid)
				# Unregister from Rust combat system (if not already done)
				NPCDataWarehouse.unregister_npc_from_combat(npc.stats.ulid)
				# Remove from Rust NPCDataWarehouse
				NPCDataWarehouse.remove_npc(ulid_key)
				# Clean up historic_state entry
				historic_state.erase(ulid_key)
				# Reset stats for future reuse
				npc.stats.reset_to_full()
				npc.stats = null

			# Reset states
			if "current_state" in npc:
				npc.current_state = NPCState.IDLE
			if "static_state" in npc:
				pass  # Keep static_state, it's immutable

			found_in_pool = true
			break

	# If not found in generic pool, search persistent pool (allies)
	if not found_in_pool:
		for slot in persistent_pool:
			if slot.has("character") and slot["character"] == npc:
				if slot.has("npc_type"):
					npc_type = slot["npc_type"]

				# Deactivate and hide
				slot["is_active"] = false
				npc.visible = false
				npc.position = Vector2.ZERO
				npc.process_mode = Node.PROCESS_MODE_DISABLED

				# Clean up stats and ULID
				if "stats" in npc and npc.stats:
					var ulid_key = ULID.to_hex(npc.stats.ulid)
					# Unregister from Rust combat system (if not already done)
					NPCDataWarehouse.unregister_npc_from_combat(npc.stats.ulid)
					# Remove from Rust NPCDataWarehouse
					NPCDataWarehouse.remove_npc(ulid_key)
					# Clean up historic_state entry
					historic_state.erase(ulid_key)
					# Reset stats for future reuse
					npc.stats.reset_to_full()
					npc.stats = null

				# Reset states
				if "current_state" in npc:
					npc.current_state = NPCState.IDLE
				if "static_state" in npc:
					pass  # Keep static_state, it's immutable

				break

	# Note: Monster respawning is handled by EventManager's spawn wave system
	# NPCManager just despawns dead monsters and returns them to the pool
	# EventManager will spawn new monsters based on wave timing and game state


## Find NPC by ULID hex string
func _find_npc_by_ulid(ulid_hex: String) -> Node2D:
	# Search through all active NPCs
	for npc in _npc_ai_states.keys():
		if npc and "stats" in npc and npc.stats and "ulid" in npc.stats:
			var npc_ulid_hex = ULID.to_hex(npc.stats.ulid)
			if npc_ulid_hex == ulid_hex:
				return npc
	return null


## Calculate spawn position at edge of screen
func _calculate_spawn_position() -> Vector2:
	if not BackgroundManager:
		return Vector2.ZERO

	# Spawn at right edge of safe zone (monsters enter from right)
	# Random Y within bounds
	var spawn_x = BackgroundManager.max_x - 50  # 50px from right edge
	var spawn_y = randf_range(BackgroundManager.min_y, BackgroundManager.max_y)

	return Vector2(spawn_x, spawn_y)


## Calculate spawn position for allies (warriors, archers)
func _calculate_ally_spawn_position() -> Vector2:
	if not BackgroundManager:
		return Vector2.ZERO

	# Spawn at left edge of safe zone (allies start from left)
	# Random Y within bounds
	var spawn_x = BackgroundManager.min_x + 50  # 50px from left edge
	var spawn_y = randf_range(BackgroundManager.min_y, BackgroundManager.max_y)

	return Vector2(spawn_x, spawn_y)


## Spawn a monster from the Rust pool (called by Rust spawn events)
func _spawn_monster(monster_type: String, spawn_pos: Vector2, initial_target: Vector2) -> void:
	# Use Rust pool system to spawn the NPC
	var ulid_bytes = NPCDataWarehouse.rust_spawn_npc(monster_type, spawn_pos)

	if ulid_bytes.size() == 0:
		push_warning("NPCManager: Failed to spawn %s from Rust pool (pool might be full or not initialized)" % monster_type)
		return

	print("[SPAWN] Successfully spawned %s from Rust pool, ULID size: %d" % [monster_type, ulid_bytes.size()])


## ===== STATE HISTORY SYSTEM FUNCTIONS =====

## Handle state change requests from other systems (CombatManager, AnimationManager, etc.)
## This is the ONLY way external systems should modify NPC state
## Maintains historic_state, previous_state, and current_state
func _handle_state_change_request(npc: Node2D, new_state: int, reason: String) -> void:
	_change_npc_state(npc, new_state, reason)


## Internal helper to change NPC state with reason tracking
## Called by both external signal handlers and internal NPCManager functions
## NOTE: History tracking happens in _on_npc_state_changed() via the state_changed signal
## This function just tags the reason for the NEXT state change
func _change_npc_state(npc: Node2D, new_state: int, reason: String) -> void:
	if not is_instance_valid(npc):
		return

	# Tag the reason for this state change (will be picked up by signal handler)
	# Store reason in NPC's AI state so _on_npc_state_changed can use it
	if _npc_ai_states.has(npc):
		_npc_ai_states[npc]["last_state_change_reason"] = reason

	# Apply the state change (triggers state_changed signal → _on_npc_state_changed)
	npc.current_state = new_state


## Get state entry for an NPC by reference
## Returns dictionary with 3-state tracking, or null if not found
## Entry: { "timestamp": int, "historic_state": int, "current_state": int, "new_state": int, "reason": String }
func get_npc_state_entry(npc: Node2D) -> Dictionary:
	if not npc or not npc.stats or not npc.stats.ulid:
		return {}

	var ulid_key = ULID.to_hex(npc.stats.ulid)
	return historic_state.get(ulid_key, {})


## Get state entry for an NPC by ULID hex string
## Returns dictionary with 3-state tracking, or null if not found
func get_state_entry_by_ulid(ulid_hex: String) -> Dictionary:
	return historic_state.get(ulid_hex, {})


## ===== COMBAT EVENT HANDLERS (from CombatManager) =====

func _on_combat_started(attacker: Node2D, target: Node2D) -> void:
	# Forward to EventManager for other systems to react
	if EventManager:
		EventManager.combat_started.emit(attacker, target)


func _on_combat_ended(attacker: Node2D, target: Node2D) -> void:
	# Forward to EventManager for other systems to react
	if EventManager:
		EventManager.combat_ended.emit(attacker, target)


func _on_damage_dealt(attacker: Node2D, target: Node2D, damage: float) -> void:
	# Forward to EventManager for other systems to react
	if EventManager:
		EventManager.damage_dealt.emit(attacker, target, damage)


func _on_target_killed(attacker: Node2D, target: Node2D) -> void:
	# Forward to EventManager for other systems to react
	if EventManager:
		EventManager.target_killed.emit(attacker, target)


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

	# Load healthbar scene
	healthbar_scene = load("res://nodes/ui/healthbar/healthbar.tscn") as PackedScene
	if not healthbar_scene:
		push_error("NPCManager: Failed to load healthbar scene")


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

		# Check NPC's combat type from bitwise state (unused in this context, keeping for consistency)
		# Combat type is determined by NPCState flags (MELEE, RANGED, etc.)

		# Send this ally to engage the enemy
		var movement_target = _get_movement_target(npc)
		if movement_target.has_method("move_to_position"):
			# Set the enemy as combat target
			ai_state["combat_target"] = enemy
			ai_state["time_until_next_change"] = 2.0

			# Move toward the enemy
			movement_target.move_to_position(enemy.global_position.x)
			_ai_tween_y_position(npc, enemy.global_position.y, ai_state)

			# Set NPC to walking state - preserve combat type and faction flags
			if "current_state" in npc:
				npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING


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

			# Set NPC to walking state - preserve combat type and faction flags
			if "current_state" in npc:
				npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING

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

	# Cat data loaded silently


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
		# NPC data saved silently


## Handle game load event
func _on_game_loaded(success: bool) -> void:
	if success:
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])
		# Warrior load removed - now handled by pool system
		# NPC data loaded silently


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

	# Initialize healthbar pool now that we have foreground_container
	_initialize_healthbar_pool()


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

	# AI system initialized silently


## Initialize Emoji Manager for chat bubbles
func _initialize_emoji_manager() -> void:
	emoji_manager = EmojiManager.new()
	add_child(emoji_manager)
	# Emoji Manager initialized silently


## Initialize Release Effect Pool for death animations
func _initialize_release_effect_pool() -> void:
	# Pre-allocate release effect pool
	for i in range(RELEASE_POOL_SIZE):
		var effect = release_effect_scene.instantiate()
		effect.visible = false
		effect.scale = Vector2(0.5, 0.5)  # Scale down to 80%
		effect.modulate.a = 0.5  # Set transparency to 50% so death animation shows through

		# Add to foreground container if available, otherwise add to NPCManager
		if foreground_container:
			foreground_container.add_child(effect)
		else:
			add_child(effect)

		release_effect_pool.append(effect)

	# Release Effect Pool initialized silently


## Get available release effect from pool (or create new if all busy)
func _get_release_effect() -> Node2D:
	# Find first inactive effect (check if valid first)
	for effect in release_effect_pool:
		if is_instance_valid(effect) and not effect.visible:
			return effect

	# Clean up any freed nodes from pool
	release_effect_pool = release_effect_pool.filter(func(effect): return is_instance_valid(effect))

	# All busy - create a new one and add to pool
	var new_effect = release_effect_scene.instantiate()
	new_effect.scale = Vector2(0.5, 0.5)  # Scale down to 80%
	new_effect.modulate.a = 0.5  # Set transparency to 50% so death animation shows through

	if foreground_container:
		foreground_container.add_child(new_effect)
	else:
		push_error("NPCManager: Cannot add release effect - foreground_container is null")
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
	# Read AI profile and category from NPC instance (decentralized)
	var ai_profile: Dictionary = {}
	var npc_category: String = ""

	if "AI_PROFILE" in npc:
		ai_profile = npc.AI_PROFILE
	else:
		# Fallback to registry if NPC doesn't have AI_PROFILE constant
		if NPC_REGISTRY.has(npc_type):
			ai_profile = NPC_REGISTRY[npc_type].get("ai_profile", {})

	if "NPC_CATEGORY" in npc:
		npc_category = npc.NPC_CATEGORY
	else:
		# Fallback to registry if NPC doesn't have NPC_CATEGORY constant
		if NPC_REGISTRY.has(npc_type):
			npc_category = NPC_REGISTRY[npc_type].get("category", "")

	# Determine behavioral state based on NPC category
	# All NPCs start in IDLE (SIMPLIFIED - no more WANDERING)
	# IMPORTANT: Only set BEHAVIORAL states here, preserve combat type and faction flags!
	var behavioral_state = NPCState.IDLE
	var initial_timer = randf_range(0.5, 1.5) if npc_category == "monster" else randf_range(
		ai_profile.get("state_change_min", 3.0),
		ai_profile.get("state_change_max", 8.0)
	)

	# Get NPC's full state - it should already be set in _ready() with combat type + faction
	# Warriors: IDLE | MELEE | ALLY
	# Archers: IDLE | RANGED | ALLY
	# Monsters: IDLE | MELEE/RANGED | MONSTER
	var npc_full_state: int
	if "current_state" in npc and npc.current_state != 0:
		# NPC has already set its state (warriors, archers, monsters)
		npc_full_state = npc.current_state
	else:
		# Fallback: NPC doesn't have state yet, use behavioral state
		# This should rarely happen since NPCs set state in _ready()
		npc_full_state = behavioral_state
		# Don't set it on the NPC - let the NPC's _ready() handle state initialization
		# Setting it here would strip combat type and faction flags

	# Create AI state for this NPC
	_npc_ai_states[npc] = {
		"npc_type": npc_type,
		"ai_profile": ai_profile,
		"current_state": npc_full_state,
		"time_until_next_change": initial_timer,
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


## Check if NPC is registered with AI system
func is_npc_registered(npc: Node2D) -> bool:
	return _npc_ai_states.has(npc)


## Called when NPC takes damage - sets combat target for counter-attack
func on_npc_damaged(victim: Node2D, attacker: Node2D) -> void:
	if not is_instance_valid(victim) or not is_instance_valid(attacker):
		return

	# Check if victim is passive (chickens, etc.) - they don't counter-attack
	if victim.has_method("is_passive") and victim.is_passive():
		return

	# Get victim's AI state
	if not _npc_ai_states.has(victim):
		return

	var ai_state = _npc_ai_states[victim]

	# Check if victim can actually attack (not passive)
	# Check bitwise state for PASSIVE flag
	if victim.current_state & NPCStaticState.PASSIVE:
		return  # Passive NPCs don't counter-attack

	# Set attacker as combat target for counter-attack
	# NPCManager's AI system will automatically call start_melee_attack() or start_ranged_attack()
	# based on the victim's combat type (MELEE, RANGED, etc.)
	ai_state["combat_target"] = attacker
	ai_state["time_until_next_change"] = 0.1  # Immediate response

	# For monsters, immediately set movement direction and combat state
	if victim.current_state & NPCStaticState.MONSTER:
		if "_move_direction" in victim:
			var direction = (attacker.global_position - victim.global_position).normalized()
			victim._move_direction = direction

		# Add COMBAT and WALKING flags (bitwise)
		victim.current_state = (victim.current_state & ~NPCState.IDLE) | NPCState.COMBAT | NPCState.WALKING
		ai_state["current_state"] = victim.current_state

	# Log counter-attack initiation
	var victim_type = ai_state.get("npc_type", "unknown")
	var attacker_type = get_npc_type(attacker)
	# Counter-attack initiated silently


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

	# COMBAT BEHAVIOR - Now handled by Rust combat system
	# Old GDScript combat logic removed - Rust handles target finding, movement, and attacks
	# Combat events from Rust are handled in _handle_combat_event()

	# OLD GDSCRIPT COMBAT (DISABLED - Rust now handles this)
	if false and CombatManager:
		# Don't do anything if currently attacking (animation playing)
		if CombatManager.has_state(npc, NPCManager.NPCState.ATTACKING):
			return

		# Find nearest enemy
		var target = CombatManager.find_nearest_target(npc, 300.0)

		if target:
			# Get NPC's combat type from bitwise state flags
			var has_combat_type = npc.current_state & (NPCStaticState.MELEE | NPCStaticState.RANGED | NPCStaticState.MAGIC | NPCStaticState.HEALER)

			# MELEE COMBAT (Warriors, Knights, etc.)
			if npc.current_state & NPCStaticState.MELEE:
				var movement_target = _get_movement_target(npc)
				var distance_to_target = npc.global_position.distance_to(target.global_position)
				var melee_range = npc.attack_range if "attack_range" in npc else 60.0

				# IMPORTANT: Flip sprite to face target BEFORE checking can_melee_attack
				# The facing check happens inside can_melee_attack, so we need to face first
				if "animated_sprite" in npc and npc.animated_sprite:
					var to_target = target.global_position - npc.global_position
					# Only flip if significant horizontal movement (prevents flickering during vertical movement)
					if abs(to_target.normalized().x) > 0.3:
						npc.animated_sprite.flip_h = to_target.x < 0

				if CombatManager.can_melee_attack(npc, target):
					# In range and facing - ATTACK!
					# Stop warrior movement before attacking (warrior must stand still to swing)
					if movement_target.has_method("stop_auto_movement"):
						movement_target.stop_auto_movement()

					# Stop monster movement (clear direction)
					if (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
						npc._move_direction = Vector2.ZERO

					# Set NPC to attacking state (triggers attack animation)
					# IMPORTANT: Preserve combat type and faction flags!
					if "current_state" in npc:
						# Remove IDLE/WALKING, add COMBAT and ATTACKING (bitwise)
						var new_state = (npc.current_state & ~NPCState.IDLE & ~NPCState.WALKING) | NPCState.COMBAT | NPCState.ATTACKING
						_change_npc_state(npc, new_state, "start_attack")
						ai_state["current_state"] = npc.current_state

					# Execute combat logic (damage calculation, state tracking)
					CombatManager.start_melee_attack(npc, target)
					ai_state["combat_target"] = target
					ai_state["time_until_next_change"] = 2.0
					return
				# Check if warrior is in combat range but on cooldown - STAY IN POSITION
				elif distance_to_target <= melee_range:
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

					if should_move:
						# NPCs with controllers (warriors, archers)
						if movement_target.has_method("move_to_position"):
							movement_target.move_to_position(target.global_position.x)
							_ai_tween_y_position(npc, target.global_position.y, ai_state)
							ai_state["combat_target"] = target
							ai_state["last_combat_target_pos"] = target.global_position
							ai_state["time_until_next_change"] = 2.0
						# Monsters without controllers - use direct movement
						elif (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
							var direction = (target.global_position - npc.global_position).normalized()
							npc._move_direction = direction

							# Add COMBAT and WALKING flags (bitwise)
							var new_state = (npc.current_state & ~NPCState.IDLE) | NPCState.COMBAT | NPCState.WALKING
							_change_npc_state(npc, new_state, "monster_move_to_combat")
							ai_state["current_state"] = npc.current_state

							ai_state["combat_target"] = target
							ai_state["last_combat_target_pos"] = target.global_position
							ai_state["time_until_next_change"] = 2.0
					return

			# RANGED COMBAT + KITING (Archers, Crossbowmen, etc.)
			elif npc.current_state & NPCStaticState.RANGED:
				var movement_target = _get_movement_target(npc)
				var distance_to_target = npc.global_position.distance_to(target.global_position)
				var ranged_range = npc.attack_range if "attack_range" in npc else 150.0
				var max_range = ranged_range * 2.0  # Double optimal = maximum shooting distance

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
					# IMPORTANT: Preserve combat type and faction flags!
					if "current_state" in npc:
						# Remove IDLE/WALKING, add ATTACKING, preserve combat type and faction
						var new_state = (npc.current_state & ~NPCState.IDLE & ~NPCState.WALKING) | NPCState.ATTACKING
						_change_npc_state(npc, new_state, "ranged_start_attack")

					# Execute combat logic (projectile firing, state tracking)
					CombatManager.start_ranged_attack(npc, target, "arrow")
					ai_state["time_until_next_change"] = 2.0
					return

				# Too far - move closer
				elif distance_to_target > max_range:
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
		else:
			# Clear combat target from AI state so monsters can resume roaming
			if ai_state.has("combat_target"):
				ai_state.erase("combat_target")

			# Clear CombatManager combat state
			if CombatManager.is_in_combat(npc):
				CombatManager.end_combat(npc)

			# Restore proper behavioral state after combat
			if "current_state" in npc:
				# Remove COMBAT/ATTACKING/WALKING, add IDLE
				var new_state = (npc.current_state & ~NPCState.COMBAT & ~NPCState.ATTACKING & ~NPCState.WALKING) | NPCState.IDLE
				_change_npc_state(npc, new_state, "end_combat")
				ai_state["current_state"] = npc.current_state

	# "CALL FOR HELP" SYSTEM - Move toward nearby faction allies in combat to assist
	# Works for both ALLY and MONSTER factions
	# Only NPCs that are idle (not already in combat) can respond
	if not ai_state.get("combat_target"):
		# Check if NPC is available to respond (idle state)
		var is_available = false
		if "current_state" in npc:
			# Check for IDLE flag (bitwise)
			is_available = (npc.current_state & NPCState.IDLE)

		# Skip passive NPCs (like chickens) - they don't fight
		var is_passive = npc.has_method("is_passive") and npc.call("is_passive")

		if is_available and not is_passive:
			# Get this NPC's faction bitwise flags
			var my_state = npc.current_state
			var my_faction_flags = my_state & (NPCStaticState.ALLY | NPCStaticState.MONSTER | NPCStaticState.PASSIVE)

			# Look for nearby faction allies that are in combat (within 400px radius)
			var help_radius = 400.0
			var nearest_combat_distance = INF
			var nearest_combat_location = Vector2.ZERO
			var nearest_ally_name = ""

			# Check all NPCs to find faction allies in combat
			for other_npc in _npc_ai_states.keys():
				if not is_instance_valid(other_npc) or other_npc == npc:
					continue

				# Check if same faction using bitwise comparison
				if not "current_state" in other_npc:
					continue

				var other_faction_flags = other_npc.current_state & (NPCStaticState.ALLY | NPCStaticState.MONSTER | NPCStaticState.PASSIVE)
				if other_faction_flags != my_faction_flags or my_faction_flags == 0:
					continue

				# Check if ally is in combat
				if CombatManager and CombatManager.is_in_combat(other_npc):
					var distance = npc.global_position.distance_to(other_npc.global_position)

					# Found nearby faction ally in combat - move to assist
					if distance < help_radius and distance < nearest_combat_distance:
						nearest_combat_distance = distance
						nearest_combat_location = other_npc.global_position
						nearest_ally_name = _npc_ai_states[other_npc].get("npc_type", "unknown")

			# If found ally in combat, move toward them to assist
			if nearest_combat_distance < INF:
				# For monsters with direct movement
				if (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
					var direction = (nearest_combat_location - npc.global_position).normalized()
					npc._move_direction = direction
					npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING
					ai_state["roam_target"] = nearest_combat_location
					ai_state["time_until_next_change"] = 2.0
					# Responding to call for help silently
					return  # Skip normal behavior this frame

				# For NPCs with controllers (warriors/archers)
				var movement_target = _get_movement_target(npc)
				if movement_target.has_method("move_to_position"):
					movement_target.move_to_position(nearest_combat_location.x)
					_ai_tween_y_position(npc, nearest_combat_location.y, ai_state)
					ai_state["roam_target"] = nearest_combat_location
					ai_state["time_until_next_change"] = 2.0
					# Responding to call for help silently
					return  # Skip normal behavior this frame

	# SPAWN STATE ROUTING - SIMPLIFIED (no longer using SPAWN flag)
	# Monsters now spawn directly in safe zone, no special routing needed

	# MONSTER ROAMING BEHAVIOR - All monsters roam with bounds checking (passive and aggressive)
	# Passive monsters (chickens) roam but don't attack, aggressive monsters (mushrooms) attack + roam
	if npc.current_state & NPCStaticState.MONSTER:
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
					# Preserve combat type and faction flags
					npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING
					ai_state["roam_target"] = safe_pos
					ai_state["time_until_next_change"] = 5.0

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
		# Clear IDLE, add WALKING
		npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING

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
				# Moving to waypoint then target
			else:
				# Direct movement (no waypoint needed)
				ai_state["has_waypoint"] = false
				movement_target.move_to_position(target_pos.x)
				_ai_tween_y_position(npc, target_pos.y, ai_state)
				# Walking directly to target

	# Monsters without controllers - use direct movement direction
	elif (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
		# Pick random target position within safe bounds
		var target_x = randf_range(movement_bounds_x.x, movement_bounds_x.y)
		var target_y = get_safe_y_for_x(target_x, npc.global_position.y)
		var target_pos = Vector2(target_x, target_y)

		# Clamp to safe bounds
		target_pos = clamp_to_safe_bounds(target_pos)

		# Set movement direction towards target
		var direction = (target_pos - npc.global_position).normalized()
		npc._move_direction = direction

		# Store target in AI state for when monster gets close
		ai_state["wander_target"] = target_pos

		# Monster wandering to random position


## AI: Start NPC idle
func _ai_start_idle(npc: Node2D, ai_state: Dictionary) -> void:
	# AI System sets the high-level behavioral state
	if "current_state" in npc:
		# Clear WALKING and set IDLE
		npc.current_state = (npc.current_state & ~NPCState.WALKING) | NPCState.IDLE

	# Stop movement (controller or direct)
	var has_controller = "controller" in npc and npc.controller
	var movement_target = npc.controller if has_controller else npc

	if movement_target.has_method("stop_auto_movement"):
		movement_target.stop_auto_movement()
		# print("NPCManager AI: %s idling" % ai_state["npc_type"])

	# Monsters without controllers - stop direct movement
	elif (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
		npc._move_direction = Vector2.ZERO
		# Clear wander target
		if ai_state.has("wander_target"):
			ai_state.erase("wander_target")


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

	# Movement completed - update NPC state to Idle, preserve combat type and faction
	if "current_state" in npc:
		npc.current_state = (npc.current_state & ~NPCState.WALKING) | NPCState.IDLE
	ai_state["current_state"] = npc.current_state

	# This enables reactive behavior (e.g., could immediately start combat if enemy nearby)


## Controller signals when movement is interrupted/stopped early
func _on_controller_movement_interrupted(npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: Received movement_interrupted from %s controller" % ai_state["npc_type"])

	# Movement was stopped - update NPC state to Idle, preserve combat type and faction
	if "current_state" in npc:
		npc.current_state = (npc.current_state & ~NPCState.WALKING) | NPCState.IDLE
	ai_state["current_state"] = npc.current_state

	# AI could react by choosing a different target - timer will handle next decision


## NPC signals when state changes (bidirectional communication)
func _on_npc_state_changed(old_state: int, new_state: int, npc: Node2D) -> void:
	if not _npc_ai_states.has(npc):
		return

	var ai_state = _npc_ai_states[npc]
	# print("NPCManager AI: %s state changed from %d to %d" % [ai_state["npc_type"], old_state, new_state])

	# Track the state change in AI system
	ai_state["current_state"] = new_state

	# Track state change in historic_state (3-state system)
	# This captures ALL state changes from any source (animation, combat, movement, etc.)
	if npc.stats and npc.stats.ulid:
		var ulid_key = ULID.to_hex(npc.stats.ulid)

		# Get the reason (if set by _change_npc_state), otherwise use generic
		var reason = ai_state.get("last_state_change_reason", "unknown")

		# Clear the reason after using it
		if ai_state.has("last_state_change_reason"):
			ai_state.erase("last_state_change_reason")

		# Get existing entry to preserve historic_state
		var existing_entry = historic_state.get(ulid_key, null)
		var previous_historic_state = 0

		if existing_entry:
			# If we have a previous entry, the old "new_state" becomes our "historic_state"
			previous_historic_state = existing_entry.get("new_state", 0)

		# VALIDATION: Ensure states are unique (detect bugs where same state is stored in multiple slots)
		# Only update if the new_state is actually different from old_state
		if old_state == new_state:
			push_error("NPCManager: State change bug detected for %s - old_state == new_state (%d). Ignoring duplicate state change." % [ai_state.get("npc_type", "unknown"), old_state])
			return

		# Also check if we're creating a situation where all 3 states are the same
		if previous_historic_state != 0 and previous_historic_state == old_state and old_state == new_state:
			push_error("NPCManager: State uniqueness violation for %s - all states are identical (%d). This indicates a state management bug!" % [ai_state.get("npc_type", "unknown"), old_state])
			return

		# Update/create the single state entry with 3-state tracking
		# historic_state: the state before current_state (last known state)
		# current_state: the state before this change (old_state parameter)
		# new_state: the state after this change (new_state parameter)
		historic_state[ulid_key] = {
			"timestamp": Time.get_ticks_msec(),
			"historic_state": previous_historic_state,
			"current_state": old_state,
			"new_state": new_state,
			"reason": reason
		}

		# Emit state change to EventManager for other systems to react
		if EventManager:
			EventManager.npc_state_changed.emit(npc, old_state, new_state, reason)

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
## Now reads from decentralized NPC class static methods
func _create_stats_for_type(npc_type: String) -> NPCStats:
	# Get the NPC class from registry
	if not NPC_REGISTRY.has(npc_type):
		push_error("NPCManager: Cannot create stats for unknown NPC type: %s" % npc_type)
		return NPCStats.new(100.0, 100.0, 100.0, 100.0, 10.0, 5.0, NPCStats.Emotion.NEUTRAL, npc_type)

	# Load the scene and get the script
	var scene_path = NPC_REGISTRY[npc_type]["scene"]
	var npc_scene = load(scene_path) as PackedScene
	if not npc_scene:
		push_error("NPCManager: Failed to load scene for NPC type: %s" % npc_type)
		return NPCStats.new(100.0, 100.0, 100.0, 100.0, 10.0, 5.0, NPCStats.Emotion.NEUTRAL, npc_type)

	# Get the script from the scene's root node
	var temp_instance = npc_scene.instantiate()
	var npc_script = temp_instance.get_script()
	temp_instance.free()

	# Call the static create_stats() method if it exists
	if npc_script and npc_script.has_method("create_stats"):
		return npc_script.create_stats()

	# Fallback to default stats
	push_error("NPCManager: NPC type '%s' missing create_stats() method" % npc_type)
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
	# Persistent pool initialized silently


## Initialize the generic pool with pre-allocated NPCs
func _initialize_generic_pool() -> void:
	generic_pool.clear()

	# DEPRECATED: Monsters are now managed by Rust pools
	# Only warriors/archers use GDScript pool during migration

	# Pre-allocate warriors (reduced to 1 for debugging)
	var num_warriors = 1
	for i in range(num_warriors):
		_preallocate_generic_npc("warrior", i)

	# Pre-allocate archers (reduced to 0 for debugging)
	var num_archers = 0
	for i in range(num_archers):
		_preallocate_generic_npc("archer", num_warriors + i)

	# NOTE: Monsters (chickens, mushrooms, goblins, eyebeasts, skeletons)
	# are now managed by Rust pools - DO NOT preallocate them here!

	# Fill remaining slots with empty entries
	var total_preallocated = num_warriors + num_archers
	for i in range(total_preallocated, MAX_GENERIC_POOL_SIZE):
		generic_pool.append({
			"character": null,
			"is_active": false,
			"slot": i,
			"npc_type": ""
		})

	print("[NPCManager] Generic pool initialized with %d warriors, %d archers (monsters use Rust pools)" % [num_warriors, num_archers])

	# NOTE: Healthbar pool will be initialized when set_layer4_container is called


## Initialize the healthbar pool with pre-allocated healthbars
func _initialize_healthbar_pool() -> void:
	if not healthbar_scene:
		push_warning("NPCManager: Healthbar scene not loaded, skipping healthbar pool initialization")
		return

	if not foreground_container:
		push_warning("NPCManager: Layer4 container not set, skipping healthbar pool initialization")
		return

	healthbar_pool.clear()

	# Pre-allocate healthbars
	for i in range(MAX_HEALTHBAR_POOL_SIZE):
		var healthbar = healthbar_scene.instantiate()
		foreground_container.add_child(healthbar)
		healthbar.visible = false  # Hide until assigned

		healthbar_pool.append({
			"healthbar": healthbar,
			"is_active": false,
			"npc": null
		})

	# Healthbar pool initialized silently


## Get an available healthbar from the pool and assign it to an NPC
func get_healthbar_for_npc(npc: Node2D) -> HealthBar:
	if not npc:
		return null

	# Find an inactive healthbar
	for slot in healthbar_pool:
		if not slot["is_active"]:
			var healthbar = slot["healthbar"]
			slot["is_active"] = true
			slot["npc"] = npc

			# Connect healthbar to NPC
			healthbar.connect_to_entity(npc)
			healthbar.visible = true

			return healthbar

	push_warning("NPCManager: No available healthbars in pool!")
	return null


## Return a healthbar to the pool when NPC is released
func return_healthbar(npc: Node2D) -> void:
	if not npc:
		return

	# Find the healthbar assigned to this NPC
	for slot in healthbar_pool:
		if slot["is_active"] and slot["npc"] == npc:
			var healthbar = slot["healthbar"]

			# Disconnect from NPC and hide
			healthbar.disconnect_from_entity()
			healthbar.visible = false

			# Mark as inactive
			slot["is_active"] = false
			slot["npc"] = null
			return


## Pre-allocate a generic NPC instance (but don't activate it yet)
func _preallocate_generic_npc(npc_type: String, slot_index: int) -> void:
	# NOTE: This function is DEPRECATED
	# Monsters now use the Rust-managed pool system (NPCDataWarehouse)
	# This function is only kept for warriors/archers during migration
	# DO NOT use this for monsters - they should come from Rust pools

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

	# MIGRATION: Store stats in Rust NPCDataWarehouse
	var ulid_key = ULID.to_hex(npc_stats.ulid)
	NPCDataWarehouse.store_npc(ulid_key, JSON.stringify(npc_stats.to_dict()))

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

		# Assign ULID to NPC (primary identifier for Rust data)
		if "ulid" in npc:
			npc.ulid = npc_stats.ulid

		# DEPRECATED: Assign stats for backward compatibility
		if "stats" in npc:
			npc.stats = npc_stats

		# Set z-index
		_update_character_z_index(npc)

		# Register AI if active
		if activate:
			register_npc_ai(npc, npc_type)


	# Added persistent NPC silently
	return npc


## Get a generic NPC from pool (creates fresh stats each time)
## Y bounds are now dynamically queried from background heightmap based on movement
func get_generic_npc(npc_type: String, position: Vector2, initial_target: Vector2 = Vector2.ZERO) -> Node2D:
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

		# Pool expanded silently

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

	# Store in Rust NPCDataWarehouse (use hex string as key)
	var ulid_key = ULID.to_hex(fresh_stats.ulid)
	NPCDataWarehouse.store_npc(ulid_key, JSON.stringify(fresh_stats.to_dict()))

	# Assign ULID to NPC (primary identifier for Rust data)
	if "ulid" in npc:
		npc.ulid = fresh_stats.ulid

	# DEPRECATED: Assign stats for backward compatibility
	if "stats" in npc:
		npc.stats = fresh_stats

	# Activate NPC
	slot["is_active"] = true
	npc.position = position
	npc.visible = true
	npc.process_mode = Node.PROCESS_MODE_INHERIT
	_update_character_z_index(npc)

	# Set static state (combat type + faction - immutable)
	var static_state: int = 0
	var behavioral_state: int = 0

	if npc_type == "warrior":
		static_state = NPCStaticState.MELEE | NPCStaticState.ALLY
		behavioral_state = NPCState.IDLE
	elif npc_type == "archer":
		static_state = NPCStaticState.RANGED | NPCStaticState.ALLY
		behavioral_state = NPCState.IDLE
	elif npc_type == "goblin":
		static_state = NPCStaticState.MELEE | NPCStaticState.MONSTER
		behavioral_state = NPCState.IDLE
	elif npc_type == "mushroom":
		static_state = NPCStaticState.MELEE | NPCStaticState.MONSTER
		behavioral_state = NPCState.IDLE
	elif npc_type == "skeleton":
		static_state = NPCStaticState.MELEE | NPCStaticState.MONSTER
		behavioral_state = NPCState.IDLE
	elif npc_type == "eyebeast":
		static_state = NPCStaticState.RANGED | NPCStaticState.MONSTER
		behavioral_state = NPCState.IDLE
	elif npc_type == "chicken":
		static_state = NPCStaticState.MELEE | NPCStaticState.PASSIVE
		behavioral_state = NPCState.IDLE

	# Store states on NPC node
	if "static_state" in npc:
		npc.static_state = static_state
	if "current_state" in npc:
		npc.current_state = behavioral_state

	# Stop state timer for monsters - movement controlled by combat system now
	if npc_type in ["goblin", "mushroom", "skeleton", "eyebeast"]:
		if "state_timer" in npc and npc.state_timer:
			npc.state_timer.stop()  # Disable random wandering

	# RUST COMBAT: Register NPC with combat system
	# Pass raw ULID bytes (PackedByteArray) instead of hex string for performance
	NPCDataWarehouse.register_npc_for_combat(
		fresh_stats.ulid,
		static_state,
		behavioral_state,
		fresh_stats.max_hp,
		fresh_stats.attack,
		fresh_stats.defense
	)

	# RUST COMBAT: Set initial position
	# Pass raw ULID bytes (PackedByteArray) instead of hex string for performance
	NPCDataWarehouse.update_npc_position(fresh_stats.ulid, position.x, position.y)

	# Register with AI system for autonomous behavior (Y queried from heightmap)
	register_npc_ai(npc, npc_type)

	# Set initial movement direction for monsters spawned with a target
	if initial_target != Vector2.ZERO and (npc.static_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
		var direction = (initial_target - position).normalized()
		npc._move_direction = direction

		# Set WALKING state, remove IDLE (bitwise)
		npc.current_state = (npc.current_state & ~NPCState.IDLE) | NPCState.WALKING

		# Update AI state to match
		var ai_state = get_npc_ai_state(npc)
		if ai_state:
			ai_state["current_state"] = npc.current_state
			ai_state["time_until_next_change"] = randf_range(5.0, 10.0)
		else:
			push_error("NPCManager: Could not get AI state for spawned monster")

	# Assign healthbar to NPC (from pool)
	get_healthbar_for_npc(npc)

	# RUST COMBAT: Death is now handled by combat events, not signals
	# Removed old death signal connections to prevent duplicate release animations

	return npc


## Return generic NPC to pool
func return_generic_npc(npc: Node2D) -> void:
	# Return healthbar to pool FIRST (before resetting NPC)
	return_healthbar(npc)

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
				# RUST COMBAT: Unregister from combat system
				# Pass raw ULID bytes (PackedByteArray) instead of hex string for performance
				NPCDataWarehouse.unregister_npc_from_combat(npc.stats.ulid)
				# MIGRATION: Remove from Rust NPCDataWarehouse
				NPCDataWarehouse.remove_npc(ulid_key)
				# Clean up historic_state entry for this NPC
				historic_state.erase(ulid_key)
				npc.stats = null

			# Reset monster movement direction BEFORE resetting state
			if (npc.current_state & NPCStaticState.MONSTER) and "_move_direction" in npc:
				npc._move_direction = Vector2.ZERO

			# Reset NPC state flags - preserve combat type and faction for re-use
			if "current_state" in npc:
				# Keep MELEE/RANGED/ALLY/MONSTER flags, only reset behavioral state to IDLE
				var preserved_flags = npc.current_state & (NPCStaticState.MELEE | NPCStaticState.RANGED | NPCStaticState.ALLY | NPCStaticState.MONSTER)
				npc.current_state = NPCState.IDLE | preserved_flags

			# Clear AI state
			if _npc_ai_states.has(npc):
				_npc_ai_states.erase(npc)

			# NPC returned to pool silently
			return

	push_error("NPCManager: NPC not found in generic pool - cannot return")


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
	return get_stats_by_key(ulid_key)


## Get NPC stats by hex string key (for internal use)
func get_stats_by_key(ulid_key: String) -> NPCStats:
	# MIGRATION: Fetch from Rust NPCDataWarehouse
	var json_str = NPCDataWarehouse.get_npc(ulid_key)
	if json_str == "":
		return null

	var json = JSON.new()
	var parse_result = json.parse(json_str)
	if parse_result != OK:
		push_error("Failed to parse NPC stats JSON for ULID: %s" % ulid_key)
		return null

	var stats = NPCStats.new()
	stats.from_dict(json.data)
	return stats


## Get persistent NPC stats by name
func get_persistent_npc_stats_by_name(npc_name: String) -> NPCStats:
	for slot in persistent_pool:
		if slot["npc_name"] == npc_name and slot.has("ulid"):
			var ulid_key = slot["ulid"]
			return get_stats_by_key(ulid_key)
	return null


## Save all NPC stats (only persistent NPCs need to be saved)
func save_all_stats() -> Dictionary:
	var saved_data = {}

	# MIGRATION: Only save persistent NPCs (generic NPCs are ephemeral)
	# Fetch stats from Rust NPCDataWarehouse
	for slot in persistent_pool:
		if slot.has("ulid"):
			var ulid_key = slot["ulid"]
			var stats = get_stats_by_key(ulid_key)

			if stats:
				saved_data[ulid_key] = {
					"stats": stats.to_dict(),
					"npc_name": slot["npc_name"],
					"npc_type": slot["npc_type"],
					"is_persistent": true
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

	# Create UI sprites for all registered NPCs (data-driven)
	for npc_type in NPC_REGISTRY:
		# Skip cat since it's already cached as singleton
		if npc_type == "cat":
			continue

		await _cache_npc_ui_sprite(npc_type)



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
