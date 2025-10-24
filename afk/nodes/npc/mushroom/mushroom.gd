extends NPC
class_name Mushroom

## Mushroom NPC - Aggressive Enemy
## An enemy mushroom that can attack allies

## Emitted when the mushroom is clicked
signal mushroom_clicked

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

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)

func _init() -> void:
	# Set mushroom-specific properties
	walk_speed = 25.0  # Slightly slower than chicken

	# Set state flags: MELEE combat type + MONSTER faction (static, never changes)
	static_state = NPCManager.NPCStaticState.MELEE | NPCManager.NPCStaticState.MONSTER
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

	# State-to-animation mapping (mushroom has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "die"
	}


## Override click handler to emit mushroom-specific signal
func _on_input_manager_clicked() -> void:
	mushroom_clicked.emit()
