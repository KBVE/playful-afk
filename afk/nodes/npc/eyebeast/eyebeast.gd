extends Monster
class_name Eyebeast

## Eyebeast NPC - Aggressive Flying Enemy
## A hostile flying eyebeast that attacks allies

## Emitted when the eyebeast is clicked
signal eyebeast_clicked

## Emitted when the eyebeast dies
signal eyebeast_died


func _init() -> void:
	# Set eyebeast-specific properties
	walk_speed = 35.0  # Faster than goblin (flies)
	combat_type = NPCManager.CombatType.MELEE  # Melee attacker for now (TODO: add ranged support for monsters)

	# Set monster types
	monster_types = [
		NPCManager.MonsterType.AGGRESSIVE
	]

	# State-to-animation mapping (eyebeast has all 5 animations)
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


## Override damage behavior - eyebeasts don't flee, they fight back
func _on_take_damage(amount: float) -> void:
	# Eyebeasts are aggressive - they don't flee when hurt
	# The hurt animation will play via the base Monster class
	pass


## Override click handler to emit eyebeast-specific signal
func _on_input_manager_clicked() -> void:
	eyebeast_clicked.emit()


## Override take_damage to also emit eyebeast_died
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Call parent implementation
	super.take_damage(amount, attacker)

	# Check if we died and emit eyebeast-specific signal
	if stats and stats.hp <= 0:
		eyebeast_died.emit()
