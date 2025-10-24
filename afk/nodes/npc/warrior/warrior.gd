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

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)

func _ready() -> void:
	# Set static/immutable properties FIRST (combat type + faction)
	# These NEVER change during gameplay
	static_state = NPCManager.NPCStaticState.MELEE | NPCManager.NPCStaticState.ALLY

	# Set initial behavioral state (just IDLE - no combat type/faction needed)
	current_state = NPCManager.NPCState.IDLE

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
