extends NPC
class_name Goblin

## Goblin NPC - Aggressive Enemy
## A hostile goblin that attacks allies

## Emitted when the goblin is clicked
signal goblin_clicked

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

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)


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


## Override click handler to emit goblin-specific signal
func _on_input_manager_clicked() -> void:
	goblin_clicked.emit()
