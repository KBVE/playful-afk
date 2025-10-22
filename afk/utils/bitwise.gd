extends Node
class_name Bitwise

## Bitwise Utility Functions
## Provides type-safe helpers for bitwise state operations
## Used throughout the codebase for NPCState and other bitwise flag systems

## ---- Bitwise safety helpers ----

## Convert any value to int safely (handles String, null, etc.)
static func _as_int(v) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_STRING:
		return int(v.to_int())
	return int(v) if v != null else 0


## Get state flags from a Dictionary with type coercion
static func _get_state_flags(dict: Dictionary, key: String, default_val: int = 0) -> int:
	return _as_int(dict.get(key, default_val))


## Set state flags in a Dictionary, ensuring int type
static func _set_state_flags(dict: Dictionary, key: String, flags: int) -> void:
	dict[key] = int(flags)


## Read a property from an object and coerce to int (for current_state style fields)
## This safely handles Node2D -> NPC/Monster property access without type warnings
static func _ensure_int_prop(obj: Object, prop: String) -> int:
	var v = obj.get(prop) if obj and obj.has_method("get") else 0
	return _as_int(v)


## Set an int property on an object safely
static func _set_int_prop(obj: Object, prop: String, val: int) -> void:
	if obj and obj.has_method("set"):
		obj.set(prop, int(val))


## ---- Common bitwise operations ----

## Check if a flag is set in the state
static func has_flag(state: int, flag: int) -> bool:
	return (state & flag) != 0


## Add a flag to the state (bitwise OR)
static func add_flag(state: int, flag: int) -> int:
	return state | flag


## Remove a flag from the state (bitwise AND NOT)
static func remove_flag(state: int, flag: int) -> int:
	return state & ~flag


## Toggle a flag in the state (bitwise XOR)
static func toggle_flag(state: int, flag: int) -> int:
	return state ^ flag


## Extract specific bits using a mask
static func extract_bits(state: int, mask: int) -> int:
	return state & mask


## Check if any of the flags in the mask are set
static func has_any_flag(state: int, mask: int) -> bool:
	return (state & mask) != 0


## Check if all of the flags in the mask are set
static func has_all_flags(state: int, mask: int) -> bool:
	return (state & mask) == mask
