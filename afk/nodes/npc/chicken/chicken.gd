extends NPC
class_name Chicken

## Chicken NPC - Passive Animal Enemy
## A harmless chicken that can only idle and show hurt reactions

## Emitted when the chicken is clicked
signal chicken_clicked

## NPC Registry Data - Decentralized configuration
const NPC_TYPE_ID: String = "chicken"
const NPC_CATEGORY: String = "monster"
const AI_PROFILE: Dictionary = {
	"idle_weight": 70,      # Chickens prefer to stay idle
	"walk_weight": 30,
	"state_change_min": 2.0,  # Faster state changes
	"state_change_max": 5.0,
	"movement_speed": 0.6   # Slower movement (it's a chicken!)
}

## Stats are now managed by Rust NPCDataWarehouse
## Query via NPCDataWarehouse.get_npc_stats_dict(ulid)


func _init() -> void:
	# Set chicken-specific properties
	walk_speed = 30.0

	# Set state flags: PASSIVE faction (static, never changes)
	static_state = NPCManager.NPCStaticState.PASSIVE
	# Behavioral state (dynamic, changes during gameplay)
	current_state = NPCManager.NPCState.IDLE

	# Override state-to-animation mapping (chickens use idle for walking)
	state_to_animation = {
		NPCManager.NPCState.IDLE: "idle",
		NPCManager.NPCState.WALKING: "idle",  # Chickens use idle animation for walking
		NPCManager.NPCState.DAMAGED: "hurt",
		NPCManager.NPCState.ATTACKING: "idle",
		NPCManager.NPCState.DEAD: "dead"
	}


## Override click handler to emit chicken-specific signal
func _on_input_manager_clicked() -> void:
	chicken_clicked.emit()
