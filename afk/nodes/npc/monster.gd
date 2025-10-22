extends CharacterBody2D
class_name Monster

## Monster - Base class for all enemy NPCs
## Provides common functionality for monsters like taking damage, state management, and animations

## Emoji set for monsters
const EMOJIS: Array[String] = ["😈", "👹", "👻", "🐔", "🦖", "🐉", "🧟", "💀"]

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

## Combat range - distance at which this monster can attack
## For MELEE monsters: attack range (default ~50px, slightly less than warriors)
## For RANGED monsters: optimal firing distance (default ~150px)
@export var attack_range: float = 50.0

## NPC Stats reference (assigned by NPCManager)
var stats: NPCStats = null

## Deprecated properties - now using NPCState bitwise flags
## Faction, combat type, and monster types are now in current_state
## Example: MELEE | MONSTER | IDLE or PASSIVE | IDLE

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

	# Connect to animation finished signal for DAMAGED state cleanup
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

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
	# Check if WALKING flag is set (bitwise AND, not equality)
	if current_state & NPCManager.NPCState.WALKING:
		# Update movement direction to follow terrain slope for natural hill climbing
		if _background_ref and _background_ref.has_method("get_walkable_y_bounds"):
			# Sample terrain height at current position and slightly ahead
			var sample_distance = 20.0  # Look ahead 20px
			var current_x = global_position.x
			var ahead_x = current_x + (_move_direction.x * sample_distance)

			var current_y_bounds = _background_ref.get_walkable_y_bounds(current_x)
			var ahead_y_bounds = _background_ref.get_walkable_y_bounds(ahead_x)

			# Use midpoint of bounds as terrain surface height
			var current_terrain_y = (current_y_bounds.x + current_y_bounds.y) / 2.0
			var ahead_terrain_y = (ahead_y_bounds.x + ahead_y_bounds.y) / 2.0

			# Calculate terrain slope
			var terrain_slope = (ahead_terrain_y - current_terrain_y) / sample_distance

			# Adjust movement direction to match terrain slope (preserve horizontal speed)
			_move_direction.y = terrain_slope * _move_direction.x
			_move_direction = _move_direction.normalized()

		# Flip sprite based on movement direction (only if not in combat)
		# Combat code in NPCManager handles flipping to face target
		# Only flip if significant horizontal movement (threshold prevents flickering during vertical movement)
		if abs(_move_direction.x) > 0.3 and not (current_state & NPCManager.NPCState.ATTACKING):
			if animated_sprite:
				animated_sprite.flip_h = _move_direction.x < 0

		# Calculate potential new position (in local coordinates relative to Layer4Objects)
		var new_position = position + (_move_direction * walk_speed * delta)

		# Always move the monster - bounds checking should only affect direction, not movement
		position = new_position

		# Safety clamp: ensure Y stays within terrain bounds to prevent floating
		if _background_ref and _background_ref.has_method("get_walkable_y_bounds"):
			var y_bounds = _background_ref.get_walkable_y_bounds(global_position.x)
			position.y = clamp(position.y, y_bounds.x, y_bounds.y)


func _update_animation() -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	# Priority-based animation selection (highest priority first)
	var animation_name = "idle"

	# Priority 1: DEAD (highest)
	if current_state & NPCManager.NPCState.DEAD:
		animation_name = state_to_animation.get(NPCManager.NPCState.DEAD, "dead")
	# Priority 2: DAMAGED (show hurt flash even while attacking)
	elif current_state & NPCManager.NPCState.DAMAGED:
		animation_name = state_to_animation.get(NPCManager.NPCState.DAMAGED, "hurt")
	# Priority 3: ATTACKING
	elif current_state & NPCManager.NPCState.ATTACKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.ATTACKING, "attacking")
	# Priority 4: WALKING
	elif current_state & NPCManager.NPCState.WALKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.WALKING, "walking")
	# Priority 5: IDLE (lowest)
	elif current_state & NPCManager.NPCState.IDLE:
		animation_name = state_to_animation.get(NPCManager.NPCState.IDLE, "idle")

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


## Take damage (attacker parameter is optional for backward compatibility)
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Reduce HP through stats system if available
	if stats:
		stats.hp -= amount

		# Emit damage signal for NPCManager
		damage_taken.emit(amount, stats.hp, stats.max_hp)

		# Check if monster died
		if stats.hp <= 0:
			current_state = NPCManager.NPCState.DEAD
			monster_died.emit()
			return

	# Add DAMAGED state with bitwise OR (allows coexisting with ATTACKING)
	_is_hurt = true
	current_state |= NPCManager.NPCState.DAMAGED

	# Notify NPCManager to set combat target (counter-attack)
	# Skip if monster is passive
	if attacker and NPCManager:
		var passive = false
		if has_method("is_passive"):
			passive = call("is_passive")
		if not passive:
			NPCManager.on_npc_damaged(self, attacker)

	# Call subclass-specific hurt behavior
	_on_take_damage(amount)


## Override this in subclasses for custom damage behavior (e.g., fleeing)
func _on_take_damage(amount: float) -> void:
	pass


## Called when animation finishes - clean up DAMAGED state if hurt animation finished
func _on_animation_finished() -> void:
	# If hurt animation just finished, remove DAMAGED state
	if _is_hurt and animated_sprite and animated_sprite.animation == state_to_animation.get(NPCManager.NPCState.DAMAGED, "hurt"):
		_is_hurt = false
		current_state &= ~NPCManager.NPCState.DAMAGED


## Check if this monster is passive (doesn't deal damage to others)
func is_passive() -> bool:
	return (current_state & NPCManager.NPCState.PASSIVE) != 0


## Check if this monster can attack
func can_attack() -> bool:
	return not is_passive()


## Called by InputManager when clicked (override in subclasses)
func _on_input_manager_clicked() -> void:
	pass


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
