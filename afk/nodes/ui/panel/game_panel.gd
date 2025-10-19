extends NinePatchRect
class_name GamePanel

## GamePanel - Resizable decorative panel for UI elements
## Uses 9-patch texture to maintain border decorations while scaling

## Optional title text for the panel
@export var panel_title: String = "":
	set(value):
		panel_title = value
		if title_label:
			title_label.text = value
			title_label.visible = value != ""

## Optional panel color tint
@export var panel_color: Color = Color(0.686, 0.439, 0.443, 1.0):  # #af7071
	set(value):
		panel_color = value
		modulate = value

## Padding inside the panel for content
@export var content_padding: Vector4 = Vector4(20, 20, 20, 20):  # left, top, right, bottom
	set(value):
		content_padding = value
		_update_content_margins()

@onready var title_label: Label = $TitleLabel
@onready var content_container: MarginContainer = $ContentContainer


func _ready() -> void:
	# Set up the 9-patch texture
	texture = load("res://nodes/ui/panel/panel.png")

	# Configure 9-patch regions (adjust these values based on your texture)
	# These define which parts are corners, edges, and center
	patch_margin_left = 32
	patch_margin_top = 32
	patch_margin_right = 32
	patch_margin_bottom = 32

	# Apply initial settings
	modulate = panel_color
	_update_content_margins()

	if title_label:
		title_label.text = panel_title
		title_label.visible = panel_title != ""


func _update_content_margins() -> void:
	if not content_container:
		return

	content_container.add_theme_constant_override("margin_left", int(content_padding.x))
	content_container.add_theme_constant_override("margin_top", int(content_padding.y))
	content_container.add_theme_constant_override("margin_right", int(content_padding.z))
	content_container.add_theme_constant_override("margin_bottom", int(content_padding.w))


## Get the content container to add child nodes
func get_content_container() -> MarginContainer:
	return content_container
