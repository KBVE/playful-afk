extends BaseStructure
class_name DragonDen

## Dragon Den Structure
## A mysterious den where dragons rest and protect the realm

func _ready() -> void:
	# Set structure-specific properties
	structure_name = "Dragon Den"
	structure_description = "A fearsome dragon's lair.\nProvides powerful defense\nand spawns at game start.\n\n(More features coming soon...)"

	# Set structure metadata - SPAWN + DEFENSE
	structure_level = StructureLevel.GROUND
	structure_types = StructureType.SPAWN | StructureType.DEFENSE

	# Call parent _ready to initialize common functionality
	super._ready()
