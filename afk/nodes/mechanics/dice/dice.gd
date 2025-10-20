extends Node2D
class_name Dice

## D20 Dice Mechanic
## A 20-faced dice that spins and lands on a value from 1 to 20

signal dice_rolled(result: int)
signal dice_roll_started
signal dice_roll_finished(result: int)

@onready var sprite: Sprite2D = $Sprite2D

## Rolling animation settings
@export var total_roll_duration: float = 2.0  ## Total time for the entire roll animation
@export var initial_shake_intensity: float = 8.0  ## Initial shake/jump intensity
@export var initial_frame_speed: float = 0.03  ## Initial time between frame changes (fast)
@export var final_frame_speed: float = 0.3  ## Final time between frame changes (slow)

## State management
var is_rolling: bool = false
var spin_timer: float = 0.0
var frame_timer: float = 0.0
var current_frame_delay: float = 0.03
var original_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	if sprite:
		# Set default frame to a random dice face
		sprite.frame = randi_range(0, 19)  # Frames 0-19 for Dice1-Dice20
		# Store original position for shake effect
		original_position = sprite.position
		print("Dice initialized at frame: ", sprite.frame)


func _process(delta: float) -> void:
	if is_rolling:
		spin_timer += delta
		frame_timer += delta

		# Calculate progress through the roll (0.0 to 1.0)
		var roll_progress = clamp(spin_timer / total_roll_duration, 0.0, 1.0)

		# Ease out the progress for smoother deceleration
		var eased_progress = ease(roll_progress, -2.0)  # Ease out (fast start, slow end)

		# Update frame delay based on progress (fast → slow)
		current_frame_delay = lerp(initial_frame_speed, final_frame_speed, eased_progress)

		# Update shake/jump intensity (strong → weak)
		var shake_intensity = initial_shake_intensity * (1.0 - eased_progress)

		# Apply shake/jump to sprite position
		var offset_x = randf_range(-shake_intensity, shake_intensity)
		var offset_y = randf_range(-shake_intensity, shake_intensity)
		sprite.position = original_position + Vector2(offset_x, offset_y)

		# Change frames based on timer
		if frame_timer >= current_frame_delay:
			frame_timer = 0.0
			# Cycle through frames sequentially
			sprite.frame = (sprite.frame + 1) % 20

		# Check if roll is complete
		if spin_timer >= total_roll_duration:
			_finish_roll()


## Roll the dice and get a result from 1 to 20
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

	# Start from a random frame
	if sprite:
		sprite.frame = randi_range(0, 19)

	dice_roll_started.emit()
	print("Dice is rolling...")


## Finish the roll and display the result
func _finish_roll() -> void:
	is_rolling = false

	# Reset sprite position after shake
	if sprite:
		sprite.position = original_position

	# Read the actual result from the frame the dice landed on
	# Frame 0 = 1, Frame 1 = 2, ..., Frame 19 = 20
	var final_result = sprite.frame + 1

	print("========================================")
	print("DICE ROLL FINISHED")
	print("Landed on frame: ", sprite.frame, " = Dice value: ", final_result)
	print("========================================")

	dice_rolled.emit(final_result)
	dice_roll_finished.emit(final_result)


## Get the last rolled result
func get_result() -> int:
	if sprite:
		return sprite.frame + 1  # Frame 0 = 1, Frame 19 = 20
	return 0


## Check if dice is currently rolling
func is_dice_rolling() -> bool:
	return is_rolling


## Roll the dice and wait for the result (async)
func roll_and_wait() -> int:
	roll()
	await dice_roll_finished
	return get_result()


## Set the dice to show a specific face (for testing/cheating)
func set_face(face: int) -> void:
	if face < 1 or face > 20:
		push_error("Invalid dice face: ", face, " (must be 1-20)")
		return

	if sprite:
		sprite.frame = face - 1
		print("Dice face set to: ", face)
