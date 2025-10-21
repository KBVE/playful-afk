extends NPC
class_name Archer

## Archer NPC - Ranged Fighter
## Extends base NPC class with archer-specific behavior

## Emitted when the archer is clicked (archer-specific signal)
signal archer_clicked


func _ready() -> void:
	# Set archer-specific properties
	walk_speed = 60.0
	max_speed = 100.0  # Slightly slower than warrior
	faction = NPCManager.Faction.ALLY
	combat_type = NPCManager.CombatType.RANGED

	# Call parent _ready
	super._ready()


## Override ready complete for archer-specific initialization
func _on_ready_complete() -> void:
	print("Archer initialized - Current state: %s" % current_state)


## Override click handler to emit archer-specific signal
func _on_input_manager_clicked() -> void:
	print("========================================")
	print("ARCHER CLICKED!")
	print("Position: ", global_position)
	print("========================================")
	archer_clicked.emit()
