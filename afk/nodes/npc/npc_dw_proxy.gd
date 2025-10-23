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
	print("NPCDataWarehouse Singleton: Ready!")


## Register a new NPC pool
func register_pool(npc_type: String, max_size: int, scene_path: String) -> void:
	if _warehouse:
		_warehouse.register_pool(npc_type, max_size, scene_path)
	else:
		push_error("NPCDataWarehouse: Warehouse not initialized!")


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

## Enter combat state (removes IDLE, WANDERING; adds COMBAT)
func enter_combat_state(current_state: int) -> int:
	if _warehouse:
		return _warehouse.enter_combat_state(current_state)
	return current_state

## Exit combat state (removes COMBAT, ATTACKING; adds IDLE)
func exit_combat_state(current_state: int) -> int:
	if _warehouse:
		return _warehouse.exit_combat_state(current_state)
	return current_state

## Start attacking (adds ATTACKING, removes IDLE/WANDERING)
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
