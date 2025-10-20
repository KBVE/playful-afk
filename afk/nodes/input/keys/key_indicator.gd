extends HBoxContainer
class_name KeyIndicator

## Key Indicator - Shows a key icon with optional label
## Used to indicate keyboard shortcuts in UI (ESC, Enter, etc.)

@onready var key_icon: TextureRect = $KeyIcon
@onready var label: Label = $Label

## Key texture to display
@export var key_texture: Texture2D

## Label text (optional)
@export var label_text: String = ""

## Icon size
@export var icon_size: Vector2 = Vector2(32, 32)


func _ready() -> void:
	# Set key icon
	if key_icon and key_texture:
		key_icon.texture = key_texture
		key_icon.custom_minimum_size = icon_size
		key_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Set label if provided
	if label and label_text != "":
		label.text = label_text
		label.visible = true
	elif label:
		label.visible = false


## Set the key texture dynamically
func set_key_texture(texture: Texture2D) -> void:
	key_texture = texture
	if key_icon:
		key_icon.texture = texture


## Set the label text dynamically
func set_label(text: String) -> void:
	label_text = text
	if label:
		label.text = text
		label.visible = text != ""
