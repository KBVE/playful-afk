extends NPC
class_name Warrior

## Warrior NPC - Melee Fighter
## Extends base NPC class with warrior-specific behavior

## Emitted when the warrior is clicked (warrior-specific signal)
signal warrior_clicked


func _ready() -> void:
	# Set warrior-specific properties
	walk_speed = 50.0
	max_speed = 120.0  # Faster than archer
	acceleration_rate = 400.0
	deceleration_rate = 400.0
	faction = NPCManager.Faction.ALLY
	combat_type = NPCManager.CombatType.MELEE

	# Call parent _ready
	super._ready()


## Override ready complete for warrior-specific initialization
func _on_ready_complete() -> void:
	print("Warrior initialized - Current state: %s" % current_state)


## Override click handler to emit warrior-specific signal
func _on_input_manager_clicked() -> void:
	warrior_clicked.emit()
