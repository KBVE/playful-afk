extends Button
class_name MainButton

## MainButton - Reusable styled button for the AFK Virtual Pet game
## Provides consistent styling and hover effects across all UI buttons

## The text displayed on the button
@export var button_text: String = "Button":
	set(value):
		button_text = value
		text = value

## Button color theme options
@export_enum("Primary", "Secondary", "Danger", "Success") var button_style: String = "Primary":
	set(value):
		button_style = value
		_apply_style()

## Enable/disable hover animation
@export var enable_hover_effect: bool = true

## Enable/disable sound effects
@export var enable_sfx: bool = true

# Color themes for different button styles
var color_themes = {
	"Primary": {
		"normal": Color(0.3, 0.5, 0.8, 1.0),      # Blue
		"hover": Color(0.4, 0.6, 0.9, 1.0),       # Lighter blue
		"pressed": Color(0.2, 0.4, 0.7, 1.0)      # Darker blue
	},
	"Secondary": {
		"normal": Color(0.5, 0.5, 0.5, 1.0),      # Gray
		"hover": Color(0.6, 0.6, 0.6, 1.0),       # Lighter gray
		"pressed": Color(0.4, 0.4, 0.4, 1.0)      # Darker gray
	},
	"Danger": {
		"normal": Color(0.8, 0.3, 0.3, 1.0),      # Red
		"hover": Color(0.9, 0.4, 0.4, 1.0),       # Lighter red
		"pressed": Color(0.7, 0.2, 0.2, 1.0)      # Darker red
	},
	"Success": {
		"normal": Color(0.3, 0.7, 0.4, 1.0),      # Green
		"hover": Color(0.4, 0.8, 0.5, 1.0),       # Lighter green
		"pressed": Color(0.2, 0.6, 0.3, 1.0)      # Darker green
	}
}

var _original_scale: Vector2
var _is_hovering: bool = false


func _ready() -> void:
	_original_scale = scale
	text = button_text

	# Set pivot point to center for proper scaling
	pivot_offset = size / 2.0

	# Connect button signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)

	# Apply initial style
	_apply_style()


func _apply_style() -> void:
	if not is_inside_tree():
		return

	# Create a StyleBoxFlat for the button
	var style_normal = StyleBoxFlat.new()
	var style_hover = StyleBoxFlat.new()
	var style_pressed = StyleBoxFlat.new()

	var theme_colors = color_themes.get(button_style, color_themes["Primary"])

	# Normal state
	style_normal.bg_color = theme_colors["normal"]
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 12
	style_normal.content_margin_bottom = 12
	# Inner shadow for 3D effect (darker on top/left, lighter on bottom/right)
	style_normal.shadow_color = Color(0, 0, 0, 0.3)
	style_normal.shadow_size = 4
	style_normal.shadow_offset = Vector2(0, -2)
	# Border for added depth
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = Color(0, 0, 0, 0.4)

	# Hover state
	style_hover.bg_color = theme_colors["hover"]
	style_hover.corner_radius_top_left = 8
	style_hover.corner_radius_top_right = 8
	style_hover.corner_radius_bottom_left = 8
	style_hover.corner_radius_bottom_right = 8
	style_hover.content_margin_left = 16
	style_hover.content_margin_right = 16
	style_hover.content_margin_top = 12
	style_hover.content_margin_bottom = 12
	# Inner shadow for 3D effect
	style_hover.shadow_color = Color(0, 0, 0, 0.3)
	style_hover.shadow_size = 4
	style_hover.shadow_offset = Vector2(0, -2)
	# Border
	style_hover.border_width_left = 2
	style_hover.border_width_top = 2
	style_hover.border_width_right = 2
	style_hover.border_width_bottom = 2
	style_hover.border_color = Color(0, 0, 0, 0.4)

	# Pressed state - inverted shadow for pushed-in effect
	style_pressed.bg_color = theme_colors["pressed"]
	style_pressed.corner_radius_top_left = 8
	style_pressed.corner_radius_top_right = 8
	style_pressed.corner_radius_bottom_left = 8
	style_pressed.corner_radius_bottom_right = 8
	style_pressed.content_margin_left = 16
	style_pressed.content_margin_right = 16
	style_pressed.content_margin_top = 12
	style_pressed.content_margin_bottom = 12
	# Inverted shadow for pushed-in effect
	style_pressed.shadow_color = Color(0, 0, 0, 0.5)
	style_pressed.shadow_size = 2
	style_pressed.shadow_offset = Vector2(0, 1)
	# Darker border for pressed state
	style_pressed.border_width_left = 2
	style_pressed.border_width_top = 2
	style_pressed.border_width_right = 2
	style_pressed.border_width_bottom = 2
	style_pressed.border_color = Color(0, 0, 0, 0.6)

	# Apply styles
	add_theme_stylebox_override("normal", style_normal)
	add_theme_stylebox_override("hover", style_hover)
	add_theme_stylebox_override("pressed", style_pressed)

	# Font color
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)


func _on_mouse_entered() -> void:
	_is_hovering = true
	if enable_hover_effect:
		_animate_hover(true)
	if enable_sfx:
		EventManager.sfx_play_requested.emit("button_hover")


func _on_mouse_exited() -> void:
	_is_hovering = false
	if enable_hover_effect:
		_animate_hover(false)


func _on_button_down() -> void:
	if enable_hover_effect:
		var tween = create_tween()
		tween.tween_property(self, "scale", _original_scale * 0.95, 0.1)


func _on_button_up() -> void:
	if enable_hover_effect:
		var target_scale = _original_scale * 1.05 if _is_hovering else _original_scale
		var tween = create_tween()
		tween.tween_property(self, "scale", target_scale, 0.1)


func _on_pressed() -> void:
	if enable_sfx:
		EventManager.sfx_play_requested.emit("button_click")


func _animate_hover(hovering: bool) -> void:
	var tween = create_tween()
	var target_scale = _original_scale * 1.05 if hovering else _original_scale
	tween.tween_property(self, "scale", target_scale, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
