extends Monster
class_name Goblin

## Goblin NPC - Aggressive Enemy
## A hostile goblin that attacks allies

## Emitted when the goblin is clicked
signal goblin_clicked

## Emitted when the goblin dies
signal goblin_died


func _init() -> void:
	# Set goblin-specific properties
	walk_speed = 30.0  # Slightly faster than mushroom
	combat_type = NPCManager.CombatType.MELEE  # Melee attacker

	# Set monster types
	monster_types = [
		NPCManager.MonsterType.AGGRESSIVE
	]

	# State-to-animation mapping (goblin has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "death"
	}


func _on_ready_complete() -> void:
	# Stop the state timer for aggressive monsters - they're controlled by NPCManager AI
	if state_timer:
		state_timer.stop()


func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 20.0)  # 20 pixel click radius


## Override random state change - disabled for aggressive monsters (controlled by NPCManager)
func _random_state_change() -> void:
	# AGGRESSIVE monsters are controlled by NPCManager's roaming AI
	# This prevents conflicts with bounds-safe movement system
	pass


## Override damage behavior - goblins don't flee, they fight back
func _on_take_damage(amount: float) -> void:
	# Goblins are aggressive - they don't flee when hurt
	# The hurt animation will play via the base Monster class
	pass


## Override click handler to emit goblin-specific signal
func _on_input_manager_clicked() -> void:
	goblin_clicked.emit()


## Override monster_died to also emit goblin_died
func take_damage(amount: float) -> void:
	# Call parent implementation
	super.take_damage(amount)

	# Check if we died and emit goblin-specific signal
	if stats and stats.hp <= 0:
		goblin_died.emit()
