extends Node2D
class_name EnvironmentObject

## EnvironmentObject - Base class for all environment objects
## Objects can be static (permanent) or temporary (removed after lifetime)

## Unique identifier for this object instance (16-byte binary format)
var ulid: PackedByteArray = PackedByteArray()

## Whether this object is static (always on map) or temporary (removed after time)
var is_static: bool = false

## Lifetime in seconds (only used for non-static objects)
var lifetime_seconds: float = 60.0

## Sprite reference (override in subclasses or assign in scene)
var sprite: Sprite2D = null

## AnimatedSprite reference (for animated objects)
var animated_sprite: AnimatedSprite2D = null


func _ready() -> void:
	# Try to find sprite nodes automatically
	if not sprite:
		sprite = get_node_or_null("Sprite2D")
	if not animated_sprite:
		animated_sprite = get_node_or_null("AnimatedSprite2D")

	_on_ready_complete()


## Called after _ready completes (override in subclasses)
func _on_ready_complete() -> void:
	pass


## Called when object is spawned from pool
## Override in subclasses for custom spawn behavior
func on_spawn() -> void:
	pass


## Called when object is despawned and returned to pool
## Override in subclasses for cleanup
func on_despawn() -> void:
	pass


## Get spawn time from ULID (Unix timestamp)
func get_spawn_time() -> float:
	if ulid.size() == 0:
		return 0.0
	return ULID.get_timestamp(ulid)


## Get age of object in seconds
func get_age() -> float:
	var spawn_time = get_spawn_time()
	if spawn_time == 0.0:
		return 0.0
	return Time.get_unix_time_from_system() - spawn_time


## Check if object has expired
func is_expired() -> bool:
	if is_static:
		return false
	return get_age() >= lifetime_seconds


## Set object to static mode (won't be removed)
func set_static(value: bool) -> void:
	is_static = value


## Set object lifetime
func set_lifetime(seconds: float) -> void:
	lifetime_seconds = seconds
