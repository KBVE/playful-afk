extends BaseStructure
class_name Castle

## Castle Structure
## A majestic castle where you can manage kingdom resources and upgrades

func _ready() -> void:
	# Set structure-specific properties
	structure_name = "Castle"
	structure_description = "A grand castle standing tall.\nManage your kingdom's resources\nand unlock powerful upgrades.\n\n(More features coming soon...)"

	# Set structure metadata
	structure_level = StructureLevel.GROUND
	structure_types = StructureType.CASTLE | StructureType.DEFENSE

	# Call parent _ready to initialize common functionality
	super._ready()
