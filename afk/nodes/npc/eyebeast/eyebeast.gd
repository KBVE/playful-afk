extends Monster
class_name Eyebeast

## Eyebeast NPC - Aggressive Flying Enemy
## A hostile flying eyebeast that attacks allies

## Emitted when the eyebeast is clicked
signal eyebeast_clicked

## Emitted when the eyebeast dies
signal eyebeast_died

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "eyebeast"
const NPC_CATEGORY: String = "monster"
const AI_PROFILE: Dictionary = {
	"idle_weight": 30,      # Eyebeasts are very aggressive
	"walk_weight": 70,      # Constantly moving (flying)
	"state_change_min": 0.8,  # Very quick state changes (agile flyer)
	"state_change_max": 2.5,
	"movement_speed": 0.9   # Fastest monster (flying)
}

## Create stats for this NPC type
static func create_stats() -> NPCStats:
	return NPCStats.new(
		80.0,   # HP (low - flying glass cannon)
		0.0,    # Mana (eyebeasts don't use mana)
		90.0,   # Energy (very high - constantly flying)
		100.0,  # Hunger
		15.0,   # Attack (very high ranged damage - eye beam)
		3.0,    # Defense (very low - extremely fragile)
		NPCStats.Emotion.NEUTRAL,
		NPC_TYPE_ID
	)


func _init() -> void:
	# Set eyebeast-specific properties
	walk_speed = 35.0  # Faster than goblin (flies)

	# Set state flags: MELEE combat type + MONSTER faction
	# Eyebeasts are MELEE MONSTER (aggressive flyers, melee attacks for now)
	# TODO: Change to RANGED when ranged monster attacks are implemented
	current_state = NPCManager.NPCState.IDLE | NPCManager.NPCState.MELEE | NPCManager.NPCState.MONSTER

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
