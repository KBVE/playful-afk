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
var current_state: int = NPCManager.NPCState.IDLE:
	set(value):
		if current_state != value:
			var old_state = current_state
			current_state = value
			_update_animation()
			# Emit state change signal for NPCManager
			state_changed.emit(old_state, current_state)

## Movement speed when walking
@export var walk_speed: float = 50.0

## NPC Stats reference (assigned by NPCManager)
var stats: NPCStats = null

## NPC's faction (set by subclasses)
var faction: int = 0  # NPCManager.Faction.ALLY by default

## NPC's combat type (set by subclasses)
var combat_type: int = 0  # NPCManager.CombatType.NONE by default

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_player_controlled: bool = false

# Cached background reference for bounds checking
var _background_ref: Control = null

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
	# Cache background reference for performance
	_background_ref = get_tree().get_first_node_in_group("background")

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
	else:  # Default to idle (most common state)
		animation_name = state_to_animation.get(NPCManager.NPCState.IDLE, "idle")

	# Play animation if it exists, otherwise fallback to idle
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
	elif animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")


## Attack action (can be overridden by subclasses)
func attack() -> void:
	var previous_state = current_state
	current_state = NPCManager.NPCState.ATTACKING

	await get_tree().create_timer(1.0).timeout
	current_state = previous_state


## Take damage (can be overridden by subclasses)
func take_damage(amount: float) -> void:
	# Reduce HP through stats system
	if not stats:
		push_warning("NPC has no stats assigned - cannot take damage")
		return

	var previous_state = current_state
	stats.hp -= amount
	print("NPC took %d damage! HP: %d/%d" % [amount, stats.hp, stats.max_hp])

	# Emit damage signal for NPCManager
	damage_taken.emit(amount, stats.hp, stats.max_hp)

	# Check if NPC died
	if stats.hp <= 0:
		current_state = NPCManager.NPCState.DEAD
		npc_died.emit()
		print("NPC has died!")
		return

	# Play hurt animation
	current_state = NPCManager.NPCState.DAMAGED
	await get_tree().create_timer(0.5).timeout

	# Return to previous state
	current_state = previous_state


## Set NPC to manual control mode
func set_player_controlled(controlled: bool) -> void:
	_is_player_controlled = controlled
	# NPCManager AI system will respect _is_player_controlled flag


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

	current_state = NPCManager.NPCState.WALKING

	# Emit signal to AI System
	movement_started.emit(target_x)


## Update movement (handles targeted movement from NPCManager AI)
func _update_movement(delta: float) -> void:
	# Only move if in WALKING state (set by NPCManager AI or move_to_position)
	if current_state != NPCManager.NPCState.WALKING:
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
	current_state = NPCManager.NPCState.IDLE
	movement_completed.emit(position.x)


## Stop automatic movement
func stop_auto_movement() -> void:
	# Only emit interrupted if we were actually walking
	if current_state == NPCManager.NPCState.WALKING:
		movement_interrupted.emit()

	current_speed = 0.0
	current_state = NPCManager.NPCState.IDLE


## Check if currently moving
func is_moving() -> bool:
	return current_state == NPCManager.NPCState.WALKING


## Called when an animation finishes
func _on_animation_finished() -> void:
	# Check if this animation should loop
	var is_looping_state = current_state in [NPCManager.NPCState.IDLE, NPCManager.NPCState.WALKING]

	if not is_looping_state:
		# Non-looping animation finished (attacking, hurt, dead, etc.)
		if current_state != NPCManager.NPCState.DEAD:
			current_state = NPCManager.NPCState.IDLE


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
