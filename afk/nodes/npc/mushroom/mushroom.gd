extends Monster
class_name Mushroom

## Mushroom NPC - Aggressive Enemy
## An enemy mushroom that can attack allies

## Emitted when the mushroom is clicked
signal mushroom_clicked

## Emitted when the mushroom dies
signal mushroom_died


func _init() -> void:
	# Set mushroom-specific properties
	walk_speed = 25.0  # Slightly slower than chicken
	combat_type = NPCManager.CombatType.MELEE  # Melee attacker

	# Set monster types
	monster_types = [
		NPCManager.MonsterType.AGGRESSIVE
	]

	# State-to-animation mapping (mushroom has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "die"
	}


func _on_ready_complete() -> void:
	print("Mushroom initialized - Current state: %s" % current_state)


func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 20.0)  # 20 pixel click radius
		print("Mushroom registered with InputManager")


## Override random state change to make mushrooms more aggressive (walk more often)
func _random_state_change() -> void:
	# 50% chance to idle, 50% chance to walk (mushrooms are more active)
	var should_walk = (randi() % 10) >= 5  # 5 out of 10 numbers (5,6,7,8,9) = 50%
	current_state = NPCManager.NPCState.WALKING if should_walk else NPCManager.NPCState.IDLE

	# Set random direction if walking
	if should_walk:
		_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	else:
		_move_direction = Vector2.ZERO

	# Randomize next state change time (shorter intervals for mushrooms)
	state_timer.wait_time = randf_range(1.5, 4.0)


## Override damage behavior - mushrooms don't flee, they fight back
func _on_take_damage(amount: float) -> void:
	# Mushrooms are aggressive - they don't flee when hurt
	# The hurt animation will play via the base Monster class
	pass


## Override click handler to emit mushroom-specific signal
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("MUSHROOM CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	mushroom_clicked.emit()


## Override monster_died to also emit mushroom_died
func take_damage(amount: float) -> void:
	# Call parent implementation
	super.take_damage(amount)

	# Check if we died and emit mushroom-specific signal
	if stats and stats.hp <= 0:
		mushroom_died.emit()
