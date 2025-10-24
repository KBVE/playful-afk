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

## ULID for this NPC - used to query Rust NPCDataWarehouse
## This is the primary identifier for all Rust-side NPC data
var ulid: PackedByteArray = PackedByteArray()

## DEPRECATED: Stats are now managed by Rust NPCDataWarehouse
## Legacy code may still reference stats, but all data comes from Rust via ULID
## Query stats via: NPCDataWarehouse.get_npc_stats_dict(ulid)

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
	# RUST COMBAT: Rust controls everything - animations, movement, and position updates
	# GDScript does nothing here - Rust updates Node2D directly via pooling system
	pass


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

	# Debug tracking (not used, kept for potential debugging)
	# Check if this is an ally (warrior/archer) using static_state
	var is_warrior_or_archer = (static_state & NPCManager.NPCStaticState.ALLY) != 0
	var is_actually_moving = current_speed > 0.1

	# Check high-priority states first (less common, but more important)
	if current_state & NPCManager.NPCState.DEAD:
		animation_name = state_to_animation.get(NPCManager.NPCState.DEAD, "dead")
	elif current_state & NPCManager.NPCState.DAMAGED:
		animation_name = state_to_animation.get(NPCManager.NPCState.DAMAGED, "hurt")
	elif current_state & NPCManager.NPCState.ATTACKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.ATTACKING, "attacking")
	# IMPORTANT: If actually moving (speed > 0), ALWAYS show walking animation
	# This ensures archers kiting in combat still show walking animation
	elif current_speed > 5.0:
		animation_name = state_to_animation.get(NPCManager.NPCState.WALKING, "walking")
		# Also set WALKING state if not already set (defensive fix for archers)
		if not (current_state & NPCManager.NPCState.WALKING):
			current_state = (current_state & ~NPCManager.NPCState.IDLE) | NPCManager.NPCState.WALKING
	# Check common states (most frequent cases)
	elif current_state & NPCManager.NPCState.WALKING:
		animation_name = state_to_animation.get(NPCManager.NPCState.WALKING, "walking")
	elif current_state & NPCManager.NPCState.IDLE:
		animation_name = state_to_animation.get(NPCManager.NPCState.IDLE, "idle")
	else:
		animation_name = "idle"  # Fallback to idle
		# Force IDLE state to fix this edge case - remove all other behavioral states first
		current_state = (current_state & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.ATTACKING & ~NPCManager.NPCState.DAMAGED) | NPCManager.NPCState.IDLE

	# Play animation if it exists, otherwise fallback to idle
	# Only call play() if animation has changed to avoid restarting the same animation
	if animated_sprite.sprite_frames.has_animation(animation_name):
		if animated_sprite.animation != animation_name:
			animated_sprite.play(animation_name)
	elif animated_sprite.sprite_frames.has_animation("idle"):
		if animated_sprite.animation != "idle":
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
	# RUST COMBAT: Damage is now handled by Rust NPCDataWarehouse
	if ulid.size() == 0:
		push_warning("NPC has no ULID assigned - cannot take damage")
		return

	# Get current stats from Rust to check HP
	var stats_dict = NPCDataWarehouse.get_npc_stats_dict(ulid)
	if stats_dict.is_empty():
		push_warning("NPC ULID not found in Rust warehouse")
		return

	var current_hp = stats_dict.get("hp", 0.0)
	var max_hp = stats_dict.get("max_hp", 100.0)
	var new_hp = max(0.0, current_hp - amount)

	# Update HP in Rust (Rust handles the actual damage)
	# TODO: Add update_npc_hp method to Rust if not exists

	# Emit damage signal for NPCManager
	damage_taken.emit(amount, new_hp, max_hp)

	# Check if NPC died
	if new_hp <= 0:
		# Preserve combat type and faction flags when dying
		current_state = (current_state & ~NPCManager.NPCState.IDLE & ~NPCManager.NPCState.WALKING & ~NPCManager.NPCState.ATTACKING) | NPCManager.NPCState.DEAD
		npc_died.emit()
		return

	# Notify NPCManager to set combat target (counter-attack)
	# Skip if NPC is passive
	if attacker and NPCManager:
		var passive = (static_state & NPCManager.NPCStaticState.PASSIVE) != 0
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
	current_state = (current_state & ~NPCManager.NPCState.IDLE) | NPCManager.NPCState.WALKING

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
		# Clear WALKING flag
		current_state = (current_state & ~NPCManager.NPCState.WALKING) | NPCManager.NPCState.IDLE
	movement_completed.emit(position.x)


## Stop automatic movement
func stop_auto_movement() -> void:
	# Only emit interrupted if we were actually walking (bitwise check)
	if current_state & NPCManager.NPCState.WALKING:
		movement_interrupted.emit()

	current_speed = 0.0
	# Only set to IDLE if not currently attacking
	if not (current_state & NPCManager.NPCState.ATTACKING):
		# Clear WALKING flag
		current_state = (current_state & ~NPCManager.NPCState.WALKING) | NPCManager.NPCState.IDLE


## Check if currently moving
func is_moving() -> bool:
	return (current_state & NPCManager.NPCState.WALKING) != 0


## Called when an animation finishes
func _on_animation_finished() -> void:
	if not animated_sprite or ulid.size() == 0:
		return

	# Tell Rust to clear DAMAGED state when hurt animation finishes
	if animated_sprite.animation == state_to_animation.get(NPCManager.NPCState.DAMAGED, "hurt"):
		NPCDataWarehouse.clear_damaged_state(ulid)
		# Sync state from Rust (using PackedByteArray directly)
		var new_state = NPCDataWarehouse.get_npc_behavioral_state(ulid)
		current_state = new_state
		# Update animation to reflect new state (e.g., WALKING after hurt)
		_update_animation()

	# Tell Rust to clear ATTACKING state when attack animation finishes
	if animated_sprite.animation == state_to_animation.get(NPCManager.NPCState.ATTACKING, "attacking"):
		NPCDataWarehouse.clear_attacking_state(ulid)
		# Sync state from Rust (using PackedByteArray directly)
		var new_state = NPCDataWarehouse.get_npc_behavioral_state(ulid)
		current_state = new_state
		# Update animation to reflect new state (e.g., WALKING after attack)
		_update_animation()
		# Clear projectile metadata when attack finishes
		if has_meta("pending_projectile"):
			remove_meta("pending_projectile")
		if has_meta("projectile_fired"):
			remove_meta("projectile_fired")


## Fire pending projectile (called during attack animation)
func _fire_pending_projectile() -> void:
	if not has_meta("pending_projectile"):
		return

	var projectile_data = get_meta("pending_projectile")
	var projectile_type = projectile_data.get("type", "arrow")
	var target = projectile_data.get("target")
	var target_pos = projectile_data.get("target_pos", Vector2.ZERO)
	var speed = projectile_data.get("speed", 300.0)

	# IMPORTANT: Face the target before firing
	# This ensures the archer sprite is flipped correctly
	if animated_sprite and target_pos != Vector2.ZERO:
		var direction_to_target = (target_pos - global_position).normalized()
		animated_sprite.flip_h = direction_to_target.x < 0

	# Fire projectile from ProjectileManager
	if ProjectileManager and projectile_type == "arrow":
		var from_pos = global_position
		var arrow = ProjectileManager.fire_arrow(from_pos, target_pos, speed)
		if arrow:
			# Store attacker reference and target ULID for collision handling
			arrow.attacker = self
			if target and "ulid" in target and target.ulid.size() > 0:
				arrow.set_meta("target_ulid", target.ulid)


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
