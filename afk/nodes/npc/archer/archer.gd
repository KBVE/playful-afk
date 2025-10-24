extends NPC
class_name Archer

## Archer NPC - Ranged Fighter
## Extends base NPC class with archer-specific behavior

## Emitted when the archer is clicked (archer-specific signal)
signal archer_clicked

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "archer"
const NPC_CATEGORY: String = "ranged"
const AI_PROFILE: Dictionary = {
	"idle_weight": 70,      # Prefers idle (patient archer)
	"walk_weight": 30,
	"state_change_min": 3.0,
	"state_change_max": 8.0,
	"movement_speed": 0.8   # Slightly slower movement
}

## Emoji set for archers
const EMOJIS: Array[String] = ["🏹", "🎯", "👁️", "🌟", "🦅", "🍃", "💨", "🔭"]

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)


func _ready() -> void:
	# IMPORTANT: Set state flags FIRST, before parent _ready() which triggers AI registration
	# RANGED combat type + ALLY faction (static, never changes)
	static_state = NPCManager.NPCStaticState.RANGED | NPCManager.NPCStaticState.ALLY
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

	# Set archer-specific properties
	walk_speed = 60.0
	max_speed = 100.0  # Slightly slower than warrior
	attack_range = 150.0  # Optimal ranged distance for archers

	# Call parent _ready (this triggers AI registration which reads current_state)
	super._ready()


## Override click handler to emit archer-specific signal
func _on_input_manager_clicked() -> void:
	archer_clicked.emit()
