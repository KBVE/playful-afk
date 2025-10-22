extends Node

## EnvironmentManager - Manages environment objects with object pooling
## Handles spawning, despawning, and lifecycle management of environment objects
## Uses two separate pools: static (permanent) and dynamic (ULID-based with expiration)

## Pool type flags (bitwise) for object behavior
enum PoolType {
	STATIC = 1 << 0,   # 1: Permanent objects that stay on map
	DYNAMIC = 1 << 1,  # 2: ULID-based temporary objects with expiration
	UNIQUE = 1 << 2,   # 4: Only one instance allowed on map at a time
	CASTABLE = 1 << 3  # 8: Object is "cast" once (spawns, triggers effect, then auto-returns to pool)
}
# Can combine flags:
# - DYNAMIC | UNIQUE = catflag (expires after time AND only 1 allowed)
# - DYNAMIC | UNIQUE | CASTABLE = catflag that triggers call_for_help once on spawn

## Static object pool - objects that stay on map permanently
var static_pool: Dictionary = {}  # Key: object_type, Value: Array of pooled objects

## Dynamic object pool - objects with ULID that expire after time
var dynamic_pool: Dictionary = {}  # Key: object_type, Value: Array of pooled objects

## Unique object pool - only one instance allowed per type
var unique_pool: Dictionary = {}  # Key: object_type, Value: Array of pooled objects

## Active static objects (no ULID needed, just reference)
var active_static_objects: Array[Node2D] = []

## Active dynamic objects (ULID-based tracking)
var active_dynamic_objects: Dictionary = {}  # Key: ulid_hex, Value: object reference

## Active unique objects (only one per type)
var active_unique_objects: Dictionary = {}  # Key: object_type, Value: Node2D

## Pool configuration
const DEFAULT_POOL_SIZE: int = 10

## Signal emitted when a catflag is spawned (for NPC AI to respond)
signal catflag_spawned(flag: Node2D, position: Vector2)

## Object registry - defines all environment object types
const OBJECT_REGISTRY: Dictionary = {
	"catflag": {
		"scene": "res://nodes/environment/catflag/catflag.tscn",
		"class_name": "CatFlag",
		"pool_type": PoolType.DYNAMIC | PoolType.UNIQUE | PoolType.CASTABLE,  # Cast once to call NPCs, expires after 60s, only 1 allowed
		"lifetime_seconds": 60.0,  # 1 minute lifetime
		"pool_size": 1,  # UNIQUE = only 1 can exist on map, so pool only needs 1 object
		"scale": Vector2(0.35, 0.35)  # Scale down to 35%
	}
}

## Container for spawned objects (set by main scene)
var environment_container: Node2D = null

## Cleanup timer for removing expired dynamic objects
var cleanup_timer: Timer = null
const CLEANUP_INTERVAL: float = 60.0  # Check for expired objects every 60 seconds (less stress)


func _ready() -> void:
	# Initialize object pools
	_initialize_pools()

	# Setup cleanup timer
	_setup_cleanup_timer()

	print("EnvironmentManager initialized")


## Initialize object pools for all registered types
func _initialize_pools() -> void:
	for object_type in OBJECT_REGISTRY:
		var config = OBJECT_REGISTRY[object_type]
		var pool_size = config.get("pool_size", DEFAULT_POOL_SIZE)
		var pool_type_flags = config.get("pool_type", PoolType.DYNAMIC)

		# Determine which pool to use based on flags
		var pool: Dictionary
		if pool_type_flags & PoolType.STATIC:
			pool = static_pool
		elif pool_type_flags & PoolType.UNIQUE:
			# UNIQUE objects go in unique pool (can also be DYNAMIC for expiration)
			pool = unique_pool
		else:
			pool = dynamic_pool

		pool[object_type] = []

		# Pre-create pool objects
		for i in range(pool_size):
			var obj = _create_object(object_type)
			if obj:
				pool[object_type].append(obj)

		# Build pool type description
		var pool_flags = []
		if pool_type_flags & PoolType.STATIC:
			pool_flags.append("static")
		if pool_type_flags & PoolType.DYNAMIC:
			pool_flags.append("dynamic")
		if pool_type_flags & PoolType.UNIQUE:
			pool_flags.append("unique")
		if pool_type_flags & PoolType.CASTABLE:
			pool_flags.append("castable")
		var pool_type_name = " + ".join(pool_flags) if pool_flags.size() > 0 else "unknown"

		print("EnvironmentManager: Initialized %s pool for '%s' with %d objects" % [pool_type_name, object_type, pool_size])


## Create a new environment object
func _create_object(object_type: String) -> Node2D:
	if not OBJECT_REGISTRY.has(object_type):
		push_error("EnvironmentManager: Unknown object type: %s" % object_type)
		return null

	var config = OBJECT_REGISTRY[object_type]
	var scene_path = config["scene"]
	var scene = load(scene_path)

	if not scene:
		push_error("EnvironmentManager: Failed to load scene: %s" % scene_path)
		return null

	var obj = scene.instantiate()

	# Add to container if available
	if environment_container:
		environment_container.add_child(obj)
	else:
		add_child(obj)

	# Apply custom scaling if specified in config
	if config.has("scale"):
		obj.scale = config["scale"]

	# Hide object initially (pooled state)
	obj.visible = false
	obj.process_mode = Node.PROCESS_MODE_DISABLED

	return obj


## Setup cleanup timer for removing expired objects
func _setup_cleanup_timer() -> void:
	cleanup_timer = Timer.new()
	cleanup_timer.wait_time = CLEANUP_INTERVAL
	cleanup_timer.one_shot = false
	cleanup_timer.timeout.connect(_on_cleanup_timer_timeout)
	add_child(cleanup_timer)
	cleanup_timer.start()


## Cleanup timer callback - remove expired dynamic objects only
func _on_cleanup_timer_timeout() -> void:
	# Get current time in milliseconds (ULID stores timestamps in ms)
	var current_time_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var expired_dynamic_objects: Array[String] = []
	var expired_unique_objects: Array[String] = []

	# Check dynamic objects (they have ULID with timestamp)
	for ulid_hex in active_dynamic_objects.keys():
		var obj = active_dynamic_objects[ulid_hex]

		if not is_instance_valid(obj):
			expired_dynamic_objects.append(ulid_hex)
			continue

		# Get object's spawn time from ULID (returns milliseconds)
		if "ulid" in obj and obj.ulid.size() > 0:
			var spawn_time_ms = ULID.decode_time(obj.ulid)
			var lifetime_seconds = 60.0
			if "lifetime_seconds" in obj:
				lifetime_seconds = obj.lifetime_seconds
			var lifetime_ms = lifetime_seconds * 1000.0

			# Check if expired (both values in milliseconds)
			if current_time_ms - spawn_time_ms >= lifetime_ms:
				expired_dynamic_objects.append(ulid_hex)

	# Check unique objects (they also have ULID with timestamp)
	for object_type in active_unique_objects.keys():
		var obj = active_unique_objects[object_type]

		if not is_instance_valid(obj):
			expired_unique_objects.append(object_type)
			continue

		# Get object's spawn time from ULID (returns milliseconds)
		if "ulid" in obj and obj.ulid.size() > 0:
			var spawn_time_ms = ULID.decode_time(obj.ulid)
			var lifetime_seconds = 60.0
			if "lifetime_seconds" in obj:
				lifetime_seconds = obj.lifetime_seconds
			var lifetime_ms = lifetime_seconds * 1000.0

			# Check if expired (both values in milliseconds)
			if current_time_ms - spawn_time_ms >= lifetime_ms:
				expired_unique_objects.append(object_type)

	# Remove expired dynamic objects
	for ulid_hex in expired_dynamic_objects:
		if active_dynamic_objects.has(ulid_hex):
			var obj = active_dynamic_objects[ulid_hex]
			if is_instance_valid(obj):
				despawn_object(obj)

	# Remove expired unique objects
	for object_type in expired_unique_objects:
		if active_unique_objects.has(object_type):
			var obj = active_unique_objects[object_type]
			if is_instance_valid(obj):
				despawn_object(obj)


## Spawn an environment object at a position
func spawn_object(object_type: String, position: Vector2, pool_type_override: int = -1) -> Node2D:
	# Validate object type exists
	if not OBJECT_REGISTRY.has(object_type):
		push_error("EnvironmentManager: Cannot spawn unknown object type '%s'. Valid types: %s" % [object_type, str(OBJECT_REGISTRY.keys())])
		return null

	# Get config to determine pool type flags
	var config = OBJECT_REGISTRY.get(object_type, {})
	var pool_type_flags = config.get("pool_type", PoolType.DYNAMIC)

	# Apply override if provided
	if pool_type_override >= 0:
		pool_type_flags = pool_type_override

	# Check if UNIQUE flag is set and object already exists
	if pool_type_flags & PoolType.UNIQUE:
		if active_unique_objects.has(object_type):
			var existing = active_unique_objects[object_type]
			if is_instance_valid(existing):
				# Already exists - return existing object instead of spawning new one
				return existing

	# Check pool health before spawning (warns if >80% utilized)
	check_pool_health(object_type)

	# Get object from appropriate pool
	var obj = _get_from_pool(object_type, pool_type_flags)

	if not obj:
		# Pool exhausted - provide detailed error
		var stats = get_pool_stats(object_type)
		push_error("EnvironmentManager: Pool exhausted for '%s'! All %d instances are active. Consider increasing pool size in OBJECT_REGISTRY." % [object_type, stats["total"]])
		print_pool_stats()  # Print full pool stats to help debug
		return null

	# Configure object based on pool type flags
	var is_static = (pool_type_flags & PoolType.STATIC)
	if "is_static" in obj:
		obj.is_static = is_static

	# Handle DYNAMIC flag (creates ULID for expiration)
	if pool_type_flags & PoolType.DYNAMIC:
		# Dynamic object - generate new ULID for this spawn (includes timestamp)
		var ulid = ULID.generate()
		var ulid_hex = ULID.to_hex(ulid)

		if "ulid" in obj:
			obj.ulid = ulid

		# Get lifetime from registry
		var lifetime = config.get("lifetime_seconds", 60.0)
		if "lifetime_seconds" in obj:
			obj.lifetime_seconds = lifetime

		# Store in active dynamic objects (unless also UNIQUE)
		if not (pool_type_flags & PoolType.UNIQUE):
			active_dynamic_objects[ulid_hex] = obj

	# Handle UNIQUE flag (only one allowed, tracked separately)
	if pool_type_flags & PoolType.UNIQUE:
		# For UNIQUE + DYNAMIC, we already created ULID above
		if not (pool_type_flags & PoolType.DYNAMIC):
			# UNIQUE but not DYNAMIC - still create ULID if needed for future use
			if "ulid" in obj and obj.ulid.size() == 0:
				obj.ulid = ULID.generate()

		# Store in active unique objects (only one per type)
		active_unique_objects[object_type] = obj

	# Handle STATIC flag (permanent, no ULID)
	if pool_type_flags & PoolType.STATIC:
		# Static object - just add to active list
		active_static_objects.append(obj)

	# Position and activate object
	obj.global_position = position
	obj.visible = true
	obj.process_mode = Node.PROCESS_MODE_INHERIT

	# Call object's spawn hook if it exists
	if obj.has_method("on_spawn"):
		obj.on_spawn()

	# Emit signal for catflag spawns
	if object_type == "catflag":
		print("EnvironmentManager: CatFlag spawned at position (%d, %d)" % [int(position.x), int(position.y)])
		catflag_spawned.emit(obj, position)

	return obj


## Despawn an object and return it to the pool
func despawn_object(obj: Node2D) -> void:
	if not is_instance_valid(obj):
		return

	# Get object type first to determine pool type from registry
	var object_type = _get_object_type(obj)
	if not object_type:
		push_error("EnvironmentManager: Cannot despawn object with unknown type")
		return

	var config = OBJECT_REGISTRY.get(object_type, {})
	var pool_type_flags = config.get("pool_type", PoolType.DYNAMIC)

	# Remove from appropriate active tracking based on flags
	if pool_type_flags & PoolType.STATIC:
		active_static_objects.erase(obj)

	if pool_type_flags & PoolType.UNIQUE:
		# Remove from unique objects
		active_unique_objects.erase(object_type)

	if pool_type_flags & PoolType.DYNAMIC:
		# Dynamic object - remove using ULID (if not also UNIQUE)
		if not (pool_type_flags & PoolType.UNIQUE):
			if "ulid" in obj and obj.ulid.size() > 0:
				var ulid_hex = ULID.to_hex(obj.ulid)
				active_dynamic_objects.erase(ulid_hex)

	# Call object's despawn hook if it exists
	if obj.has_method("on_despawn"):
		obj.on_despawn()

	# Return to pool
	_return_to_pool(obj, object_type, pool_type_flags)


## Get object from pool
func _get_from_pool(object_type: String, pool_type_flags: int) -> Node2D:
	# Select the appropriate pool based on flags
	var pool_dict: Dictionary
	if pool_type_flags & PoolType.STATIC:
		pool_dict = static_pool
	elif pool_type_flags & PoolType.UNIQUE:
		# UNIQUE objects use unique pool (regardless of DYNAMIC flag)
		pool_dict = unique_pool
	else:
		pool_dict = dynamic_pool

	if not pool_dict.has(object_type):
		return null

	var pool = pool_dict[object_type]

	# Find inactive object in pool
	for obj in pool:
		if is_instance_valid(obj) and not obj.visible:
			return obj

	# Pool exhausted - create new object (dynamic expansion)
	var stats_before = get_pool_stats(object_type)
	push_warning("EnvironmentManager: Pool exhausted for '%s' (%d/%d active). Auto-expanding pool by 1 slot..." % [
		object_type,
		stats_before["active"],
		stats_before["total"]
	])

	var new_obj = _create_object(object_type)
	if new_obj:
		pool.append(new_obj)
		print("EnvironmentManager: Pool expanded! '%s' now has %d total slots." % [object_type, pool.size()])
	else:
		push_error("EnvironmentManager: Failed to create new object for '%s' during pool expansion!" % object_type)

	return new_obj


## Return object to pool
func _return_to_pool(obj: Node2D, object_type: String, pool_type_flags: int) -> void:
	# Hide and disable object
	obj.visible = false
	obj.process_mode = Node.PROCESS_MODE_DISABLED
	obj.global_position = Vector2.ZERO

	# Clear ULID for dynamic objects (includes UNIQUE + DYNAMIC)
	if (pool_type_flags & PoolType.DYNAMIC) and "ulid" in obj:
		obj.ulid = PackedByteArray()


## Get object type from object instance
func _get_object_type(obj: Node2D) -> String:
	# Check script's class name
	var script = obj.get_script()
	if script:
		var script_class_name = script.get_global_name()
		for object_type in OBJECT_REGISTRY:
			if OBJECT_REGISTRY[object_type]["class_name"] == script_class_name:
				return object_type

	return ""


## Set the environment container (called from main scene)
func set_environment_container(container: Node2D) -> void:
	environment_container = container

	# Reparent existing pooled objects from all pools
	for object_type in static_pool:
		for obj in static_pool[object_type]:
			if is_instance_valid(obj) and obj.get_parent() != container:
				obj.reparent(container)

	for object_type in dynamic_pool:
		for obj in dynamic_pool[object_type]:
			if is_instance_valid(obj) and obj.get_parent() != container:
				obj.reparent(container)

	for object_type in unique_pool:
		for obj in unique_pool[object_type]:
			if is_instance_valid(obj) and obj.get_parent() != container:
				obj.reparent(container)


## Get all active objects of a specific type
func get_active_objects_by_type(object_type: String) -> Array[Node2D]:
	var result: Array[Node2D] = []

	# Check static objects
	for obj in active_static_objects:
		if is_instance_valid(obj) and _get_object_type(obj) == object_type:
			result.append(obj)

	# Check dynamic objects
	for obj in active_dynamic_objects.values():
		if is_instance_valid(obj) and _get_object_type(obj) == object_type:
			result.append(obj)

	return result


## Get object by ULID (only works for dynamic objects)
func get_object_by_ulid(ulid: PackedByteArray) -> Node2D:
	var ulid_hex = ULID.to_hex(ulid)
	return active_dynamic_objects.get(ulid_hex, null)


## Get pool statistics for monitoring
func get_pool_stats(object_type: String) -> Dictionary:
	if not OBJECT_REGISTRY.has(object_type):
		push_error("EnvironmentManager: Unknown object type '%s'" % object_type)
		return {}

	var config = OBJECT_REGISTRY[object_type]
	var pool_type_flags = config.get("pool_type", PoolType.DYNAMIC)

	# Get the appropriate pool based on flags
	var pool_dict: Dictionary
	if pool_type_flags & PoolType.STATIC:
		pool_dict = static_pool
	elif pool_type_flags & PoolType.UNIQUE:
		pool_dict = unique_pool
	else:
		pool_dict = dynamic_pool

	var total = 0
	var active_count = 0

	if pool_dict.has(object_type):
		var pool = pool_dict[object_type]
		total = pool.size()

		# Count active objects
		for obj in pool:
			if is_instance_valid(obj) and obj.visible:
				active_count += 1

	# Build pool type string from flags
	var pool_flags = []
	if pool_type_flags & PoolType.STATIC:
		pool_flags.append("static")
	if pool_type_flags & PoolType.DYNAMIC:
		pool_flags.append("dynamic")
	if pool_type_flags & PoolType.UNIQUE:
		pool_flags.append("unique")
	if pool_type_flags & PoolType.CASTABLE:
		pool_flags.append("castable")
	var pool_type_str = " + ".join(pool_flags) if pool_flags.size() > 0 else "unknown"

	return {
		"type": object_type,
		"pool_type": pool_type_str,
		"total": total,
		"active": active_count,
		"inactive": total - active_count,
		"utilization": (float(active_count) / float(total) * 100.0) if total > 0 else 0.0
	}


## Check pool health and warn if near exhaustion
func check_pool_health(object_type: String) -> bool:
	var stats = get_pool_stats(object_type)
	if stats.is_empty():
		return false

	var is_healthy = stats["utilization"] < 80.0

	if not is_healthy:
		push_warning("EnvironmentManager: Pool for '%s' is %d%% utilized (%d/%d active). Consider increasing pool size!" % [
			object_type,
			int(stats["utilization"]),
			stats["active"],
			stats["total"]
		])

	return is_healthy


## Print all pool statistics (for debugging)
func print_pool_stats() -> void:
	print("=== EnvironmentManager Pool Statistics ===")

	for object_type in OBJECT_REGISTRY.keys():
		var stats = get_pool_stats(object_type)
		print("  %s (%s): %d/%d active (%.1f%% utilized)" % [
			object_type,
			stats["pool_type"],
			stats["active"],
			stats["total"],
			stats["utilization"]
		])

	print("============================================")
