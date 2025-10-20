extends BaseStructure
class_name StoneHome

## Stone Home Structure
## A cozy stone dwelling for your pets and villagers

func _ready() -> void:
	# Set structure-specific properties
	structure_name = "Stone Home"
	structure_description = "A sturdy stone dwelling.\nProvides shelter and comfort\nfor your pets and villagers.\n\n(More features coming soon...)"

	# Call parent _ready to initialize common functionality
	super._ready()
