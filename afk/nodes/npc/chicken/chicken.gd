extends CharacterBody2D
class_name Chicken

## Chicken NPC - Passive Animal Enemy
## A harmless chicken that can only idle and show hurt reactions

## Emitted when the chicken is clicked
signal chicken_clicked

## Chicken's current state
@export_enum("Idle", "Walking", "Hurt") var current_state: String = "Idle":
	set(value):
		if current_state != value:
			current_state = value
			_update_animation()

## Movement speed when walking
@export var walk_speed: float = 30.0

## NPC Stats reference (assigned by NPCManager)
var stats: NPCStats = null

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


func _ready() -> void:
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
	# Simple movement for chickens
	if current_state == "Walking" and not _is_hurt:
		position += _move_direction * walk_speed * delta


func _update_animation() -> void:
	if not animated_sprite:
		return

	match current_state:
		"Idle":
			animated_sprite.play("idle")
		"Walking":
			animated_sprite.play("idle")  # Chickens use idle animation for walking
		"Hurt":
			animated_sprite.play("hurt")


func _on_state_timer_timeout() -> void:
	# Randomly change state for AFK behavior (only if not hurt)
	if not _is_hurt:
		_random_state_change()


func _random_state_change() -> void:
	var states = ["Idle", "Walking"]
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
			if current_state == "Walking":
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

	# Show hurt animation
	_is_hurt = true
	current_state = "Hurt"

	# Return to idle after hurt animation
	await get_tree().create_timer(0.5).timeout
	_is_hurt = false
	current_state = "Idle"


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
