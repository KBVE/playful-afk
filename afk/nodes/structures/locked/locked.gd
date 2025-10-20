extends BaseStructure
class_name LockedStructure

func _ready() -> void:
	structure_name = "Locked"
	structure_description = "This slot is locked.\nUnlock it to build here.\n\n(Coming soon...)"

	structure_level = StructureLevel.GROUND  # Will be set per instance
	structure_types = StructureType.NONE  # Not a spawn structure

	# Set low opacity for locked structures
	modulate.a = 0.35

	# Minimal hover effects for locked structures
	distance_opacity = 0.35
	near_opacity = 0.45

	super._ready()
