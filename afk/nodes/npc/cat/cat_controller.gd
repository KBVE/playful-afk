extends Node
class_name CatController

## CatController - Animation and Movement Controller for Cat
## Handles animation sequencing, combos, and movement coordination
## Automatically syncs animations with cat states and movement

## Reference to the cat being controlled
var cat: Cat

## Animation sprite reference
var animated_sprite: AnimatedSprite2D

## Animation mapping - maps state names to animation sequences (can be combos)
var animation_sequences: Dictionary = {
	# State: [animation_row_1, animation_row_2, ...] - plays in sequence
	"idle": ["row1"],                    # Simple idle loop
	"walking": ["row2"],                 # Walking loop
	"sleeping": ["row3", "row4"],        # Combo: Get into bed → Sleep loop
	"waking_up": ["row5"],               # Wake up animation
	"eating": ["row6"],                  # Eating animation
	"playing": ["row7", "row8"],         # Combo: Start playing → Playing loop
	"happy": ["row9"],                   # Happy emotion
	"sad": ["row10"],                    # Sad emotion
}

## Current animation sequence being played
var current_sequence: Array = []
var current_sequence_index: int = 0
var is_playing_sequence: bool = false

## Movement settings
var move_speed: float = 50.0
var move_direction: Vector2 = Vector2.ZERO


func _init(cat_instance: Cat = null) -> void:
	if cat_instance:
		set_cat(cat_instance)


func _ready() -> void:
	if cat and cat.has_node("AnimatedSprite2D"):
		animated_sprite = cat.get_node("AnimatedSprite2D")

		# Connect to animation finished signal
		if animated_sprite:
			animated_sprite.animation_finished.connect(_on_animation_finished)


## Set the cat this controller manages
func set_cat(cat_instance: Cat) -> void:
	cat = cat_instance
	if cat:
		move_speed = cat.walk_speed


## Play a state animation (can be a combo sequence)
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


## Update an existing animation sequence
func update_animation_sequence(state_name: String, animation_rows: Array) -> void:
	if animation_sequences.has(state_name):
		animation_sequences[state_name] = animation_rows
		print("Updated animation sequence '%s': %s" % [state_name, animation_rows])
	else:
		push_warning("Cannot update '%s' - sequence doesn't exist. Use add_animation_sequence() instead." % state_name)


## Get the current animation sequence for a state
func get_animation_sequence(state_name: String) -> Array:
	return animation_sequences.get(state_name, [])


## Move the cat in a direction with matching animation
func move_cat(direction: Vector2, use_walking_animation: bool = true) -> void:
	if not cat:
		return

	move_direction = direction.normalized()
	cat.velocity = move_direction * move_speed

	# Flip sprite based on movement direction
	if animated_sprite and move_direction.x != 0:
		animated_sprite.flip_h = move_direction.x < 0

	# Auto-play walking animation if moving
	if use_walking_animation and move_direction.length() > 0:
		if not is_playing_sequence or current_sequence != animation_sequences.get("walking", []):
			play_state("walking")


## Stop cat movement
func stop_movement() -> void:
	if cat:
		cat.velocity = Vector2.ZERO
		move_direction = Vector2.ZERO


## Handle movement input (for manual control)
func handle_movement_input(input_vector: Vector2) -> void:
	if input_vector.length() > 0:
		move_cat(input_vector, true)
	else:
		stop_movement()
		# Return to idle if not in a sequence
		if not is_playing_sequence:
			play_state("idle")


## Called when an animation finishes
func _on_animation_finished() -> void:
	if not is_playing_sequence:
		return

	# Check if this animation should loop (last in sequence with 1 item, or explicitly looping states)
	var current_state = cat.current_state.to_lower() if cat else ""
	var is_looping_state = current_state in ["idle", "walking", "sleeping", "happy", "sad"]

	# Move to next animation in sequence
	current_sequence_index += 1

	if current_sequence_index >= current_sequence.size():
		# Sequence finished
		if is_looping_state and current_sequence.size() > 1:
			# For multi-animation sequences in looping states, loop the last animation
			current_sequence_index = current_sequence.size() - 1
			_play_next_in_sequence()
		elif is_looping_state:
			# Single animation loop - restart sequence
			current_sequence_index = 0
			_play_next_in_sequence()
		else:
			# Non-looping sequence finished
			is_playing_sequence = false
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


## List all available animation sequences
func list_animation_sequences() -> void:
	print("=== Available Animation Sequences ===")
	for state in animation_sequences.keys():
		print("  %s: %s" % [state, animation_sequences[state]])
