extends TextureRect
class_name GameLogo

## GameLogo - Reusable game logo component with optional animations
## Displays the Virtual AFK Pet logo with various display options

## Enable/disable entrance animation on ready
@export var animate_on_ready: bool = false

## Animation type for entrance
@export_enum("None", "FadeIn", "ScaleIn", "BounceIn") var entrance_animation: String = "None"

## Duration of entrance animation
@export var animation_duration: float = 0.8

## Enable idle bobbing animation
@export var enable_idle_bob: bool = false

## Bobbing animation speed
@export var bob_speed: float = 2.0

## Bobbing animation amplitude (pixels)
@export var bob_amplitude: float = 5.0

var _original_position: Vector2
var _time: float = 0.0


func _ready() -> void:
	# Load the logo texture
	texture = load("res://nodes/ui/logo/logo.png")

	# Set texture settings
	expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_original_position = position

	# Play entrance animation if enabled
	if animate_on_ready:
		_play_entrance_animation()


func _process(delta: float) -> void:
	if enable_idle_bob:
		_time += delta
		var bob_offset = sin(_time * bob_speed) * bob_amplitude
		position.y = _original_position.y + bob_offset


func _play_entrance_animation() -> void:
	match entrance_animation:
		"FadeIn":
			_animate_fade_in()
		"ScaleIn":
			_animate_scale_in()
		"BounceIn":
			_animate_bounce_in()


func _animate_fade_in() -> void:
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_scale_in() -> void:
	scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, animation_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_bounce_in() -> void:
	scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, animation_duration).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Play a custom animation (call this manually)
func play_animation(anim_type: String) -> void:
	entrance_animation = anim_type
	_play_entrance_animation()


## Start the idle bob animation
func start_bobbing() -> void:
	enable_idle_bob = true
	_time = 0.0


## Stop the idle bob animation
func stop_bobbing() -> void:
	enable_idle_bob = false
	position = _original_position


## Pulse the logo (for attention/feedback)
func pulse(scale_amount: float = 1.2, duration: float = 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * scale_amount, duration * 0.5).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2.ONE, duration * 0.5).set_trans(Tween.TRANS_ELASTIC)
