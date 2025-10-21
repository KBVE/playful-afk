extends CharacterBody2D
class_name Archer

## Archer NPC
## Manages the archer's animations, states, and behaviors

## Emitted when the archer is clicked
signal archer_clicked

## Archer's current state
@export_enum("Idle", "Walking", "Attacking", "Hurt", "Dead") var current_state: String = "Idle":
	set(value):
		if current_state != value:
			current_state = value
			_update_animation()

## Movement speed when walking
@export var walk_speed: float = 60.0

## Archer's stats
@export_group("Stats")
@export var health: float = 80.0:
	set(value):
		health = clamp(value, 0.0, 100.0)

@export var agility: float = 70.0:
	set(value):
		agility = clamp(value, 0.0, 100.0)

@export var attack_range: float = 200.0:
	set(value):
		attack_range = clamp(value, 50.0, 500.0)

@export var level: int = 1

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer

# Controller reference
var controller: ArcherController

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_player_controlled: bool = false


func _ready() -> void:
	# Initialize controller
	controller = ArcherController.new(self)
	add_child(controller)

	# Set up state timer for automatic state changes
	if state_timer:
		state_timer.timeout.connect(_on_state_timer_timeout)
		state_timer.start()

	# Register with InputManager for click detection
	# Wait a frame to ensure InputManager is ready
	await get_tree().process_frame
	if InputManager:
		InputManager.register_interactive_object(self, 80.0)  # 80 pixel click radius
		print("Archer registered with InputManager")

	# Initialize animation
	_update_animation()

	print("Archer initialized - Current state: %s" % current_state)


func _process(delta: float) -> void:
	# Update controller movement
	if controller:
		controller.update_movement(delta)


func _physics_process(delta: float) -> void:
	# Physics disabled for archer - movement handled by controller
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
	var weights = [70, 30]  # Percentage chance (archer prefers idle more)

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
	var previous_state = current_state
	health -= amount

	# Play hurt animation
	current_state = "Hurt"
	await get_tree().create_timer(0.5).timeout

	# Check if dead
	if health <= 0:
		current_state = "Dead"
	else:
		current_state = previous_state


## Set archer to manual control mode
func set_player_controlled(controlled: bool) -> void:
	_is_player_controlled = controlled
	# Always stop the state timer - the controller handles movement
	if state_timer:
		state_timer.stop()


## Called by InputManager when this archer is clicked
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("ARCHER CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	archer_clicked.emit()


## Called by InputManager when mouse enters this archer
func _on_input_manager_hover_enter() -> void:
	print("Mouse ENTERED archer at position: ", global_position)
	# Highlight archer when hovered
	if animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)


## Called by InputManager when mouse exits this archer
func _on_input_manager_hover_exit() -> void:
	print("Mouse EXITED archer at position: ", global_position)
	# Remove highlight
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
