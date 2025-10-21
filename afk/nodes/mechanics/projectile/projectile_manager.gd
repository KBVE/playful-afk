extends Node

## ProjectileManager - Object Pool for Projectiles
## Manages arrow pooling and other projectiles to optimize performance
## Pre-allocates projectiles to avoid runtime instantiation overhead

## ===== PROJECTILE REGISTRY =====
## Central registry for all projectile types
const PROJECTILE_REGISTRY: Dictionary = {
	"arrow": {
		"scene": "res://nodes/mechanics/projectile/arrow/arrow.tscn",
		"class_name": "Arrow",
		"pool_size": 16,  # Number of arrows to keep in pool
		"category": "ranged"
	}
}

## ===== PROJECTILE POOL SYSTEM =====

# Projectile pools - Key: projectile type (e.g., "arrow"), Value: Array of projectile instances
var _projectile_pools: Dictionary = {}

# Active projectiles - currently in flight
var _active_projectiles: Dictionary = {}  # Key: projectile type, Value: Array of active instances

# Parent node for projectiles (set externally)
var projectile_container: Node2D = null


## ===== INITIALIZATION =====

func _ready() -> void:
	# Initialize pools for all registered projectiles
	_initialize_all_pools()
	print("ProjectileManager: Initialized with %d projectile types" % PROJECTILE_REGISTRY.size())


## Initialize all projectile pools based on registry
func _initialize_all_pools() -> void:
	for projectile_type in PROJECTILE_REGISTRY.keys():
		_initialize_pool(projectile_type)


## Initialize a specific projectile pool
func _initialize_pool(projectile_type: String) -> void:
	if not PROJECTILE_REGISTRY.has(projectile_type):
		push_error("ProjectileManager: Unknown projectile type: %s" % projectile_type)
		return

	var registry_entry = PROJECTILE_REGISTRY[projectile_type]
	var pool_size = registry_entry.get("pool_size", 8)
	var scene_path = registry_entry.get("scene", "")

	# Load the projectile scene
	var projectile_scene = load(scene_path)
	if not projectile_scene:
		push_error("ProjectileManager: Failed to load scene for %s: %s" % [projectile_type, scene_path])
		return

	# Create pool arrays
	_projectile_pools[projectile_type] = []
	_active_projectiles[projectile_type] = []

	# Pre-allocate projectiles
	for i in range(pool_size):
		var projectile = projectile_scene.instantiate()
		projectile.visible = false
		projectile.process_mode = Node.PROCESS_MODE_DISABLED

		# Add to scene tree if container is set
		if projectile_container:
			projectile_container.add_child(projectile)
		else:
			add_child(projectile)

		_projectile_pools[projectile_type].append(projectile)

	print("ProjectileManager: Initialized pool for '%s' with %d instances" % [projectile_type, pool_size])


## ===== PROJECTILE CONTAINER SETUP =====

## Set the container node for projectiles (e.g., Layer4Objects for parallax scrolling)
func set_projectile_container(container: Node2D) -> void:
	projectile_container = container
	print("ProjectileManager: Projectile container set to %s" % container.name)

	# Re-parent existing projectiles if any
	_reparent_all_projectiles()


## Re-parent all pooled projectiles to the new container
func _reparent_all_projectiles() -> void:
	if not projectile_container:
		return

	for projectile_type in _projectile_pools.keys():
		var pool = _projectile_pools[projectile_type]
		for projectile in pool:
			if projectile.get_parent() != projectile_container:
				projectile.reparent(projectile_container)


## ===== POOL MANAGEMENT =====

## Get a projectile from the pool
func get_projectile(projectile_type: String) -> Node2D:
	if not _projectile_pools.has(projectile_type):
		push_error("ProjectileManager: No pool exists for projectile type: %s" % projectile_type)
		return null

	var pool = _projectile_pools[projectile_type]

	# Find an available projectile
	if pool.size() > 0:
		var projectile = pool.pop_back()
		_active_projectiles[projectile_type].append(projectile)
		return projectile
	else:
		push_warning("ProjectileManager: Pool for '%s' is empty, creating new instance" % projectile_type)
		# Pool exhausted - create a new one (fallback)
		return _create_new_projectile(projectile_type)


## Return a projectile to the pool
func return_projectile(projectile: Node2D, projectile_type: String) -> void:
	if not _projectile_pools.has(projectile_type):
		push_error("ProjectileManager: Cannot return projectile - unknown type: %s" % projectile_type)
		return

	# Remove from active list
	var active_list = _active_projectiles[projectile_type]
	var index = active_list.find(projectile)
	if index != -1:
		active_list.remove_at(index)

	# Reset projectile state
	projectile.visible = false
	projectile.process_mode = Node.PROCESS_MODE_DISABLED
	projectile.position = Vector2.ZERO
	projectile.rotation = 0.0

	# Return to pool
	_projectile_pools[projectile_type].append(projectile)


## Create a new projectile instance (fallback when pool is exhausted)
func _create_new_projectile(projectile_type: String) -> Node2D:
	var registry_entry = PROJECTILE_REGISTRY[projectile_type]
	var scene_path = registry_entry.get("scene", "")
	var projectile_scene = load(scene_path)

	if not projectile_scene:
		push_error("ProjectileManager: Failed to load scene for %s" % projectile_type)
		return null

	var projectile = projectile_scene.instantiate()

	if projectile_container:
		projectile_container.add_child(projectile)
	else:
		add_child(projectile)

	_active_projectiles[projectile_type].append(projectile)
	return projectile


## ===== PROJECTILE FIRING =====

## Fire an arrow from a position towards a target
func fire_arrow(from_position: Vector2, target_position: Vector2, speed: float = 300.0) -> Node2D:
	var arrow = get_projectile("arrow")
	if not arrow:
		return null

	# Set arrow position and rotation
	arrow.position = from_position
	arrow.rotation = from_position.angle_to_point(target_position)

	# Enable and fire the arrow
	arrow.visible = true
	arrow.process_mode = Node.PROCESS_MODE_INHERIT

	# Call arrow's fire method if it exists
	if arrow.has_method("fire"):
		arrow.fire(target_position, speed)

	return arrow


## ===== UTILITY =====

## Get pool stats for debugging
func get_pool_stats(projectile_type: String) -> Dictionary:
	if not _projectile_pools.has(projectile_type):
		return {}

	return {
		"pool_available": _projectile_pools[projectile_type].size(),
		"active": _active_projectiles[projectile_type].size(),
		"total": _projectile_pools[projectile_type].size() + _active_projectiles[projectile_type].size()
	}


## Get all pool stats
func get_all_pool_stats() -> Dictionary:
	var stats = {}
	for projectile_type in _projectile_pools.keys():
		stats[projectile_type] = get_pool_stats(projectile_type)
	return stats


## Debug print all pool stats
func print_pool_stats() -> void:
	print("=== ProjectileManager Pool Stats ===")
	var all_stats = get_all_pool_stats()
	for projectile_type in all_stats.keys():
		var stats = all_stats[projectile_type]
		print("  %s: Available=%d, Active=%d, Total=%d" % [
			projectile_type,
			stats["pool_available"],
			stats["active"],
			stats["total"]
		])
