extends Monster
class_name Mushroom

## Mushroom NPC - Aggressive Enemy
## An enemy mushroom that can attack allies

## Emitted when the mushroom is clicked
signal mushroom_clicked

## Emitted when the mushroom dies
signal mushroom_died

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "mushroom"
const NPC_CATEGORY: String = "monster"
const AI_PROFILE: Dictionary = {
	"idle_weight": 50,      # Mushrooms are more active
	"walk_weight": 50,
	"state_change_min": 1.5,  # Quick state changes
	"state_change_max": 4.0,
	"movement_speed": 0.7   # Medium speed
}

## Create stats for this NPC type
static func create_stats() -> NPCStats:
	return NPCStats.new(
		120.0,  # HP (high - needs to survive against multiple enemies)
		0.0,    # Mana (mushrooms don't use mana)
		75.0,   # Energy
		100.0,  # Hunger
		8.0,    # Attack (melee damage)
		8.0,    # Defense (medium)
		NPCStats.Emotion.NEUTRAL,
		NPC_TYPE_ID
	)


func _init() -> void:
	# Set mushroom-specific properties
	walk_speed = 25.0  # Slightly slower than chicken

	# Set state flags: MELEE combat type + MONSTER faction
	# Mushrooms are MELEE MONSTER (aggressive, attacks allies)
	current_state = NPCManager.NPCState.IDLE | NPCManager.NPCState.MELEE | NPCManager.NPCState.MONSTER

	# State-to-animation mapping (mushroom has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "die"
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


## Override damage behavior - mushrooms don't flee, they fight back
func _on_take_damage(amount: float) -> void:
	# Mushrooms are aggressive - they don't flee when hurt
	# The hurt animation will play via the base Monster class
	pass


## Override click handler to emit mushroom-specific signal
func _on_input_manager_clicked() -> void:
	mushroom_clicked.emit()


## Override take_damage to also emit mushroom_died
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Call parent implementation
	super.take_damage(amount, attacker)

	# Check if we died and emit mushroom-specific signal
	if stats and stats.hp <= 0:
		mushroom_died.emit()
