extends BaseStructure
class_name CityTower

## City Tower Structure
## A towering structure that watches over the city from the sky

func _ready() -> void:
	# Set structure-specific properties
	structure_name = "City Tower"
	structure_description = "A magnificent tower reaching into the sky.\nProvides defense, serves as a town hub,\nand appears in the starting scene.\n\n(More features coming soon...)"

	# Set structure metadata - Sky level with TOWN | DEFENSE | SPAWN
	structure_level = StructureLevel.SKY
	structure_types = StructureType.TOWN | StructureType.DEFENSE | StructureType.SPAWN

	# Call parent _ready to initialize common functionality
	super._ready()
