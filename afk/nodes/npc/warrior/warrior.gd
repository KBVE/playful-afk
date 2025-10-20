extends CharacterBody2D
class_name Warrior

## Warrior NPC
## Manages the warrior's animations, states, and behaviors

## Warrior's current state
@export_enum("Idle", "Walking", "Attacking") var current_state: String = "Idle":
	set(value):
		if current_state != value:
			current_state = value
			_update_animation()

## Movement speed when walking
@export var walk_speed: float = 50.0

## Warrior's stats
@export_group("Stats")
@export var health: float = 100.0:
	set(value):
		health = clamp(value, 0.0, 100.0)

@export var strength: float = 50.0:
	set(value):
		strength = clamp(value, 0.0, 100.0)

@export var defense: float = 50.0:
	set(value):
		defense = clamp(value, 0.0, 100.0)

@export var level: int = 1

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer

# Controller reference
var controller: WarriorController

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_player_controlled: bool = false


func _ready() -> void:
	# Initialize controller
	controller = WarriorController.new(self)
	add_child(controller)

	# Set up state timer for automatic state changes
	if state_timer:
		state_timer.timeout.connect(_on_state_timer_timeout)
		state_timer.start()

	# Initialize animation
	_update_animation()

	print("Warrior initialized - Current state: %s" % current_state)


func _physics_process(delta: float) -> void:
	# Physics disabled for warrior - movement handled by controller
	# No gravity or physics-based movement needed
	pass


func _update_animation() -> void:
	if not controller:
		return

	# Use controller to play state animations
	controller.play_state(current_state.to_lower())


func _on_state_timer_timeout() -> void:
	# Randomly change state for AFK behavior
	if not _is_player_controlled:
		_random_state_change()


func _random_state_change() -> void:
	var states = ["Idle", "Walking"]
	var weights = [60, 40]  # Percentage chance

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
			if current_state == "Walking":
				_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			else:
				_move_direction = Vector2.ZERO

			# Randomize next state change time
			state_timer.wait_time = randf_range(3.0, 8.0)
			break


## Attack action
func attack() -> void:
	var previous_state = current_state
	current_state = "Attacking"

	await get_tree().create_timer(1.0).timeout
	current_state = previous_state


## Take damage
func take_damage(amount: float) -> void:
	var actual_damage = max(0, amount - (defense * 0.5))
	health -= actual_damage

	# Could add hurt reaction here in future


## Set warrior to manual control mode
func set_player_controlled(controlled: bool) -> void:
	_is_player_controlled = controlled
	# Always stop the state timer - the controller handles movement
	if state_timer:
		state_timer.stop()
