extends Control
class_name RollingHillsBackground

## Simple layered background using TextureRect nodes
## 4 layers with parallax scrolling for rolling hills environment

@export var scroll_speed_layer1: float = 0.15
@export var scroll_speed_layer2: float = 0.35
@export var scroll_speed_layer3: float = 0.6
@export var scroll_speed_layer4: float = 0.9

@onready var layer1: TextureRect = $Layer1
@onready var layer2: TextureRect = $Layer2
@onready var layer3: TextureRect = $Layer3
@onready var layer4: TextureRect = $Layer4
@onready var layer3_objects: Node2D = $Layer3Objects

var scroll_offset: float = 0.0
var initial_layer3_objects_position: float = 0.0


func _ready() -> void:
	# Store initial position for objects container
	if layer3_objects:
		initial_layer3_objects_position = layer3_objects.position.x

	# Auto-register all structures with StructureManager
	_register_structures()

	print("RollingHillsBackground initialized")


## Register all child structures with StructureManager for auto-positioning
func _register_structures() -> void:
	if not layer3_objects or not StructureManager:
		return

	# Get all structure children
	var structures = layer3_objects.get_children()

	print("RollingHillsBackground: Found ", structures.size(), " structures to register")

	# Register each structure with the manager
	for structure in structures:
		if structure is Node2D:
			StructureManager.register_structure(structure)
			# Scale all structures using StructureManager's scale setting
			var scale = StructureManager.structure_scale
			structure.scale = Vector2(scale, scale)


## Scroll all layers based on an offset
func scroll_to(offset: float) -> void:
	scroll_offset = offset

	if layer1 and layer1.material:
		layer1.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer1)
	if layer2 and layer2.material:
		layer2.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer2)
	if layer3 and layer3.material:
		layer3.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer3)
	if layer4 and layer4.material:
		layer4.material.set_shader_parameter("scroll_offset", scroll_offset * scroll_speed_layer4)

	# Also scroll objects in layer 3 at the same speed as layer 3
	if layer3_objects:
		layer3_objects.position.x = initial_layer3_objects_position - (scroll_offset * scroll_speed_layer3)


## Reset scroll
func reset() -> void:
	scroll_to(0.0)
