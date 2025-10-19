extends Control
class_name RedForestSimple

## Simple layered background using TextureRect nodes
## No SubViewport complexity - just layers that scroll at different speeds

@export var scroll_speed_layer1: float = 0.2
@export var scroll_speed_layer2: float = 0.5
@export var scroll_speed_layer3: float = 0.8

@onready var layer1: TextureRect = $Layer1
@onready var layer2: TextureRect = $Layer2
@onready var layer3: TextureRect = $Layer3

var scroll_offset: float = 0.0


func _ready() -> void:
	print("RedForestSimple initialized")


## Scroll all layers based on an offset
func scroll_to(offset: float) -> void:
	scroll_offset = offset

	if layer1:
		layer1.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer1)
	if layer2:
		layer2.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer2)
	if layer3:
		layer3.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer3)


## Reset scroll
func reset() -> void:
	scroll_to(0.0)
