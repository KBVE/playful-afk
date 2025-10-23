extends Monster
class_name Goblin

## Goblin NPC - Aggressive Enemy
## A hostile goblin that attacks allies

## Emitted when the goblin is clicked
signal goblin_clicked

## Emitted when the goblin dies
signal goblin_died

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "goblin"
const NPC_CATEGORY: String = "monster"
const AI_PROFILE: Dictionary = {
	"idle_weight": 40,      # Goblins are aggressive
	"walk_weight": 60,      # Move around more than mushrooms
	"state_change_min": 1.0,  # Very quick state changes
	"state_change_max": 3.0,
	"movement_speed": 0.8   # Faster than mushrooms
}

## Create stats for this NPC type
static func create_stats() -> NPCStats:
	return NPCStats.new(
		100.0,  # HP (medium - glass cannon)
		0.0,    # Mana (goblins don't use mana)
		80.0,   # Energy (high - very active)
		100.0,  # Hunger
		12.0,   # Attack (high melee damage - hits harder than mushrooms)
		5.0,    # Defense (low - fragile)
		NPCStats.Emotion.NEUTRAL,
		NPC_TYPE_ID
	)


func _init() -> void:
	# Set goblin-specific properties
	walk_speed = 30.0  # Slightly faster than mushroom

	# Set state flags: MELEE combat type + MONSTER faction (static, never changes)
	static_state = NPCManager.NPCStaticState.MELEE | NPCManager.NPCStaticState.MONSTER
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

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


## Override take_damage to also emit goblin_died
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Call parent implementation
	super.take_damage(amount, attacker)

	# Check if we died and emit goblin-specific signal
	if stats and stats.hp <= 0:
		goblin_died.emit()
