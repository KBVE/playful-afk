extends Monster
class_name Chicken

## Chicken NPC - Passive Animal Enemy
## A harmless chicken that can only idle and show hurt reactions

## Emitted when the chicken is clicked
signal chicken_clicked

## Emitted when the chicken dies
signal chicken_died

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

## Create stats for this NPC type
static func create_stats() -> NPCStats:
	return NPCStats.new(
		1000.0, # HP (high for testing!)
		0.0,    # Mana (chickens don't use mana)
		50.0,   # Energy
		100.0,  # Hunger
		0.0,    # Attack (passive - can't attack)
		2.0,    # Defense (very low)
		NPCStats.Emotion.NEUTRAL,
		NPC_TYPE_ID
	)


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


func _on_ready_complete() -> void:
	pass


func _register_with_input_manager() -> void:
	if InputManager:
		InputManager.register_interactive_object(self, 20.0)  # 20 pixel click radius (smaller than warrior)


## Override random state change to use chicken-specific weights
func _random_state_change() -> void:
	# 70% chance to idle, 30% chance to walk (using modulo for fun!)
	var should_walk = (randi() % 10) >= 7  # 3 out of 10 numbers (7,8,9) = 30%
	current_state = NPCManager.NPCState.WALKING if should_walk else NPCManager.NPCState.IDLE

	# Set random direction if walking
	if should_walk:
		_move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	else:
		_move_direction = Vector2.ZERO

	# Randomize next state change time
	state_timer.wait_time = randf_range(2.0, 5.0)


## Override damage behavior - handled by NPCManager hurt state system
func _on_take_damage(amount: float) -> void:
	# Hurt state is already handled by Monster.take_damage() and NPCManager
	# No additional behavior needed
	pass


## Override click handler to emit chicken-specific signal
func _on_input_manager_clicked() -> void:
	chicken_clicked.emit()


## Override take_damage to also emit chicken_died
func take_damage(amount: float, attacker: Node2D = null) -> void:
	# Call parent implementation
	super.take_damage(amount, attacker)

	# Check if we died and emit chicken-specific signal
	if stats and stats.hp <= 0:
		chicken_died.emit()
