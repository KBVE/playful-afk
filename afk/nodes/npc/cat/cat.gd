extends CharacterBody2D
class_name Cat

## Cat NPC - Virtual Pet
## Manages the cat's animations, states, and behaviors for the AFK virtual pet game

## Cat's current state
@export_enum("Idle", "Walking", "Sleeping", "Eating", "Playing", "Happy", "Sad") var current_state: String = "Idle":
	set(value):
		if current_state != value:
			current_state = value
			_update_animation()
			EventManager.pet_state_changed.emit(value)

## Movement speed when walking
@export var walk_speed: float = 50.0

## Cat's stats
@export_group("Stats")
@export var hunger: float = 100.0:
	set(value):
		hunger = clamp(value, 0.0, 100.0)
		EventManager.pet_hunger_changed.emit(hunger)

@export var happiness: float = 100.0:
	set(value):
		happiness = clamp(value, 0.0, 100.0)
		EventManager.pet_happiness_changed.emit(happiness)

@export var health: float = 100.0:
	set(value):
		health = clamp(value, 0.0, 100.0)
		EventManager.pet_health_changed.emit(health)

@export var level: int = 1:
	set(value):
		if level != value and value > level:
			EventManager.pet_leveled_up.emit(value)
		level = value

@export var experience: int = 0:
	set(value):
		experience = value
		EventManager.pet_xp_changed.emit(experience, experience_to_next_level)

@export var experience_to_next_level: int = 100

## Cat's faction (ALLY - never targeted by allies)
var faction: int = 0  # NPCManager.Faction.ALLY

## Cat's combat type (NONE - doesn't fight)
var combat_type: int = 0  # NPCManager.CombatType.NONE

## Cat is a friendly pet, not a monster (should never be targeted in combat)
var is_friendly: bool = true

## Signal emitted when cat sees enemies and calls for help
signal call_for_help(enemy: Node2D)

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_timer: Timer = $StateTimer

# Controller reference
var controller: CatController

# Internal state
var _move_direction: Vector2 = Vector2.ZERO
var _is_player_controlled: bool = false

# Danger detection
var _danger_check_timer: float = 0.0
const DANGER_CHECK_INTERVAL: float = 2.0  # Check for enemies every 2 seconds
const DANGER_RANGE: float = 600.0  # Range at which cat detects danger (covers most of screen)


func _ready() -> void:
	# Initialize controller
	controller = CatController.new(self)
	add_child(controller)

	# Set up state timer for automatic state changes
	if state_timer:
		state_timer.timeout.connect(_on_state_timer_timeout)
		state_timer.start()

	# Initialize animation
	_update_animation()

	# Connect to EventManager for feeding
	EventManager.pet_fed.connect(_on_pet_fed)


func _process(delta: float) -> void:

	# Check for nearby enemies periodically
	_danger_check_timer += delta
	if _danger_check_timer >= DANGER_CHECK_INTERVAL:
		_danger_check_timer = 0.0
		_check_for_danger()


func _physics_process(delta: float) -> void:
	# Handle movement based on state (only if not controlled by main scene)
	if current_state == "Walking" and not _is_player_controlled:
		if controller:
			controller.move_cat(_move_direction, true)
		move_and_slide()


func _update_animation() -> void:
	if not controller:
		return

	# Use controller to play state animations (supports combos)
	controller.play_state(current_state.to_lower())


func _on_state_timer_timeout() -> void:
	# Randomly change state for AFK behavior
	if not _is_player_controlled:
		_random_state_change()


func _random_state_change() -> void:
	var states = ["Idle", "Walking", "Sleeping"]
	var weights = [50, 30, 20]  # Percentage chance

	# Add happy/sad states based on happiness level
	if happiness > 70:
		states.append("Happy")
		weights.append(20)
	elif happiness < 30:
		states.append("Sad")
		weights.append(20)

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


## Feed the cat
func feed(food_item: Dictionary) -> void:
	var nutrition = food_item.get("nutrition", 10)
	hunger = min(hunger + nutrition, 100.0)
	happiness = min(happiness + nutrition * 0.5, 100.0)

	# Play eating animation temporarily
	var previous_state = current_state
	current_state = "Eating"

	# Return to previous state after eating
	await get_tree().create_timer(2.0).timeout
	current_state = previous_state

	EventManager.pet_fed.emit(food_item)


## Play with the cat
func play() -> void:
	happiness = min(happiness + 20.0, 100.0)
	hunger = max(hunger - 5.0, 0.0)

	var previous_state = current_state
	current_state = "Playing"

	await get_tree().create_timer(3.0).timeout
	current_state = previous_state


## Give the cat experience
func gain_experience(amount: int) -> void:
	experience += amount

	# Check for level up
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		experience_to_next_level = int(experience_to_next_level * 1.5)


## Set cat to manual control mode
func set_player_controlled(controlled: bool) -> void:
	_is_player_controlled = controlled
	if controlled:
		state_timer.stop()
	else:
		state_timer.start()


func _on_pet_fed(food_item: Dictionary) -> void:
	# React to being fed (from EventManager)
	pass


## Check for nearby enemies and call for help if found
func _check_for_danger() -> void:
	# RUST COMBAT: CombatManager removed - danger detection disabled for now
	# TODO: Implement danger detection in Rust or via NPCManager
	pass
