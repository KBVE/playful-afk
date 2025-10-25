extends Control
class_name HealthBar

## Mini HealthBar - Reusable health display for NPCs and Monsters
## Shows a small rectangle that fills based on current/max HP
## Automatically connects to NPC/Monster damage_taken signals
## Also spawns floating damage text when damage is taken

## Visual configuration
@export var bar_width: float = 40.0
@export var bar_height: float = 6.0
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.8)  # Dark gray
@export var health_color: Color = Color(0.2, 0.8, 0.2, 1.0)  # Green
@export var low_health_color: Color = Color(0.8, 0.2, 0.2, 1.0)  # Red
@export var low_health_threshold: float = 0.3  # Below 30% shows red

## Offset from parent NPC (centered above sprite)
@export var y_offset: float = -40.0  # Above the NPC

## Floating damage text scene
var floating_damage_text_scene: PackedScene = preload("res://nodes/ui/floating_damage_text.tscn")

## Floating damage text pool (static, shared across all healthbars)
static var damage_text_pool: Array = []
static var damage_text_pool_size: int = 10  # Pre-allocate 10 damage texts

## Floating healing text pool (static, shared across all healthbars)
static var healing_text_pool: Array = []
static var healing_text_pool_size: int = 10  # Pre-allocate 10 healing texts

## Health state
var current_hp: float = 100.0
var max_hp: float = 100.0
var health_percent: float = 1.0

## Reference to the NPC/Monster this healthbar is tracking
var tracked_entity: Node2D = null

## Node references
var border_rect: ColorRect = null
var background_rect: ColorRect = null
var health_rect: ColorRect = null

## Border styling (golden border like chat UI)
var border_color: Color = Color(0.8, 0.6, 0.2, 1.0)  # Golden color
var border_width: float = 1.0


func _ready() -> void:
	# Initialize damage text pool on first healthbar creation (static, shared)
	if damage_text_pool.is_empty():
		_initialize_damage_text_pool()

	# Initialize healing text pool on first healthbar creation (static, shared)
	if healing_text_pool.is_empty():
		_initialize_healing_text_pool()

	# Create golden border rectangle (outermost)
	border_rect = ColorRect.new()
	border_rect.color = border_color
	border_rect.size = Vector2(bar_width + border_width * 2, bar_height + border_width * 2)
	border_rect.position = Vector2(-bar_width / 2.0 - border_width, -border_width)
	add_child(border_rect)

	# Create background rectangle (inner, sits on top of border)
	background_rect = ColorRect.new()
	background_rect.color = background_color
	background_rect.size = Vector2(bar_width, bar_height)
	background_rect.position = Vector2(-bar_width / 2.0, 0)  # Center horizontally
	add_child(background_rect)

	# Create health fill rectangle (topmost)
	health_rect = ColorRect.new()
	health_rect.color = health_color
	health_rect.size = Vector2(bar_width, bar_height)
	health_rect.position = Vector2(-bar_width / 2.0, 0)  # Center horizontally
	add_child(health_rect)

	# Set position offset
	position = Vector2(0, y_offset)

	# Initially hide until we connect to an entity
	visible = false


func _process(_delta: float) -> void:
	# Keep healthbar positioned above the tracked entity
	if tracked_entity and is_instance_valid(tracked_entity):
		# Use local position since both healthbar and entity are in Layer4 (same parallax)
		# This prevents drift from parallax transform conflicts
		position = tracked_entity.position + Vector2(0, y_offset)
	else:
		# Entity was destroyed, hide healthbar
		visible = false


## Connect to an NPC or Monster to track their health
func connect_to_entity(entity: Node2D) -> void:
	if not entity:
		push_warning("HealthBar: Tried to connect to null entity")
		return

	tracked_entity = entity

	# Get initial health values
	if "stats" in entity and entity.stats:
		current_hp = entity.stats.hp
		max_hp = entity.stats.max_hp
		_update_health_display()

	# Connect to damage_taken signal (both NPC and Monster have this)
	if entity.has_signal("damage_taken"):
		if not entity.damage_taken.is_connected(_on_entity_damage_taken):
			entity.damage_taken.connect(_on_entity_damage_taken)

	# Show the healthbar
	visible = true


## Disconnect from current entity
func disconnect_from_entity() -> void:
	if tracked_entity and is_instance_valid(tracked_entity):
		if tracked_entity.has_signal("damage_taken"):
			if tracked_entity.damage_taken.is_connected(_on_entity_damage_taken):
				tracked_entity.damage_taken.disconnect(_on_entity_damage_taken)

	tracked_entity = null
	visible = false


## Update health values (can also be called manually)
func set_health(current: float, maximum: float) -> void:
	current_hp = clamp(current, 0.0, maximum)
	max_hp = maximum
	_update_health_display()


## Called when tracked entity takes damage
func _on_entity_damage_taken(amount: float, current: float, maximum: float) -> void:
	current_hp = current
	max_hp = maximum
	_update_health_display()

	# Spawn floating damage text above the entity
	_spawn_floating_damage_text(int(amount))


## Called when tracked entity is healed
func _on_entity_healed(amount: float, current: float, maximum: float) -> void:
	current_hp = current
	max_hp = maximum
	_update_health_display()

	# Spawn floating healing text (green) above the entity
	_spawn_floating_healing_text(int(amount))


## Update the visual health bar
func _update_health_display() -> void:
	if not health_rect or not background_rect:
		return

	# Calculate health percentage
	health_percent = current_hp / max_hp if max_hp > 0 else 0.0

	# Update health bar width
	health_rect.size.x = bar_width * health_percent

	# Change color based on health percentage
	if health_percent <= low_health_threshold:
		health_rect.color = low_health_color  # Red when low
	else:
		health_rect.color = health_color  # Green when healthy

	# Hide healthbar if at full health (optional - can be configured)
	# visible = health_percent < 1.0


## Initialize the static damage text pool (called once by first healthbar)
func _initialize_damage_text_pool() -> void:
	# Pre-allocate damage text instances
	for i in range(damage_text_pool_size):
		var damage_text = floating_damage_text_scene.instantiate()
		damage_text.visible = false
		damage_text_pool.append(damage_text)


## Initialize the static healing text pool (called once by first healthbar)
func _initialize_healing_text_pool() -> void:
	# Pre-allocate healing text instances (green color, + prefix)
	for i in range(healing_text_pool_size):
		var healing_text = floating_damage_text_scene.instantiate()
		healing_text.visible = false
		# Mark this as a healing text so it can use green color
		healing_text.set_meta("is_healing", true)
		healing_text_pool.append(healing_text)


## Get an available damage text from the pool
func _get_damage_text_from_pool() -> Node:
	# Find first inactive damage text
	for damage_text in damage_text_pool:
		if is_instance_valid(damage_text) and not damage_text.visible:
			return damage_text

	# All busy - create a new one and add to pool
	var new_damage_text = floating_damage_text_scene.instantiate()
	damage_text_pool.append(new_damage_text)
	return new_damage_text


## Spawn floating damage text above the tracked entity (using pool)
func _spawn_floating_damage_text(damage_amount: int) -> void:
	if not tracked_entity or not is_instance_valid(tracked_entity):
		return

	# Get damage text from pool
	var damage_text = _get_damage_text_from_pool()

	# Add to parent if not already in scene tree
	if not damage_text.is_inside_tree():
		var parent = get_parent()
		if parent:
			parent.add_child(damage_text)
		else:
			# Fallback: add to scene tree root
			get_tree().root.add_child(damage_text)

	# Position just above the healthbar using LOCAL position (same as healthbar positioning)
	# Both healthbar and damage text are in Layer4, so use local coords
	# Spawn text 10 pixels above the healthbar
	var text_position = tracked_entity.position + Vector2(0, y_offset - 10)

	# Setup and start the animation (this will make it visible)
	damage_text.setup(damage_amount, text_position)


## Get an available healing text from the pool
func _get_healing_text_from_pool() -> Node:
	# Find first inactive healing text
	for healing_text in healing_text_pool:
		if is_instance_valid(healing_text) and not healing_text.visible:
			return healing_text

	# All busy - create a new one and add to pool
	var new_healing_text = floating_damage_text_scene.instantiate()
	new_healing_text.set_meta("is_healing", true)
	healing_text_pool.append(new_healing_text)
	return new_healing_text


## Spawn floating healing text above the tracked entity (using pool)
func _spawn_floating_healing_text(heal_amount: int) -> void:
	if not tracked_entity or not is_instance_valid(tracked_entity):
		return

	# Get healing text from pool
	var healing_text = _get_healing_text_from_pool()

	# Add to parent if not already in scene tree
	if not healing_text.is_inside_tree():
		var parent = get_parent()
		if parent:
			parent.add_child(healing_text)
		else:
			# Fallback: add to scene tree root
			get_tree().root.add_child(healing_text)

	# Position just above the healthbar using LOCAL position (same as healthbar positioning)
	# Both healthbar and healing text are in Layer4, so use local coords
	# Spawn text 10 pixels above the healthbar
	var text_position = tracked_entity.position + Vector2(0, y_offset - 10)

	# Setup and start the animation with positive number (will show as +N in green)
	healing_text.setup(heal_amount, text_position)


## Cleanup when healthbar is freed
func _exit_tree() -> void:
	disconnect_from_entity()
