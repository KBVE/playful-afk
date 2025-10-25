extends Label

## Floating damage text that appears above NPCs when they take damage
## Shows damage amount with inner shadow effect and floats upward before fading

var float_speed: float = 50.0  # Pixels per second upward
var fade_duration: float = 1.0  # Total duration before removal
var elapsed: float = 0.0

func _ready() -> void:
	# Set up label properties for damage/healing text
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Add outline for inner shadow effect
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 2)

	# Make text larger and bold
	add_theme_font_size_override("font_size", 20)

	# Color will be set in setup() based on is_healing meta

func _process(delta: float) -> void:
	# Only process if visible (active)
	if not visible:
		return

	elapsed += delta

	# Float upward
	position.y -= float_speed * delta

	# Fade out over time
	var alpha = 1.0 - (elapsed / fade_duration)
	modulate.a = alpha

	# Hide when fully faded (return to pool instead of destroying)
	if elapsed >= fade_duration:
		visible = false
		elapsed = 0.0

## Initialize the damage/healing text with amount and starting position
func setup(amount: int, start_pos: Vector2) -> void:
	# Check if this is a healing text (set via meta in healthbar.gd)
	var is_healing = get_meta("is_healing", false)

	if is_healing:
		# Healing text: green color with + prefix
		text = "+%d" % amount
		add_theme_color_override("font_color", Color(0.2, 1.0, 0.2, 1.0))  # Bright green
	else:
		# Damage text: red color with - prefix
		text = "-%d" % amount
		add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))  # Bright red

	position = start_pos
	elapsed = 0.0
	modulate.a = 1.0
	visible = true
