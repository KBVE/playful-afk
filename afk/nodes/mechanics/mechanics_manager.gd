extends Node

## MechanicsManager - Centralized management for game mechanics
## Handles reusable game mechanics like dice rolling, minigames, etc.
## Available globally as an autoload singleton

## Signals
signal dice_rolled(result: int)
signal mechanic_activated(mechanic_name: String)

## Mechanics references
var dice: Dice = null

## State management
var is_mechanic_active: bool = false
var active_mechanic: String = ""


func _ready() -> void:
	# Initialize dice
	var dice_scene = load("res://nodes/mechanics/dice/dice.tscn")
	dice = dice_scene.instantiate()
	add_child(dice)

	# Connect dice signals
	if dice:
		dice.dice_rolled.connect(_on_dice_rolled)
		dice.dice_roll_started.connect(_on_dice_roll_started)
		dice.dice_roll_finished.connect(_on_dice_roll_finished)

	print("MechanicsManager initialized with dice")


## Get a dice instance for use in UI
## Returns a new dice node that can be added to any scene
func get_dice_instance() -> Dice:
	var dice_scene = load("res://nodes/mechanics/dice/dice.tscn")
	return dice_scene.instantiate()


## Roll the global dice
func roll_dice() -> void:
	if dice and not dice.is_dice_rolling():
		dice.roll()
		mechanic_activated.emit("dice")


## Roll dice and wait for result (async)
func roll_dice_and_wait() -> int:
	if not dice:
		push_error("MechanicsManager: Dice not initialized!")
		return 0

	return await dice.roll_and_wait()


## Get the last dice roll result
func get_last_dice_result() -> int:
	if dice:
		return dice.get_result()
	return 0


## Check if dice is currently rolling
func is_dice_rolling() -> bool:
	if dice:
		return dice.is_dice_rolling()
	return false


## Dice signal callbacks
func _on_dice_rolled(result: int) -> void:
	dice_rolled.emit(result)
	print("MechanicsManager: Dice rolled - result: ", result)


func _on_dice_roll_started() -> void:
	is_mechanic_active = true
	active_mechanic = "dice"
	print("MechanicsManager: Dice roll started")


func _on_dice_roll_finished(result: int) -> void:
	is_mechanic_active = false
	active_mechanic = ""
	print("MechanicsManager: Dice roll finished - result: ", result)


## Future mechanics can be added here
## Example:
## func get_card_game_instance() -> CardGame:
##     var card_scene = load("res://nodes/mechanics/card_game/card_game.tscn")
##     return card_scene.instantiate()
