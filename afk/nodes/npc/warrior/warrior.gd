extends NPC
class_name Warrior

## Warrior NPC - Melee Fighter
## Extends base NPC class with warrior-specific behavior

## Emitted when the warrior is clicked (warrior-specific signal)
signal warrior_clicked

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "warrior"
const NPC_CATEGORY: String = "melee"
const AI_PROFILE: Dictionary = {
	"idle_weight": 60,      # Prefers action over idle
	"walk_weight": 40,
	"state_change_min": 3.0,  # Min seconds between state changes
	"state_change_max": 8.0,  # Max seconds between state changes
	"movement_speed": 1.0     # Movement speed multiplier
}

## Emoji set for warriors
const EMOJIS: Array[String] = ["⚔️", "🛡️", "💪", "🔥", "⚡", "🎖️", "👊", "⭐"]

## Create stats for this NPC type
static func create_stats() -> NPCStats:
	return NPCStats.new(
		350.0,  # HP - BUFFED AGAIN (was 200.0, originally 100.0)
		50.0,   # Mana
		100.0,  # Energy
		100.0,  # Hunger
		15.0,   # Attack
		35.0,   # Defense - BUFFED AGAIN (was 20.0, originally 10.0)
		NPCStats.Emotion.NEUTRAL,
		NPC_TYPE_ID
	)


func _ready() -> void:
	# IMPORTANT: Set state flags FIRST, before parent _ready() which triggers AI registration
	# MELEE combat type + ALLY faction
	# Warriors are MELEE ALLY (fight for player, don't attack each other)
	var desired_state = NPCManager.NPCState.IDLE | NPCManager.NPCState.MELEE | NPCManager.NPCState.ALLY
	print("DEBUG Warrior _ready: Setting state from %d to %d" % [current_state, desired_state])
	current_state = desired_state
	print("DEBUG Warrior _ready: State is now %d" % current_state)

	# Set warrior-specific properties
	walk_speed = 50.0
	max_speed = 120.0  # Faster than archer
	acceleration_rate = 400.0
	deceleration_rate = 400.0
	attack_range = 60.0  # Melee range - can attack from close range

	# Call parent _ready (this triggers AI registration which reads current_state)
	super._ready()


## Override click handler to emit warrior-specific signal
func _on_input_manager_clicked() -> void:
	warrior_clicked.emit()
