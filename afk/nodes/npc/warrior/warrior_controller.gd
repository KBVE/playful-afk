extends Node
class_name WarriorController

## WarriorController - Animation and Movement Controller for Warrior
## Handles animation sequencing and movement coordination
## Automatically syncs animations with warrior states and movement

## Reference to the warrior being controlled
var warrior: Warrior

## Animation sprite reference
var animated_sprite: AnimatedSprite2D

## Animation mapping - maps state names to animation sequences
var animation_sequences: Dictionary = {
	# State: [animation_name] - plays animation
	"idle": ["idle"],              # Idle animation (6 frames)
	"walking": ["walking"],        # Walking/running animation (8 frames)
	"running": ["walking"],        # Running uses walking animation
	"attacking": ["attacking"],    # Attack animation (5 frames)
}

## Current animation sequence being played
var current_sequence: Array = []
var current_sequence_index: int = 0
var is_playing_sequence: bool = false

## Movement settings
var move_speed: float = 50.0
var move_direction: Vector2 = Vector2.ZERO

## Movement state system
enum MovementState { IDLE, ACCELERATING, MOVING, DECELERATING }
var movement_state: MovementState = MovementState.IDLE:
	set(value):
		if movement_state != value:
			movement_state = value
			_update_animation_from_movement_state()
var current_speed: float = 0.0
var max_speed: float = 120.0  # Faster movement speed
var acceleration_rate: float = 400.0
var deceleration_rate: float = 400.0
var target_position_x: float = 0.0
var deceleration_distance: float = 50.0
var is_auto_moving: bool = false

## Random movement behavior
var random_move_timer: Timer = null
var min_wait_time: float = 3.0
var max_wait_time: float = 8.0
var idle_chance: float = 0.4  # 40% chance to idle
var screen_bounds: Vector2 = Vector2(100, 1052)  # Default bounds


func _init(warrior_instance: Warrior = null) -> void:
	if warrior_instance:
		set_warrior(warrior_instance)


func _ready() -> void:
	if warrior and warrior.has_node("AnimatedSprite2D"):
		animated_sprite = warrior.get_node("AnimatedSprite2D")

		# Connect to animation finished signal
		if animated_sprite:
			animated_sprite.animation_finished.connect(_on_animation_finished)


## Set the warrior this controller manages
func set_warrior(warrior_instance: Warrior) -> void:
	warrior = warrior_instance
	if warrior:
		move_speed = warrior.walk_speed


## Update animation based on movement state
func _update_animation_from_movement_state() -> void:
	if not warrior:
		return

	match movement_state:
		MovementState.IDLE:
			warrior.current_state = "Idle"
			play_state("idle")
			print("Animation: IDLE - playing idle animation")
		MovementState.ACCELERATING, MovementState.MOVING, MovementState.DECELERATING:
			warrior.current_state = "Walking"
			play_state("walking")
			print("Animation: MOVING - playing walking animation")


## Play a state animation
func play_state(state_name: String) -> void:
	if not animation_sequences.has(state_name):
		push_warning("Animation sequence for state '%s' not found" % state_name)
		return

	current_sequence = animation_sequences[state_name]
	current_sequence_index = 0
	is_playing_sequence = true

	_play_next_in_sequence()


## Play a specific row animation directly
func play_animation(row_name: String, loop: bool = true) -> void:
	if not animated_sprite:
		return

	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(row_name):
		animated_sprite.play(row_name)
		is_playing_sequence = false
	else:
		push_warning("Animation '%s' not found in sprite frames" % row_name)


## Add a custom animation sequence
func add_animation_sequence(state_name: String, animation_rows: Array) -> void:
	animation_sequences[state_name] = animation_rows
	print("Added animation sequence '%s': %s" % [state_name, animation_rows])


## Move the warrior in a direction with matching animation
func move_warrior(direction: Vector2, use_walking_animation: bool = true) -> void:
	if not warrior:
		return

	move_direction = direction.normalized()
	warrior.velocity = move_direction * move_speed

	# Flip sprite based on movement direction
	if animated_sprite and move_direction.x != 0:
		animated_sprite.flip_h = move_direction.x < 0

	# Auto-play walking animation if moving
	if use_walking_animation and move_direction.length() > 0:
		if not is_playing_sequence or current_sequence != animation_sequences.get("walking", []):
			play_state("walking")


## Stop warrior movement
func stop_movement() -> void:
	if warrior:
		warrior.velocity = Vector2.ZERO
		move_direction = Vector2.ZERO


## Called when an animation finishes
func _on_animation_finished() -> void:
	if not is_playing_sequence:
		return

	# Check if this animation should loop
	var current_state = warrior.current_state.to_lower() if warrior else ""
	var is_looping_state = current_state in ["idle", "walking", "running"]

	# Move to next animation in sequence
	current_sequence_index += 1

	if current_sequence_index >= current_sequence.size():
		# Sequence finished
		if is_looping_state:
			# Loop the animation
			current_sequence_index = 0
			_play_next_in_sequence()
		else:
			# Non-looping sequence finished (attacking, hurt, dead, etc.)
			is_playing_sequence = false
			if current_state != "dead":
				play_state("idle")
	else:
		# Play next animation in sequence
		_play_next_in_sequence()


## Play the next animation in the current sequence
func _play_next_in_sequence() -> void:
	if current_sequence_index >= current_sequence.size():
		return

	var animation_name = current_sequence[current_sequence_index]

	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.play(animation_name)
		else:
			push_warning("Animation '%s' not found in sequence" % animation_name)
			is_playing_sequence = false


## Get current animation info (for debugging)
func get_animation_info() -> Dictionary:
	return {
		"current_sequence": current_sequence,
		"sequence_index": current_sequence_index,
		"is_playing_sequence": is_playing_sequence,
		"current_animation": animated_sprite.animation if animated_sprite else "none",
		"is_playing": animated_sprite.is_playing() if animated_sprite else false
	}


## Start automatic movement to a target position
func move_to_position(target_x: float) -> void:
	if not warrior:
		return

	target_position_x = target_x
	is_auto_moving = true

	# Determine direction
	var direction = 1 if target_x > warrior.position.x else -1
	move_direction = Vector2(direction, 0)

	# Start accelerating (setter will update animation to walking)
	movement_state = MovementState.ACCELERATING
	current_speed = 0.0

	print("Warrior starting auto-move to position: %s" % target_x)


## Update movement (call this from _process or _physics_process)
func update_movement(delta: float) -> void:
	if not warrior:
		return

	# Force IDLE state when not auto-moving
	if not is_auto_moving:
		if movement_state != MovementState.IDLE:
			movement_state = MovementState.IDLE  # Setter will update animation
		return

	# Handle active movement states
	match movement_state:
		MovementState.ACCELERATING:
			_handle_movement_acceleration(delta)
		MovementState.MOVING:
			_handle_movement_moving(delta)
		MovementState.DECELERATING:
			_handle_movement_deceleration(delta)


func _handle_movement_acceleration(delta: float) -> void:
	if not warrior:
		return

	# Accelerate
	current_speed += acceleration_rate * delta
	current_speed = min(current_speed, max_speed)

	# Move warrior
	warrior.position.x += current_speed * delta * move_direction.x

	# Flip sprite
	if animated_sprite:
		animated_sprite.flip_h = (move_direction.x < 0)

	# Transition to full speed movement
	if current_speed >= max_speed:
		movement_state = MovementState.MOVING


func _handle_movement_moving(delta: float) -> void:
	if not warrior:
		return

	# Move at constant speed
	warrior.position.x += current_speed * delta * move_direction.x

	# Check distance to target
	var distance_to_target = abs(target_position_x - warrior.position.x)

	# Start decelerating when close
	if distance_to_target <= deceleration_distance:
		movement_state = MovementState.DECELERATING


func _handle_movement_deceleration(delta: float) -> void:
	if not warrior:
		return

	# Check distance to target
	var distance_to_target = abs(target_position_x - warrior.position.x)

	# If very close to target, just coast there slowly
	if distance_to_target < 5.0:
		# Move directly to target at very slow speed
		var move_amount = min(distance_to_target, 20.0 * delta)
		warrior.position.x += move_amount * move_direction.x

		# Check if reached
		if abs(target_position_x - warrior.position.x) < 1.0:
			is_auto_moving = false
			print("Warrior reached target position")
		return

	# Normal deceleration
	current_speed -= deceleration_rate * delta
	current_speed = max(current_speed, 0.0)

	# Continue moving
	warrior.position.x += current_speed * delta * move_direction.x

	# Check if stopped too early
	if current_speed <= 0.0:
		is_auto_moving = false
		print("Warrior stopped before reaching target")


## Stop automatic movement
func stop_auto_movement() -> void:
	is_auto_moving = false
	movement_state = MovementState.IDLE
	current_speed = 0.0


## Check if currently auto-moving
func is_moving() -> bool:
	return is_auto_moving and movement_state != MovementState.IDLE


## Start random autonomous movement behavior
func start_random_movement(bounds_min: float = 100.0, bounds_max: float = 1052.0) -> void:
	screen_bounds = Vector2(bounds_min, bounds_max)

	# Create and setup timer
	if not random_move_timer:
		random_move_timer = Timer.new()
		random_move_timer.timeout.connect(_on_random_move_timer_timeout)
		warrior.add_child(random_move_timer)

	# Start with random wait time
	random_move_timer.wait_time = randf_range(min_wait_time, max_wait_time)
	random_move_timer.start()

	print("Warrior random movement started")


## Stop random movement behavior
func stop_random_movement() -> void:
	if random_move_timer:
		random_move_timer.stop()
	stop_auto_movement()


func _on_random_move_timer_timeout() -> void:
	if not warrior:
		return

	# Random action: idle or walk
	var random_action = randf()

	if random_action < idle_chance:
		# Idle - stop all movement (update_movement will handle animation)
		stop_auto_movement()
		print("Warrior idling")
	else:
		# Walk to a random position
		var target_x = randf_range(screen_bounds.x, screen_bounds.y)
		move_to_position(target_x)
		print("Warrior walking to position: ", target_x)

	# Set next timer
	random_move_timer.wait_time = randf_range(min_wait_time, max_wait_time)
	random_move_timer.start()
