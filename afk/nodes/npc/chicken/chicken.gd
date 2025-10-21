extends Monster
class_name Chicken

## Chicken NPC - Passive Animal Enemy
## A harmless chicken that can only idle and show hurt reactions

## Emitted when the chicken is clicked
signal chicken_clicked

## Emitted when the chicken dies
signal chicken_died


func _init() -> void:
	# Set chicken-specific properties
	walk_speed = 30.0
	combat_type = NPCManager.CombatType.NONE  # Passive, doesn't attack

	# Set monster types
	monster_types = [
		NPCManager.MonsterType.ANIMAL,
		NPCManager.MonsterType.PASSIVE
	]

	# Override state-to-animation mapping (chickens use idle for walking)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "idle",  # Chickens use idle animation for walking
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "dead"
	}


func _on_ready_complete() -> void:
	print("Chicken initialized - Current state: %s" % current_state)


func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 20.0)  # 40 pixel click radius (smaller than warrior)
		print("Chicken registered with InputManager")


## Override random state change to use chicken-specific weights
func _random_state_change() -> void:
	# 70% chance to idle, 30% chance to walk (using modulo for fun!)
	var should_walk = (randi() % 10) >= 7  # 3 out of 10 numbers (7,8,9) = 30%
	current_state = NPCManager.NPCState.WALKING if should_walk else NPCManager.NPCState.IDLE

	# Set random direction if walking
	if should_walk:
		_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	else:
		_move_direction = Vector2.ZERO

	# Randomize next state change time
	state_timer.wait_time = randf_range(2.0, 5.0)


## Override damage behavior - chickens panic and flee when hit
func _on_take_damage(amount: float) -> void:
	# Panic behavior: Run away in random direction after getting hit
	_panic_flee()


## Panic flee behavior - chicken runs away after taking damage
func _panic_flee() -> void:
	# Pick a random direction to flee (prefer moving away from center of action)
	var viewport_size = get_viewport_rect().size
	var screen_center = Vector2(viewport_size.x / 2, viewport_size.y / 2)
	var away_from_center = (position - screen_center).normalized()

	# Add randomness to the flee direction
	var random_angle = randf_range(-PI/3, PI/3)  # ±60 degrees variation
	_move_direction = away_from_center.rotated(random_angle).normalized()

	# Enter walking state to start fleeing
	current_state = NPCManager.NPCState.WALKING

	# Flee for a short duration (2-3 seconds)
	var flee_duration = randf_range(2.0, 3.0)
	state_timer.wait_time = flee_duration
	state_timer.start()

	print("Chicken panicking and fleeing!")


## Override click handler to emit chicken-specific signal
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("CHICKEN CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	chicken_clicked.emit()


## Override monster_died to also emit chicken_died
func take_damage(amount: float) -> void:
	# Call parent implementation
	super.take_damage(amount)

	# Check if we died and emit chicken-specific signal
	if stats and stats.hp <= 0:
		chicken_died.emit()
