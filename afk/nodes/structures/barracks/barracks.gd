extends BaseStructure
class_name Barracks

func _ready() -> void:
	structure_name = "Barracks"
	structure_description = "Military training grounds for your forces.\nTrain soldiers and strengthen your defenses.\nA key defensive structure for your kingdom.\n\n(More features coming soon...)"

	structure_level = StructureLevel.ELEVATED
	structure_types = StructureType.DEFENSE | StructureType.SPAWN

	super._ready()
