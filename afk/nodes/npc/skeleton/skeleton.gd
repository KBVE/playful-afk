extends Monster
class_name Skeleton

## Skeleton NPC - Aggressive Undead Enemy
## A hostile skeleton warrior that attacks allies

## Emitted when the skeleton is clicked
signal skeleton_clicked

## Emitted when the skeleton dies
signal skeleton_died


func _init() -> void:
	# Set skeleton-specific properties
	walk_speed = 28.0  # Medium speed (between mushroom and goblin)
	combat_type = NPCManager.CombatType.MELEE  # Melee attacker

	# Set monster types
	monster_types = [
		NPCManager.MonsterType.AGGRESSIVE
	]

	# State-to-animation mapping (skeleton has all 5 animations)
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


## Override damage behavior - skeletons don't flee, they fight back
func _on_take_damage(amount: float) -> void:
	# Skeletons are aggressive - they don't flee when hurt
	# The hurt animation will play via the base Monster class
	pass


## Override click handler to emit skeleton-specific signal
func _on_input_manager_clicked() -> void:
	skeleton_clicked.emit()


## Override take_damage to also emit skeleton_died
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Call parent implementation
	super.take_damage(amount, attacker)

	# Check if we died and emit skeleton-specific signal
	if stats and stats.hp <= 0:
		skeleton_died.emit()
