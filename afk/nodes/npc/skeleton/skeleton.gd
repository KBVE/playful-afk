extends NPC
class_name Skeleton

## Skeleton NPC - Aggressive Undead Enemy
## A hostile skeleton warrior that attacks allies

## Emitted when the skeleton is clicked
signal skeleton_clicked

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "skeleton"
const NPC_CATEGORY: String = "monster"
const AI_PROFILE: Dictionary = {
	"idle_weight": 35,      # Skeletons are aggressive
	"walk_weight": 65,      # Move around steadily
	"state_change_min": 1.2,  # Medium state changes
	"state_change_max": 3.5,
	"movement_speed": 0.75  # Medium speed
}

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)


func _init() -> void:
	# Set skeleton-specific properties
	walk_speed = 28.0  # Medium speed (between mushroom and goblin)

	# Set state flags: MELEE combat type + MONSTER faction (static, never changes)
	static_state = NPCManager.NPCStaticState.MELEE | NPCManager.NPCStaticState.MONSTER
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

	# State-to-animation mapping (skeleton has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "death"
	}


## Override click handler to emit skeleton-specific signal
func _on_input_manager_clicked() -> void:
	skeleton_clicked.emit()
