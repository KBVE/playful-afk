extends Control
class_name SkyCloudbox

## Sky cloudbox with multiple parallax cloud layers
## Positioned above the main viewport, revealed when camera pans up
## Similar to rolling_hills but optimized for sky/cloud visuals

@onready var layer1: TextureRect = $Layer1
@onready var layer2: TextureRect = $Layer2
@onready var layer3: TextureRect = $Layer3
@onready var layer4: TextureRect = $Layer4

## Scroll speeds for each layer (slower = more distant)
@export var scroll_speed_layer1: float = 0.1
@export var scroll_speed_layer2: float = 0.25
@export var scroll_speed_layer3: float = 0.45
@export var scroll_speed_layer4: float = 0.7

## Auto-scroll settings (clouds drift slowly on their own)
@export var auto_scroll_enabled: bool = true
@export var auto_scroll_speed: float = 5.0  ## Pixels per second

var scroll_offset: float = 0.0
var auto_scroll_offset: float = 0.0


func _ready() -> void:
	print("SkyCloudbox initialized")


func _process(delta: float) -> void:
	# Auto-scroll clouds for ambient movement
	if auto_scroll_enabled:
		auto_scroll_offset += auto_scroll_speed * delta
		_update_layers()


## Scroll the cloudbox layers to a specific offset
func scroll_to(offset: float) -> void:
	scroll_offset = offset
	_update_layers()


## Update all layer materials with current scroll offset
func _update_layers() -> void:
	var total_offset = scroll_offset + auto_scroll_offset

	if layer1 and layer1.material:
		layer1.material.set_shader_parameter("scroll_offset", total_offset * scroll_speed_layer1)

	if layer2 and layer2.material:
		layer2.material.set_shader_parameter("scroll_offset", total_offset * scroll_speed_layer2)

	if layer3 and layer3.material:
		layer3.material.set_shader_parameter("scroll_offset", total_offset * scroll_speed_layer3)

	if layer4 and layer4.material:
		layer4.material.set_shader_parameter("scroll_offset", total_offset * scroll_speed_layer4)
