extends Node

## NPCDataWarehouse Singleton
##
## High-performance NPC pool and state management using Rust GDExtension.
## This is a GDScript autoload wrapper around the Rust GodotNPCDataWarehouse.
##
## Replaces Dictionary-based pools with HolyMap for:
## - Lock-free reads (combat/AI queries)
## - Fast concurrent writes (spawn/despawn)
## - WASM-safe threading support
##
## Usage:
## ```gdscript
## # Register a pool
## NPCDataWarehouse.register_pool("warrior", 10, "res://nodes/npc/warrior/warrior.tscn")
##
## # Store NPC data
## NPCDataWarehouse.store_npc(ulid, npc_json_data)
##
## # Get NPC data
## var npc_data = NPCDataWarehouse.get_npc(ulid)
##
## # Check pool health
## var read_count = NPCDataWarehouse.read_store_count()
## var write_count = NPCDataWarehouse.write_store_count()
## ```

# The actual Rust warehouse instance
var _warehouse: GodotNPCDataWarehouse = null

func _ready() -> void:
	print("NPCDataWarehouse Singleton: Initializing Rust backend...")
	_warehouse = GodotNPCDataWarehouse.new()
	add_child(_warehouse)

	# Initialize NPC pools immediately (before combat tick can run)
	# This prevents race conditions where combat tries to spawn before pools exist
	print("[NPCDataWarehouse] Pre-initializing NPC pools...")

	# Allies
	_warehouse.initialize_npc_pool("warrior", 10, "res://nodes/npc/warrior/warrior.tscn")
	_warehouse.initialize_npc_pool("archer", 10, "res://nodes/npc/archer/archer.tscn")

	# Monsters
	_warehouse.initialize_npc_pool("goblin", 10, "res://nodes/npc/goblin/goblin.tscn")
	_warehouse.initialize_npc_pool("mushroom", 10, "res://nodes/npc/mushroom/mushroom.tscn")
	_warehouse.initialize_npc_pool("skeleton", 10, "res://nodes/npc/skeleton/skeleton.tscn")
	_warehouse.initialize_npc_pool("eyebeast", 10, "res://nodes/npc/eyebeast/eyebeast.tscn")

	# Passive
	_warehouse.initialize_npc_pool("chicken", 5, "res://nodes/npc/chicken/chicken.tscn")

	print("[NPCDataWarehouse] NPC pools pre-initialized successfully!")
	print("NPCDataWarehouse Singleton: Ready!")


## Register a new NPC pool
func register_pool(npc_type: String, max_size: int, scene_path: String) -> void:
	if _warehouse:
		_warehouse.register_pool(npc_type, max_size, scene_path)
	else:
		push_error("NPCDataWarehouse: Warehouse not initialized!")


# ===== Rust NPC Pool System Methods =====

## Initialize an NPC pool (pre-create NPCs)
## Call this on game start for each NPC type
func initialize_npc_pool(npc_type: String, pool_size: int, scene_path: String) -> void:
	if _warehouse:
		_warehouse.initialize_npc_pool(npc_type, pool_size, scene_path)
	else:
		push_error("NPCDataWarehouse: Warehouse not initialized!")


## Set the scene container where NPCs will be added as children
func set_scene_container(container: Node2D) -> void:
	if _warehouse:
		_warehouse.set_scene_container(container)
	else:
		push_error("NPCDataWarehouse: Warehouse not initialized!")


## Spawn an NPC from the Rust pool
## Returns the ULID bytes of the spawned NPC, or empty PackedByteArray if failed
func rust_spawn_npc(npc_type: String, position: Vector2) -> PackedByteArray:
	if _warehouse:
		return _warehouse.rust_spawn_npc(npc_type, position)
	return PackedByteArray()


## Despawn an NPC and return it to the pool
func rust_despawn_npc(ulid: PackedByteArray) -> bool:
	if _warehouse:
		return _warehouse.rust_despawn_npc(ulid)
	return false


## Store active NPC data
func store_npc(ulid: String, npc_data: String) -> void:
	if _warehouse:
		_warehouse.store_npc(ulid, npc_data)


## Get active NPC data
func get_npc(ulid: String) -> String:
	if _warehouse:
		return _warehouse.get_npc(ulid)
	return ""


## Remove NPC from active pool
func remove_npc(ulid: String) -> bool:
	if _warehouse:
		return _warehouse.remove_npc(ulid)
	return false


## Store NPC state flags (raw integer, not JSON)
## Much faster than storing in AI state JSON
func store_npc_state(ulid: String, state: int) -> void:
	if _warehouse:
		_warehouse.store_npc_state(ulid, state)


## Get NPC state flags (raw integer)
func get_npc_state(ulid: String) -> int:
	if _warehouse:
		return _warehouse.get_npc_state(ulid)
	return 1  # Default to IDLE


## Store AI state
func store_ai_state(ulid: String, ai_data: String) -> void:
	if _warehouse:
		_warehouse.store_ai_state(ulid, ai_data)


## Get AI state
func get_ai_state(ulid: String) -> String:
	if _warehouse:
		return _warehouse.get_ai_state(ulid)
	return ""


## Store combat state
func store_combat_state(ulid: String, combat_data: String) -> void:
	if _warehouse:
		_warehouse.store_combat_state(ulid, combat_data)


## Get combat state
func get_combat_state(ulid: String) -> String:
	if _warehouse:
		return _warehouse.get_combat_state(ulid)
	return ""


## Check if NPC exists
func has_npc(ulid: String) -> bool:
	if _warehouse:
		return _warehouse.has_npc(ulid)
	return false


## Get total entries
func total_entries() -> int:
	if _warehouse:
		return _warehouse.total_entries()
	return 0


## Get read store count (Papaya - lock-free)
func read_store_count() -> int:
	if _warehouse:
		return _warehouse.read_store_count()
	return 0


## Get write store count (DashMap - concurrent)
func write_store_count() -> int:
	if _warehouse:
		return _warehouse.write_store_count()
	return 0


## Manually trigger sync
func sync() -> void:
	if _warehouse:
		_warehouse.sync()


## Clear all data (use with caution!)
func clear_all() -> void:
	if _warehouse:
		_warehouse.clear_all()


# ===== NPCState Bitflag Helper Methods =====

## Get NPCState constant value by name
func get_state(state_name: String) -> int:
	if _warehouse:
		return _warehouse.get_state(state_name)
	return 0


## Check if a state has a specific flag set
func has_state_flag(state: int, flag_name: String) -> bool:
	if _warehouse:
		return _warehouse.has_state_flag(state, flag_name)
	return false


## Combine multiple states using bitwise OR
func combine_states(state1: int, state2: int) -> int:
	if _warehouse:
		return _warehouse.combine_states(state1, state2)
	return 0


## Remove a flag from a state using bitwise AND NOT
func remove_state_flag(state: int, flag_name: String) -> int:
	if _warehouse:
		return _warehouse.remove_state_flag(state, flag_name)
	return state


## Add a flag to a state using bitwise OR
func add_state_flag(state: int, flag_name: String) -> int:
	if _warehouse:
		return _warehouse.add_state_flag(state, flag_name)
	return state


## Get a human-readable string representation of a state
func state_to_string(state: int) -> String:
	if _warehouse:
		return _warehouse.state_to_string(state)
	return ""


# ===== ULID Generation (Binary Format for Performance) =====

## Generate a new ULID as raw bytes (16 bytes / 128 bits)
## Returns PackedByteArray for maximum performance - zero allocations!
## This is the FASTEST way to generate ULIDs - use this for new code!
func generate_ulid_bytes() -> PackedByteArray:
	if _warehouse:
		return _warehouse.generate_ulid_bytes()
	return PackedByteArray()


## Generate a new ULID as hex string (backwards compatibility)
## Note: String format is slower due to allocations. Use generate_ulid_bytes() for best performance.
func generate_ulid() -> String:
	if _warehouse:
		return _warehouse.generate_ulid()
	return ""


## Convert ULID bytes to hex string
func ulid_bytes_to_hex(bytes: PackedByteArray) -> String:
	if _warehouse:
		return _warehouse.ulid_bytes_to_hex(bytes)
	return ""


## Convert hex string to ULID bytes
func ulid_hex_to_bytes(hex: String) -> PackedByteArray:
	if _warehouse:
		return _warehouse.ulid_hex_to_bytes(hex)
	return PackedByteArray()


## Parse and validate a ULID string
## Returns true if valid, false otherwise
func validate_ulid(ulid: String) -> bool:
	if _warehouse:
		return _warehouse.validate_ulid(ulid)
	return false


# ============================================================================
# Combat & AI Logic Methods (Rust-powered)
# ============================================================================

## Calculate damage dealt by attacker to victim
func calculate_damage(attacker_attack: float, victim_defense: float) -> float:
	if _warehouse:
		return _warehouse.calculate_damage(attacker_attack, victim_defense)
	return 1.0

## Check if two NPCs are hostile to each other based on their states
func are_hostile(state1: int, state2: int) -> bool:
	if _warehouse:
		return _warehouse.are_hostile(state1, state2)
	return false

## Check if NPC can attack (just checks if attacker is in valid attacking state)
func can_attack(attacker_state: int) -> bool:
	if _warehouse:
		return _warehouse.can_attack(attacker_state)
	return false

## Get combat type (MELEE, RANGED, or MAGIC) from state
func get_combat_type(state: int) -> int:
	if _warehouse:
		return _warehouse.get_combat_type(state)
	return 0

## Enter combat state (removes IDLE; adds COMBAT)
func enter_combat_state(current_state: int) -> int:
	if _warehouse:
		return _warehouse.enter_combat_state(current_state)
	return current_state

## Exit combat state (removes COMBAT, ATTACKING; adds IDLE)
func exit_combat_state(current_state: int) -> int:
	if _warehouse:
		return _warehouse.exit_combat_state(current_state)
	return current_state

## Start attacking (adds ATTACKING, removes IDLE)
func start_attack(current_state: int) -> int:
	if _warehouse:
		return _warehouse.start_attack(current_state)
	return current_state

## Stop attacking (removes ATTACKING, adds IDLE)
func stop_attack(current_state: int) -> int:
	if _warehouse:
		return _warehouse.stop_attack(current_state)
	return current_state

## Start walking (adds WALKING, removes IDLE)
func start_walking(current_state: int) -> int:
	if _warehouse:
		return _warehouse.start_walking(current_state)
	return current_state

## Stop walking (removes WALKING, adds IDLE)
func stop_walking(current_state: int) -> int:
	if _warehouse:
		return _warehouse.stop_walking(current_state)
	return current_state

## Mark NPC as dead (adds DEAD, removes all other states)
func mark_dead(current_state: int) -> int:
	if _warehouse:
		return _warehouse.mark_dead(current_state)
	return current_state

## Check if NPC is in combat
func is_in_combat(state: int) -> bool:
	if _warehouse:
		return _warehouse.is_in_combat(state)
	return false

## ===== COMBAT SYSTEM =====

## Enable combat system
func start_combat_system() -> void:
	if _warehouse:
		_warehouse.start_combat_system()
	else:
		push_error("NPCDataWarehouse: Warehouse not initialized!")

## Disable combat system
func stop_combat_system() -> void:
	if _warehouse:
		_warehouse.stop_combat_system()

## Tick combat logic (call every frame from _process)
## Returns Array of JSON strings (CombatEvent)
func tick_combat(delta: float) -> Array:
	if _warehouse:
		return _warehouse.tick_combat(delta)
	return []

## Poll combat events from event queue
## Returns Array of JSON strings (CombatEvent)
func poll_combat_events() -> Array:
	if _warehouse:
		return _warehouse.poll_combat_events()
	return []

## Register NPC for combat system
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
func register_npc_for_combat(ulid_bytes: PackedByteArray, static_state: int, behavioral_state: int, max_hp: float, attack: float, defense: float) -> void:
	if _warehouse:
		_warehouse.register_npc_for_combat(ulid_bytes, static_state, behavioral_state, max_hp, attack, defense)

## Unregister NPC from combat system
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
func unregister_npc_from_combat(ulid_bytes: PackedByteArray) -> void:
	if _warehouse:
		_warehouse.unregister_npc_from_combat(ulid_bytes)

## Get NPC current HP
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
func get_npc_hp(ulid_bytes: PackedByteArray) -> float:
	if _warehouse:
		return _warehouse.get_npc_hp(ulid_bytes)
	return 0.0

## Update NPC position (call every frame from NPC _process)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
func update_npc_position(ulid_bytes: PackedByteArray, x: float, y: float) -> void:
	if _warehouse:
		_warehouse.update_npc_position(ulid_bytes, x, y)

## Get NPC position
func get_npc_position(ulid: String) -> PackedFloat32Array:
	if _warehouse:
		return _warehouse.get_npc_position(ulid)
	return PackedFloat32Array()

## Get NPC behavioral state (IDLE, WALKING, ATTACKING, DAMAGED, DEAD, etc.)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
## Returns: int - bitwise state flags
func get_npc_behavioral_state(ulid_bytes: PackedByteArray) -> int:
	if _warehouse:
		return _warehouse.get_npc_behavioral_state(ulid_bytes)
	return 0

## Clear ATTACKING state after attack animation finishes
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
## Called by NPC animation_finished handler
func clear_attacking_state(ulid_bytes: PackedByteArray) -> void:
	if _warehouse:
		_warehouse.clear_attacking_state(ulid_bytes)

## Clear DAMAGED state after hurt animation finishes
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
## Called by NPC animation_finished handler
func clear_damaged_state(ulid_bytes: PackedByteArray) -> void:
	if _warehouse:
		_warehouse.clear_damaged_state(ulid_bytes)

## Confirm spawn completed successfully (defensive programming)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
## monster_type: String - type of monster spawned
## static_state: int - expected static state flags
## behavioral_state: int - expected behavioral state flags
func confirm_spawn(ulid_bytes: PackedByteArray, monster_type: String, static_state: int, behavioral_state: int) -> void:
	if _warehouse:
		_warehouse.confirm_spawn(ulid_bytes, monster_type, static_state, behavioral_state)

## Get NPC waypoint (target position calculated by Rust AI)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
## Returns: PackedFloat32Array [x, y] world position, or empty array if no waypoint
func get_npc_waypoint(ulid_bytes: PackedByteArray) -> PackedFloat32Array:
	if _warehouse:
		return _warehouse.get_npc_waypoint(ulid_bytes)
	return PackedFloat32Array()

## Handle projectile hit - called when arrow/projectile collides with target
## attacker_ulid_bytes: PackedByteArray (16 bytes) - who fired the projectile
## target_ulid_bytes: PackedByteArray (16 bytes) - who got hit
## Returns: Array of JSON event strings (damage or death events)
func projectile_hit(attacker_ulid_bytes: PackedByteArray, target_ulid_bytes: PackedByteArray) -> Array:
	if _warehouse:
		return _warehouse.projectile_hit(attacker_ulid_bytes, target_ulid_bytes)
	return []

## Set world bounds for waypoint clamping (from BackgroundManager)
## Called when background loads to set safe zone boundaries
## min_x, max_x, min_y, max_y: floats defining the playable rectangle
func set_world_bounds(min_x: float, max_x: float, min_y: float, max_y: float) -> void:
	if _warehouse:
		_warehouse.set_world_bounds(min_x, max_x, min_y, max_y)

## Get NPC stats as a Dictionary (for UI display)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes
## Returns: Dictionary with keys: hp, max_hp, attack, defense, name, type, etc.
func get_npc_stats_dict(ulid_bytes: PackedByteArray) -> Dictionary:
	if _warehouse:
		# Get NPC data from Rust (returns JSON string)
		var npc_json = _warehouse.get_npc(ULID.to_hex(ulid_bytes))
		if npc_json and npc_json.length() > 0:
			var json = JSON.new()
			var error = json.parse(npc_json)
			if error == OK and json.data is Dictionary:
				return json.data
	return {}


## Get NPC name by ULID bytes
func get_npc_name(ulid_bytes: PackedByteArray) -> String:
	if _warehouse:
		return _warehouse.get_npc_name(ulid_bytes)
	return ""


## Get NPC type by ULID bytes
func get_npc_type(ulid_bytes: PackedByteArray) -> String:
	if _warehouse:
		return _warehouse.get_npc_type(ulid_bytes)
	return ""


## Get NPC data as JSON string (name, type, stats)
## ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes
## Returns: JSON string with format: {"name":"...","type":"...","hp":X,"max_hp":X,"attack":X,"defense":X}
func get_npc_data_json(ulid_bytes: PackedByteArray) -> String:
	if _warehouse:
		return _warehouse.get_npc_data_json(ulid_bytes)
	return "{}"
