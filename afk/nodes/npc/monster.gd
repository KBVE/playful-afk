extends CharacterBody2D
class_name Monster

## Monster - Base class for all enemy NPCs
## Provides common functionality for monsters like taking damage, state management, and animations

## Emitted when the monster's state changes
signal state_changed(old_state: int, new_state: int)

## Emitted when the monster takes damage
signal damage_taken(amount: float, current_hp: float, max_hp: float)

## Emitted when the monster dies
signal monster_died

## Monster's current state (uses NPCManager.NPCState enum)
var current_state: int = NPCManager.NPCState.IDLE:
	set(value):
		if current_state != value:
			var old_state = current_state
			current_state = value
			_update_animation()
			# Emit state change signal for NPCManager
			state_changed.emit(old_state, current_state)

## Movement speed when walking
@export var walk_speed: float = 30.0

## NPC Stats reference (assigned by NPCManager)
var stats: NPCStats = null

## Monster's faction (MONSTER - can be attacked by allies)
var faction: int = 1  # NPCManager.Faction.MONSTER

## Monster's combat type (override in subclasses)
var combat_type: int = 0  # NPCManager.CombatType.NONE

## Monster types (override in subclasses to define behavior)
var monster_types: Array[NPCManager.MonsterType] = []

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer

# Controller reference (if needed by subclass)
var controller = null

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_hurt: bool = false

# Cached background reference for bounds checking (performance optimization)
var _background_ref: Control = null

# State-to-animation mapping (override in subclasses if needed)
var state_to_animation: Dictionary = {
	NPCManager.NPCState.IDLE: "idle",
	NPCManager.NPCState.WALKING: "walking",
	NPCManager.NPCState.ATTACKING: "attacking",
	NPCManager.NPCState.DAMAGED: "hurt",
	NPCManager.NPCState.DEAD: "dead"
}


func _ready() -> void:
	# Cache background reference for performance
	_background_ref = get_tree().get_first_node_in_group("background")

	# Set up state timer for automatic state changes
	if state_timer:
		state_timer.timeout.connect(_on_state_timer_timeout)
		state_timer.start()

	# Register with InputManager for click detection
	await get_tree().process_frame
	if InputManager:
		_register_with_input_manager()

	# Initialize animation
	_update_animation()

	# Call subclass-specific ready
	_on_ready_complete()


## Override this in subclasses for additional ready logic
func _on_ready_complete() -> void:
	pass


## Override this in subclasses for custom InputManager registration
func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 40.0)  # Default 40 pixel click radius


func _process(delta: float) -> void:
	# Update movement
	_update_movement(delta)


func _update_movement(delta: float) -> void:
	# Simple movement for monsters
	if current_state == NPCManager.NPCState.WALKING:
		# Calculate potential new position
		var new_position = position + (_move_direction * walk_speed * delta)

		# Check if new position is within walkable bounds
		if _background_ref and _background_ref.has_method("is_position_in_walkable_area"):
			if _background_ref.is_position_in_walkable_area(new_position):
				position = new_position
			else:
				# Hit bounds - pick a new random direction towards center
				var viewport_size = get_viewport_rect().size
				var center = Vector2(viewport_size.x / 2, position.y)
				var to_center = (center - position).normalized()
				# Add randomness to avoid straight line
				_move_direction = (to_center + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))).normalized()
		else:
			# Fallback: simple screen bounds check if background not available
			var viewport_size = get_viewport_rect().size
			if new_position.x < 50 or new_position.x > viewport_size.x - 50:
				_move_direction.x *= -1  # Bounce off horizontal bounds
			if new_position.y < 200 or new_position.y > viewport_size.y - 100:
				_move_direction.y *= -1  # Bounce off vertical bounds
			position = new_position


func _update_animation() -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	# Get animation name from state mapping
	var animation_name = state_to_animation.get(current_state, "idle")

	# Play animation if it exists
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _on_state_timer_timeout() -> void:
	# Randomly change state for AFK behavior (only if not hurt)
	if not _is_hurt:
		_random_state_change()


## Override this in subclasses for custom state changes
func _random_state_change() -> void:
	# 70% chance to idle, 30% chance to walk (using modulo for fun!)
	var should_walk = (randi() % 10) >= 7  # 3 out of 10 numbers (7,8,9) = 30%
	current_state = NPCManager.NPCState.WALKING if should_walk else NPCManager.NPCState.IDLE

	# Set random direction if walking
	if should_walk:
		_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	else:
		_move_direction = Vector2.ZERO

	# Randomize next state change time
	state_timer.wait_time = randf_range(2.0, 5.0)


## Take damage
func take_damage(amount: float) -> void:
	# Reduce HP through stats system if available
	if stats:
		stats.hp -= amount
		print("%s took %d damage! HP: %d/%d" % [get_class(), amount, stats.hp, stats.max_hp])

		# Emit damage signal for NPCManager
		damage_taken.emit(amount, stats.hp, stats.max_hp)

		# Check if monster died
		if stats.hp <= 0:
			current_state = NPCManager.NPCState.DEAD
			monster_died.emit()
			print("%s has died!" % get_class())
			return

	# Show hurt animation
	_is_hurt = true
	current_state = NPCManager.NPCState.DAMAGED

	# Call subclass-specific hurt behavior
	_on_take_damage(amount)

	# Return to idle after hurt animation
	await get_tree().create_timer(0.5).timeout
	_is_hurt = false
	current_state = NPCManager.NPCState.IDLE


## Override this in subclasses for custom damage behavior (e.g., fleeing)
func _on_take_damage(amount: float) -> void:
	pass


## Check if this monster is passive (doesn't deal damage to others)
func is_passive() -> bool:
	return NPCManager.MonsterType.PASSIVE in monster_types


## Check if this monster can attack
func can_attack() -> bool:
	return not is_passive()


## Called by InputManager when clicked (override in subclasses)
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("%s CLICKED!" % get_class().to_upper())
	print("Position: ", global_position)
	print("========================================")


## Called by InputManager when mouse enters
func _on_input_manager_hover_enter() -> void:
	# Highlight monster when hovered
	if animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)


## Called by InputManager when mouse exits
func _on_input_manager_hover_exit() -> void:
	# Remove highlight
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
