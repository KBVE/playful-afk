extends Control
class_name ForestIntroBackground

## Simple static background for the introduction scene
## Displays the windrise forest background filling the screen

@onready var background_layer: TextureRect = $BackgroundLayer


func _ready() -> void:
	print("ForestIntroBackground initialized")
