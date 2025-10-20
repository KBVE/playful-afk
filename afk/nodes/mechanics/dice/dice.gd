extends Node2D
class_name Dice

## D20 Dice Mechanic
## A 21-faced dice that spins and lands on a value from 0 to 20

signal dice_rolled(result: int)
signal dice_roll_started
signal dice_roll_finished(result: int)

@onready var sprite: Sprite2D = $Sprite2D

## Preloaded dice textures for direct control
var dice_textures: Array[Texture2D] = []

## Rolling animation settings
@export var total_roll_duration: float = 2.0  ## Total time for the entire roll animation
@export var initial_shake_intensity: float = 5.0  ## Initial shake/jump intensity
@export var initial_frame_speed: float = 0.02  ## Initial time between frame changes (very fast!)
@export var final_frame_speed: float = 0.4  ## Final time between frame changes (slow)
@export var stop_threshold: float = 0.7  ## When to start settling (0.0-1.0, starts slowing earlier)
@export var settle_time: float = 0.5  ## Time to wait after animation stops before showing result

## State management
var is_rolling: bool = false
var is_settling: bool = false
var spin_timer: float = 0.0
var frame_timer: float = 0.0
var settle_timer: float = 0.0
var settle_frame_count: int = 0
var frames_to_wait: int = 5  # Wait 5 frames after animation stops
var current_frame_delay: float = 0.03
var original_position: Vector2 = Vector2.ZERO
var current_dice_value: int = 0  # The actual dice value (0-20)


func _ready() -> void:
	# Load all dice textures (Dice0.png through Dice20.png)
	for i in range(21):
		var texture_path = "res://nodes/mechanics/dice/Dice" + str(i) + ".png"
		var texture = load(texture_path) as Texture2D
		if texture:
			dice_textures.append(texture)
		else:
			push_error("Failed to load dice texture: ", texture_path)

	print("Loaded ", dice_textures.size(), " dice textures")

	if sprite:
		# Set to a random starting dice face
		current_dice_value = randi_range(0, 20)
		_set_dice_texture(current_dice_value)
		# Store original position for shake effect
		original_position = sprite.position
		print("Dice initialized to value: ", current_dice_value)


func _process(delta: float) -> void:
	if is_rolling:
		spin_timer += delta

		# Check if roll is complete - enter settling phase FIRST
		if spin_timer >= total_roll_duration:
			_start_settling()
			return  # Stop processing immediately to lock the frame

		frame_timer += delta

		# Calculate progress through the roll (0.0 to 1.0)
		var roll_progress = clamp(spin_timer / total_roll_duration, 0.0, 1.0)

		# Use aggressive ease-out curve only for frame speed, NOT shake
		var eased_progress = ease(roll_progress, -4.0)

		# After stop_threshold, rapidly decelerate to final frame
		if roll_progress > stop_threshold:
			# Quick settle phase - frames slow down dramatically
			var settle_progress = (roll_progress - stop_threshold) / (1.0 - stop_threshold)
			eased_progress = 1.0 - pow(1.0 - settle_progress, 4.0)  # Quick stop

		# Update frame delay based on progress (very fast → very slow)
		current_frame_delay = lerp(initial_frame_speed, final_frame_speed, eased_progress)

		# KEEP SHAKE CONSTANT throughout the roll (doesn't fade!)
		var shake_intensity = initial_shake_intensity

		# Apply constant shake/bounce to sprite position
		var offset_x = randf_range(-shake_intensity, shake_intensity)
		var offset_y = randf_range(-shake_intensity * 0.7, shake_intensity * 0.7)
		sprite.position = original_position + Vector2(offset_x, offset_y)

		# Keep rotation constant throughout (dice tumbling)
		sprite.rotation = randf_range(-0.12, 0.12)

		# Change dice value based on timer (only if we're still rolling)
		if frame_timer >= current_frame_delay:
			frame_timer = 0.0
			# Cycle through values sequentially
			current_dice_value = (current_dice_value + 1) % 21  # 0-20 inclusive
			_set_dice_texture(current_dice_value)

	elif is_settling:
		# Wait for several frames to ensure the sprite is fully settled
		settle_frame_count += 1

		# Dice is completely static during settling - don't touch anything!
		# The is_rolling=false flag already prevents value changes

		# Debug: Print value every settle frame
		if settle_frame_count <= frames_to_wait:
			print("Settle frame ", settle_frame_count, "/", frames_to_wait, " - Current value: ", current_dice_value)

		# After waiting enough frames, read the result
		if settle_frame_count >= frames_to_wait:
			_finish_roll()


## Roll the dice and get a result from 0 to 20
func roll() -> void:
	if is_rolling:
		push_warning("Dice is already rolling!")
		return

	print("========================================")
	print("DICE ROLL STARTED")
	print("========================================")

	is_rolling = true
	spin_timer = 0.0
	frame_timer = 0.0
	current_frame_delay = initial_frame_speed

	# Start from a random value
	current_dice_value = randi_range(0, 20)
	_set_dice_texture(current_dice_value)

	dice_roll_started.emit()
	print("Dice is rolling...")


## Start the settling phase - dice becomes static
func _start_settling() -> void:
	is_rolling = false
	is_settling = true
	settle_timer = 0.0
	settle_frame_count = 0  # Reset frame counter

	# Lock the sprite position and rotation
	if sprite:
		sprite.position = original_position
		sprite.rotation = 0.0

	print("========================================")
	print("SETTLING STARTED - Dice value locked at: ", current_dice_value)
	print("========================================")


## Finish the roll and display the result
func _finish_roll() -> void:
	is_settling = false

	# Use the current_dice_value variable - this is our single source of truth
	var final_result = current_dice_value

	print("========================================")
	print("DICE ROLL FINISHED (after ", settle_frame_count, " settle frames)")
	print("Final dice value: ", final_result)
	print("========================================")

	dice_rolled.emit(final_result)
	dice_roll_finished.emit(final_result)


## Get the last rolled result
func get_result() -> int:
	return current_dice_value


## Check if dice is currently rolling
func is_dice_rolling() -> bool:
	return is_rolling or is_settling


## Roll the dice and wait for the result (async)
func roll_and_wait() -> int:
	roll()
	await dice_roll_finished
	return get_result()


## Set the dice to show a specific face (for testing/cheating)
func set_face(face: int) -> void:
	if face < 0 or face > 20:
		push_error("Invalid dice face: ", face, " (must be 0-20)")
		return

	current_dice_value = face
	_set_dice_texture(face)
	print("Dice face set to: ", face)


## Helper function to set the dice texture based on value
func _set_dice_texture(value: int) -> void:
	if value >= 0 and value < dice_textures.size() and sprite:
		sprite.texture = dice_textures[value]
