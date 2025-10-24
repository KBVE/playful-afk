extends NPC
class_name Eyebeast

## Eyebeast NPC - Aggressive Flying Enemy
## A hostile flying eyebeast that attacks allies

## Emitted when the eyebeast is clicked
signal eyebeast_clicked

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

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)


func _init() -> void:
	# Set eyebeast-specific properties
	walk_speed = 35.0  # Faster than goblin (flies)

	# Set state flags: MELEE combat type + MONSTER faction
	# Set state flags: MELEE combat type + MONSTER faction (static, never changes)
	# TODO: Change to RANGED when ranged monster attacks are implemented
	static_state = NPCManager.NPCStaticState.MELEE | NPCManager.NPCStaticState.MONSTER
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

	# State-to-animation mapping (eyebeast has all 5 animations)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "walk",
		NPCManager.NPCState.ATTACKING: "attack",
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.DEAD: "death"
	}


## Override click handler to emit eyebeast-specific signal
func _on_input_manager_clicked() -> void:
	eyebeast_clicked.emit()
