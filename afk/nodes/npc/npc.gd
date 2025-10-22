extends CharacterBody2D
class_name NPC

## Base NPC Class
## Shared functionality for all NPCs (Archer, Warrior, etc.)
## Handles states, movement, animations, combat integration, and AI communication

## Signals for bidirectional communication with NPCManager/AI System
signal state_changed(old_state: int, new_state: int)
signal damage_taken(amount: float, current_hp: float, max_hp: float)
signal npc_died
signal movement_started(target_position: float)
signal movement_completed(final_position: float)
signal movement_interrupted()

## NPC's current state (uses NPCManager.NPCState enum)
## ONLY contains behavioral/dynamic states (IDLE, WALKING, ATTACKING, etc.)
## Combat type and faction are now in static_state (immutable)
var current_state: int = NPCManager.NPCState.IDLE:
	set(value):
		if current_state != value:
			var old_state = current_state
			current_state = value
			_update_animation()
			# Emit state change signal for NPCManager
			state_changed.emit(old_state, current_state)

## Static/immutable NPC properties (combat type + faction)
## Set once during initialization, NEVER modified during gameplay
var static_state: int = 0

## Movement speed when walking
@export var walk_speed: float = 50.0

## Combat range - distance at which this NPC can attack
## For MELEE: attack range (default ~60px)
## For RANGED: optimal firing distance (default ~150px)
@export var attack_range: float = 60.0

## NPC Stats reference (assigned by NPCManager)
var stats: NPCStats = null

## Deprecated properties - now using NPCState bitwise flags
## Faction and combat type are now in current_state
## Example: MELEE | ALLY | IDLE or RANGED | ALLY | WALKING

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_player_controlled: bool = false

# Animation mapping - maps NPCManager.NPCState enum to animation names
var state_to_animation: Dictionary = {}

# Movement state
var current_speed: float = 0.0
var max_speed: float = 100.0  # Can be overridden by subclasses
var acceleration_rate: float = 350.0
var deceleration_rate: float = 350.0
var target_position_x: float = 0.0
var deceleration_distance: float = 50.0


func _ready() -> void:
	# Initialize state-to-animation mapping (can be overridden by subclasses)
	_initialize_animation_mapping()

	# Connect to animation finished signal
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

	# Register with InputManager for click detection
	await get_tree().process_frame
	_register_with_input_manager()

	# Initialize animation
	_update_animation()

	# Subclasses can override _on_ready_complete() for additional setup
	_on_ready_complete()


## Override this in subclasses for custom animation mappings
func _initialize_animation_mapping() -> void:
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walking",
		NPCManager.NPCState.ATTACKING: "attacking",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "dead"
	}


## Override this in subclasses for additional ready logic
func _on_ready_complete() -> void:
	pass


## Override this in subclasses for custom InputManager registration
func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 80.0)  # 80 pixel click radius


func _process(delta: float) -> void:
	# Update movement
	_update_movement(delta)


func _physics_process(delta: float) -> void:
	# Physics disabled - movement handled directly in _process
	pass


func _update_animation() -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	# Since states are bitwise, check individual flags with priority order
	# Priority: DEAD > DAMAGED > ATTACKING > WALKING > IDLE
	# Early exit pattern for common cases (optimized for performance)
	var animation_name: String = ""

	# Debug for warriors/archers to see what animation they're choosing
	var is_warrior_or_archer = (current_state & NPCManager.NPCState.ALLY) and (current_state & (NPCManager.NPCState.MELEE | NPCManager.NPCState.RANGED))
	var is_actually_moving = current_speed > 0.1

	# Check high-priority states first (less common, but more important)
	if current_state & NPCManager.NPCState.DEAD:
		animation_name = state_to_animation.get(NPCManager.NPCState.DEAD, "dead")
	elif current_state & NPCManager.NPCState.DAMAGED:
		animation_name = state_to_animation.get(NPCManager.NPCState.DAMAGED, "hurt")
	elif current_state & NPCManager.NPCState.ATTACKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.ATTACKING, "attacking")
	# Check common states (most frequent cases)
	elif current_state & NPCManager.NPCState.WALKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.WALKING, "walking")
	# If actually moving (speed > 0), always show walking animation regardless of state
	elif current_speed > 5.0:
		animation_name = state_to_animation.get(NPCManager.NPCState.WALKING, "walking")
	elif current_state & NPCManager.NPCState.IDLE:
		animation_name = state_to_animation.get(NPCManager.NPCState.IDLE, "idle")
	else:
		# Debug: No behavioral state flag found, check what flags are set
		var is_ally = current_state & NPCManager.NPCState.ALLY
		var is_melee = current_state & NPCManager.NPCState.MELEE
		var is_ranged = current_state & NPCManager.NPCState.RANGED
		if is_ally and (is_melee or is_ranged):
			print("WARNING: Warrior/Archer with no behavioral state! State=%d, Stack trace:" % current_state)
			print(get_stack())
		animation_name = "idle"  # Fallback to idle
		# Force IDLE state to fix this edge case - remove all other behavioral states first
		current_state = (current_state & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.ATTACKING & ~NPCManager.NPCState.DAMAGED) | NPCManager.NPCState.IDLE

	# Play animation if it exists, otherwise fallback to idle
	# Only call play() if animation has changed to avoid restarting the same animation
	var is_warrior = (current_state & NPCManager.NPCState.ALLY) and (current_state & NPCManager.NPCState.MELEE)
	if animated_sprite.sprite_frames.has_animation(animation_name):
		if animated_sprite.animation != animation_name:
			if is_warrior:
				print("ANIM CHANGE: %s -> %s (state=%d, speed=%.2f)" % [animated_sprite.animation, animation_name, current_state, current_speed])
			animated_sprite.play(animation_name)
	elif animated_sprite.sprite_frames.has_animation("idle"):
		if animated_sprite.animation != "idle":
			if is_warrior:
				print("ANIM CHANGE: %s -> idle (fallback, state=%d)" % [animated_sprite.animation, current_state])
			animated_sprite.play("idle")


## Attack action (can be overridden by subclasses)
func attack() -> void:
	# Preserve combat type and faction flags, remove behavioral states, add ATTACKING
	current_state = (current_state & ~NPCManager.NPCState.IDLE & ~NPCManager.NPCState.WALKING) | NPCManager.NPCState.ATTACKING

	await get_tree().create_timer(1.0).timeout

	# After attack animation, return to IDLE (don't restore previous state as it may be stale)
	# Remove ATTACKING, add IDLE, preserve combat type and faction flags
	current_state = (current_state & ~NPCManager.NPCState.ATTACKING) | NPCManager.NPCState.IDLE


## Take damage (attacker parameter is optional for backward compatibility)
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Reduce HP through stats system
	if not stats:
		push_warning("NPC has no stats assigned - cannot take damage")
		return

	stats.hp -= amount

	# Emit damage signal for NPCManager
	damage_taken.emit(amount, stats.hp, stats.max_hp)

	# Check if NPC died
	if stats.hp <= 0:
		# Preserve combat type and faction flags when dying
		current_state = (current_state & ~NPCManager.NPCState.IDLE & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.ATTACKING) | NPCManager.NPCState.DEAD
		npc_died.emit()
		return

	# Notify NPCManager to set combat target (counter-attack)
	# Skip if NPC is passive
	if attacker and NPCManager:
		var passive = false
		if has_method("is_passive"):
			passive = call("is_passive")
		if not passive:
			NPCManager.on_npc_damaged(self, attacker)

	# Play hurt animation - preserve combat type and faction flags
	current_state = (current_state & ~NPCManager.NPCState.IDLE & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.ATTACKING) | NPCManager.NPCState.DAMAGED
	await get_tree().create_timer(0.5).timeout

	# After damage animation, return to IDLE (don't restore previous state as NPCManager may have changed it)
	# Remove DAMAGED, add IDLE, preserve combat type and faction flags
	current_state = (current_state & ~NPCManager.NPCState.DAMAGED) | NPCManager.NPCState.IDLE


## Set NPC to manual control mode
func set_player_controlled(controlled: bool) -> void:
	_is_player_controlled = controlled
	# Propagate to NPCManager AI system
	if NPCManager:
		NPCManager.set_npc_player_controlled(self, controlled)


## ============================================================================
## MOVEMENT FUNCTIONS
## ============================================================================

## Start automatic movement to a target position
func move_to_position(target_x: float) -> void:
	target_position_x = target_x

	# Determine direction
	var direction = 1 if target_x > position.x else -1
	_move_direction = Vector2(direction, 0)

	# Start from zero speed for smooth acceleration
	current_speed = 0.0

	# Update state to trigger walking animation
	# Don't change state if currently attacking (let attack animation finish)
	if CombatManager and CombatManager.has_state(self, NPCManager.NPCState.ATTACKING):
		print("NPC movement queued - waiting for attack to finish")
		return  # Don't interrupt attack animation

	# Preserve combat type and faction flags when transitioning to WALKING
	# Add WAYPOINT flag to prevent AI from interrupting movement
	current_state = (current_state & ~NPCManager.NPCState.IDLE) | NPCManager.NPCState.WALKING | NPCManager.NPCState.WAYPOINT

	# Emit signal to AI System
	movement_started.emit(target_x)


## Update movement (handles targeted movement from NPCManager AI)
func _update_movement(delta: float) -> void:
	# Only move if in WALKING state (set by NPCManager AI or move_to_position)
	# Use bitwise check since state includes combat type and faction flags
	if not (current_state & NPCManager.NPCState.WALKING):
		return

	# Calculate distance to target
	var distance_to_target = abs(target_position_x - position.x)

	# Determine if we should decelerate (within deceleration zone)
	var should_decelerate = distance_to_target < deceleration_distance

	if should_decelerate:
		# Decelerate to stop smoothly
		current_speed -= deceleration_rate * delta
		current_speed = max(current_speed, 0.0)

		# Check if reached target
		if distance_to_target < 1.0 or current_speed == 0.0:
			_complete_movement()
			return
	else:
		# Accelerate or maintain speed
		current_speed += acceleration_rate * delta
		current_speed = min(current_speed, max_speed)

	# Move the NPC
	var movement = _move_direction * current_speed * delta
	position += movement

	# Flip sprite based on direction
	if animated_sprite:
		animated_sprite.flip_h = _move_direction.x < 0


## Complete movement - called when NPC reaches target
func _complete_movement() -> void:
	current_speed = 0.0
	# Only set to IDLE if not currently attacking
	if not (current_state & NPCManager.NPCState.ATTACKING):
		# Preserve combat type and faction flags when transitioning to IDLE
		# Clear WAYPOINT, WALKING, RETREATING, PURSUING flags
		current_state = (current_state & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.WAYPOINT & ~NPCManager.NPCState.RETREATING & ~NPCManager.NPCState.PURSUING) | NPCManager.NPCState.IDLE
	movement_completed.emit(position.x)


## Stop automatic movement
func stop_auto_movement() -> void:
	# Only emit interrupted if we were actually walking (bitwise check)
	if current_state & NPCManager.NPCState.WALKING:
		movement_interrupted.emit()

	current_speed = 0.0
	# Only set to IDLE if not currently attacking
	if not (current_state & NPCManager.NPCState.ATTACKING):
		# Preserve combat type and faction flags when transitioning to IDLE
		# Clear WAYPOINT, WALKING, RETREATING, PURSUING flags
		current_state = (current_state & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.WAYPOINT & ~NPCManager.NPCState.RETREATING & ~NPCManager.NPCState.PURSUING) | NPCManager.NPCState.IDLE


## Check if currently moving
func is_moving() -> bool:
	return (current_state & NPCManager.NPCState.WALKING) != 0


## Called when an animation finishes
func _on_animation_finished() -> void:
	# Check if this animation should loop using bitwise checks
	# IDLE, WALKING, and ATTACKING animations loop
	var is_looping_state = (current_state & NPCManager.NPCState.IDLE) or \
	                       (current_state & NPCManager.NPCState.WALKING) or \
	                       (current_state & NPCManager.NPCState.ATTACKING)

	if not is_looping_state:
		# Non-looping animation finished (hurt, dead, etc.)
		# Only transition if not dead (use bitwise check)
		if not (current_state & NPCManager.NPCState.DEAD):
			# Preserve combat type and faction flags when transitioning to IDLE
			current_state = (current_state & ~NPCManager.NPCState.DAMAGED) | NPCManager.NPCState.IDLE


## ============================================================================
## INPUT CALLBACKS (Override in subclasses for custom behavior)
## ============================================================================

## Called by InputManager when this NPC is clicked
func _on_input_manager_clicked() -> void:
	pass  # Override in subclasses


## Called by InputManager when mouse enters this NPC
func _on_input_manager_hover_enter() -> void:
	# Highlight NPC when hovered
	if animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)


## Called by InputManager when mouse exits this NPC
func _on_input_manager_hover_exit() -> void:
	# Remove highlight
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
