extends Control
class_name HealthBar

## Mini HealthBar - Reusable health display for NPCs and Monsters
## Shows a small rectangle that fills based on current/max HP
## Automatically connects to NPC/Monster damage_taken signals

## Visual configuration
@export var bar_width: float = 40.0
@export var bar_height: float = 6.0
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.8)  # Dark gray
@export var health_color: Color = Color(0.2, 0.8, 0.2, 1.0)  # Green
@export var low_health_color: Color = Color(0.8, 0.2, 0.2, 1.0)  # Red
@export var low_health_threshold: float = 0.3  # Below 30% shows red

## Offset from parent NPC (centered above sprite)
@export var y_offset: float = -40.0  # Above the NPC

## Health state
var current_hp: float = 100.0
var max_hp: float = 100.0
var health_percent: float = 1.0

## Reference to the NPC/Monster this healthbar is tracking
var tracked_entity: Node2D = null

## Node references
var background_rect: ColorRect = null
var health_rect: ColorRect = null


func _ready() -> void:
	# Create background rectangle
	background_rect = ColorRect.new()
	background_rect.color = background_color
	background_rect.size = Vector2(bar_width, bar_height)
	background_rect.position = Vector2(-bar_width / 2.0, 0)  # Center horizontally
	add_child(background_rect)

	# Create health fill rectangle
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
func _on_entity_damage_taken(_amount: float, current: float, maximum: float) -> void:
	current_hp = current
	max_hp = maximum
	_update_health_display()


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


## Cleanup when healthbar is freed
func _exit_tree() -> void:
	disconnect_from_entity()
