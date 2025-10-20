extends CanvasLayer

## Transition Scene - Handles smooth scene transitions
## Fades to black with a loading spinner, then fades into the next scene

@onready var fade_rect: ColorRect = $FadeRect
@onready var spinner: Control = $Spinner
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var parallax_bg: Control = $ParallaxBackground
@onready var far_trees: TextureRect = $ParallaxBackground/FarTrees
@onready var mid_trees: TextureRect = $ParallaxBackground/MidTrees
@onready var close_trees: TextureRect = $ParallaxBackground/CloseTrees

var target_scene: String = ""
var is_transitioning: bool = false

# Transition timing
var fade_out_duration: float = 0.4
var fade_in_duration: float = 0.4
var min_transition_time: float = 5.0  # Minimum 5 seconds to show loading

# Parallax scrolling
var parallax_scroll_offset: float = 0.0
var parallax_scroll_speed: float = 30.0  # pixels per second


func _ready() -> void:
	# Start invisible
	fade_rect.visible = false
	fade_rect.modulate.a = 0.0
	spinner.modulate.a = 0.0
	spinner.visible = false
	progress_bar.visible = false
	progress_bar.value = 0.0

	# Hide parallax background initially
	parallax_bg.visible = false
	parallax_bg.modulate.a = 0.0

	# Make sure this layer is on top
	layer = 100


func _process(delta: float) -> void:
	# Rotate spinner if visible
	if spinner.visible:
		spinner.rotation += delta * 3.0  # Rotation speed

	# Update parallax scrolling if transitioning
	if is_transitioning:
		parallax_scroll_offset += delta * parallax_scroll_speed

		# Update shader parameters for each layer
		if far_trees and far_trees.material:
			far_trees.material.set_shader_parameter("scroll_offset", parallax_scroll_offset * 0.3)
		if mid_trees and mid_trees.material:
			mid_trees.material.set_shader_parameter("scroll_offset", parallax_scroll_offset * 0.6)
		if close_trees and close_trees.material:
			close_trees.material.set_shader_parameter("scroll_offset", parallax_scroll_offset * 1.0)


## Start transition to a new scene
func transition_to(scene_path: String) -> void:
	if is_transitioning:
		return

	is_transitioning = true
	target_scene = scene_path

	# Show fade rect and block mouse input during transition
	fade_rect.visible = true
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	parallax_bg.visible = true
	parallax_bg.modulate.a = 0.0

	# Start fade out
	await _fade_out()

	var fade_tween = create_tween()
	fade_tween.tween_property(fade_rect, "modulate:a", 0.7, 0.3)

	# Fade in parallax background after fade to black
	print("Fading in parallax background, current alpha: ", parallax_bg.modulate.a)
	var bg_tween = create_tween()
	bg_tween.tween_property(parallax_bg, "modulate:a", 1.0, 0.3)
	await bg_tween.finished

	# Show spinner and progress bar
	spinner.visible = true
	progress_bar.visible = true
	progress_bar.value = 0.0
	var ui_tween = create_tween()
	ui_tween.set_parallel(true)
	ui_tween.tween_property(spinner, "modulate:a", 1.0, 0.2)
	ui_tween.tween_property(progress_bar, "modulate:a", 1.0, 0.2)

	# Start progress bar animation
	var start_time = Time.get_ticks_msec()
	_animate_progress_bar(min_transition_time)

	# Load the new scene
	var error = get_tree().change_scene_to_file(target_scene)

	if error != OK:
		push_error("Failed to load scene: %s (Error: %d)" % [target_scene, error])
		is_transitioning = false
		await _fade_in()
		return

	# Ensure minimum transition time has passed
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	if elapsed < min_transition_time:
		await get_tree().create_timer(min_transition_time - elapsed).timeout

	# Hide spinner, progress bar, and parallax background
	var hide_ui = create_tween()
	hide_ui.set_parallel(true)
	hide_ui.tween_property(spinner, "modulate:a", 0.0, 0.2)
	hide_ui.tween_property(progress_bar, "modulate:a", 0.0, 0.2)
	hide_ui.tween_property(parallax_bg, "modulate:a", 0.0, 0.2)
	hide_ui.tween_property(fade_rect, "modulate:a", 1.0, 0.2)  # Fade back to full black
	await hide_ui.finished
	spinner.visible = false
	progress_bar.visible = false
	parallax_bg.visible = false

	# Fade in to new scene
	await _fade_in()

	# Hide fade rect and re-enable mouse input
	fade_rect.visible = false
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Reset parallax offset
	parallax_scroll_offset = 0.0

	is_transitioning = false


## Fade out to black
func _fade_out() -> void:
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_out_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished


## Fade in from black
func _fade_in() -> void:
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, fade_in_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished


## Quick fade (for immediate transitions)
func quick_fade_out() -> void:
	fade_rect.modulate.a = 1.0


func quick_fade_in() -> void:
	fade_rect.modulate.a = 0.0


## Animate progress bar over duration
func _animate_progress_bar(duration: float) -> void:
	var tween = create_tween()
	tween.tween_property(progress_bar, "value", 100.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
