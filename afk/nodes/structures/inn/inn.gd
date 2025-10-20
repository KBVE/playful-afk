extends BaseStructure
class_name Inn

func _ready() -> void:
	structure_name = "Inn"
	structure_description = "A cozy inn where travelers rest.\nProvides comfort and serves as a town hub.\nAppears at the start of your journey.\n\n(More features coming soon...)"

	structure_level = StructureLevel.ELEVATED
	structure_types = StructureType.TOWN | StructureType.SPAWN

	super._ready()
