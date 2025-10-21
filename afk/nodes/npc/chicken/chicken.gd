extends CharacterBody2D
class_name Chicken

## Chicken NPC - Passive Animal Enemy
## A harmless chicken that can only idle and show hurt reactions

## Emitted when the chicken is clicked
signal chicken_clicked

## Emitted when the chicken's state changes (bidirectional communication with NPCManager)
signal state_changed(old_state: int, new_state: int)

## Emitted when the chicken takes damage
signal damage_taken(amount: float, current_hp: float, max_hp: float)

## Emitted when the chicken dies
signal chicken_died

## Chicken's current state (uses NPCManager.NPCState enum)
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

## Chicken's faction (MONSTER - can be attacked by allies)
var faction: int = 1  # NPCManager.Faction.MONSTER

## Chicken's combat type (NONE - passive, doesn't attack)
var combat_type: int = 0  # NPCManager.CombatType.NONE

## Monster types (chicken is ANIMAL + PASSIVE)
var monster_types: Array[NPCManager.MonsterType] = [
	NPCManager.MonsterType.ANIMAL,
	NPCManager.MonsterType.PASSIVE
]

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer

# Controller reference
var controller = null  # Chickens use simpler AI, no complex controller needed

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_hurt: bool = false

# Cached background reference for bounds checking (performance optimization)
var _background_ref: Control = null


func _ready() -> void:
	# Cache background reference for performance (instead of get_tree().get_first_node_in_group every frame)
	_background_ref = get_tree().get_first_node_in_group("background")
	# Set up state timer for automatic state changes
	if state_timer:
		state_timer.timeout.connect(_on_state_timer_timeout)
		state_timer.start()

	# Register with InputManager for click detection
	await get_tree().process_frame
	if InputManager:
		InputManager.register_interactive_object(self, 40.0)  # 40 pixel click radius (smaller than warrior)
		print("Chicken registered with InputManager")

	# Initialize animation
	_update_animation()

	print("Chicken initialized - Current state: %s" % current_state)


func _process(delta: float) -> void:
	# Simple movement for chickens (works for both normal walking and panic fleeing)
	if current_state == NPCManager.NPCState.WALKING:
		# Calculate potential new position
		var new_position = position + (_move_direction * walk_speed * delta)

		# Check if new position is within walkable bounds (use cached reference for performance)
		# This applies to both normal walking AND panic fleeing
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
	if not animated_sprite:
		return

	match current_state:
		NPCManager.NPCState.IDLE:
			animated_sprite.play("idle")
		NPCManager.NPCState.WALKING:
			animated_sprite.play("idle")  # Chickens use idle animation for walking
		NPCManager.NPCState.DAMAGED:
			animated_sprite.play("hurt")


func _on_state_timer_timeout() -> void:
	# Randomly change state for AFK behavior (only if not hurt)
	if not _is_hurt:
		_random_state_change()


func _random_state_change() -> void:
	var states = [NPCManager.NPCState.IDLE, NPCManager.NPCState.WALKING]
	var weights = [70, 30]  # Chickens prefer to stay idle

	# Pick random state based on weights
	var total_weight = 0
	for w in weights:
		total_weight += w

	var random_value = randf() * total_weight
	var cumulative = 0

	for i in range(states.size()):
		cumulative += weights[i]
		if random_value <= cumulative:
			current_state = states[i]

			# Set random direction if walking
			if current_state == NPCManager.NPCState.WALKING:
				_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			else:
				_move_direction = Vector2.ZERO

			# Randomize next state change time
			state_timer.wait_time = randf_range(2.0, 5.0)
			break


## Take damage - chickens can take damage but don't fight back (passive means no attacking)
func take_damage(amount: float) -> void:
	# Reduce HP through stats system if available
	if stats:
		stats.hp -= amount
		print("Chicken took %d damage! HP: %d/%d" % [amount, stats.hp, stats.max_hp])

		# Emit damage signal for NPCManager
		damage_taken.emit(amount, stats.hp, stats.max_hp)

		# Check if chicken died
		if stats.hp <= 0:
			current_state = NPCManager.NPCState.DEAD
			chicken_died.emit()
			print("Chicken has died!")
			return

	# Show hurt animation
	_is_hurt = true
	current_state = NPCManager.NPCState.DAMAGED

	# Panic behavior: Run away in random direction after getting hit
	_panic_flee()

	# Return to idle after hurt animation
	await get_tree().create_timer(0.5).timeout
	_is_hurt = false
	current_state = NPCManager.NPCState.IDLE


## Panic flee behavior - chicken runs away after taking damage
func _panic_flee() -> void:
	# Pick a random direction to flee (prefer moving away from center of action)
	var viewport_size = get_viewport_rect().size
	var screen_center = Vector2(viewport_size.x / 2, viewport_size.y / 2)
	var away_from_center = (position - screen_center).normalized()

	# Add randomness to the flee direction
	var random_angle = randf_range(-PI/3, PI/3)  # ±60 degrees variation
	_move_direction = away_from_center.rotated(random_angle).normalized()

	# Enter walking state to start fleeing
	current_state = NPCManager.NPCState.WALKING

	# Flee for a short duration (2-3 seconds)
	var flee_duration = randf_range(2.0, 3.0)
	state_timer.wait_time = flee_duration
	state_timer.start()

	print("Chicken panicking and fleeing!")


## Check if this monster is passive (doesn't deal damage to others)
func is_passive() -> bool:
	return NPCManager.MonsterType.PASSIVE in monster_types


## Check if this monster can attack
func can_attack() -> bool:
	return not is_passive()


## Called by InputManager when this chicken is clicked
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("CHICKEN CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	chicken_clicked.emit()


## Called by InputManager when mouse enters this chicken
func _on_input_manager_hover_enter() -> void:
	# Highlight chicken when hovered
	if animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)


## Called by InputManager when mouse exits this chicken
func _on_input_manager_hover_exit() -> void:
	# Remove highlight
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
