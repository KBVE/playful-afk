extends Node

## GameplayCache - Centralized performance cache for gameplay systems
## Autoload singleton that caches frequently-accessed game state
## Used by NPCManager, CombatManager, and other gameplay systems

signal viewport_resized(new_size: Vector2)

## ===== VIEWPORT CACHING =====
## Cache viewport rect to avoid repeated tree traversals

var _viewport_rect: Rect2 = Rect2()
var _viewport_rect_dirty: bool = true


func _ready() -> void:
	# Connect to viewport size changes
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Initialize cache
	_refresh_viewport_cache()

	print("GameplayCache: Initialized")


## Get cached viewport rect (auto-refreshes if dirty)
func get_viewport_rect() -> Rect2:
	if _viewport_rect_dirty:
		_refresh_viewport_cache()
	return _viewport_rect


## Get cached viewport center X position
func get_viewport_center_x() -> float:
	if _viewport_rect_dirty:
		_refresh_viewport_cache()
	return _viewport_rect.size.x / 2.0


## Get cached viewport center Y position
func get_viewport_center_y() -> float:
	if _viewport_rect_dirty:
		_refresh_viewport_cache()
	return _viewport_rect.size.y / 2.0


## Get cached viewport center point
func get_viewport_center() -> Vector2:
	if _viewport_rect_dirty:
		_refresh_viewport_cache()
	return _viewport_rect.size / 2.0


## Get cached viewport size
func get_viewport_size() -> Vector2:
	if _viewport_rect_dirty:
		_refresh_viewport_cache()
	return _viewport_rect.size


## Refresh viewport cache (called automatically when dirty)
func _refresh_viewport_cache() -> void:
	# Guard 1: Check tree and root exist
	if not get_tree() or not get_tree().root:
		_viewport_rect = Rect2(0, 0, 1152, 648)  # Default fallback
		_viewport_rect_dirty = false
		return

	var root = get_tree().root

	# Method 1: Try Window.size (Godot 4.x - works!)
	if "size" in root:
		_viewport_rect = Rect2(Vector2.ZERO, root.size)
	
	# Method 2: Fallback to get_viewport_rect() if it exists
	elif root.has_method("get_viewport_rect"):
		_viewport_rect = root.get_viewport_rect()
	
	# Method 3: Final fallback to default size
	else:
		_viewport_rect = Rect2(0, 0, 1152, 648)

	_viewport_rect_dirty = false

## Called when viewport is resized
func _on_viewport_size_changed() -> void:
	_viewport_rect_dirty = true
	_refresh_viewport_cache()
	viewport_resized.emit(_viewport_rect.size)
	print("GameplayCache: Viewport resized to %s" % _viewport_rect.size)


## Force cache refresh (use if viewport changes outside of size_changed signal)
func invalidate_viewport_cache() -> void:
	_viewport_rect_dirty = true
