extends Node2D
class_name ReleaseEffect

## Release Effect - Pooled death animation managed by Rust
## Plays a smoke/puff effect at death location
## Rust automatically returns effect to pool after animation duration

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Start hidden - will be shown when played
	visible = false

	# Connect to animation finished signal to auto-hide
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)


## Play the release effect (called by Rust via call_deferred("play"))
func play() -> void:
	# Safety check - ensure we're in the scene tree
	if not is_inside_tree():
		push_warning("ReleaseEffect.play() called but node not in tree yet")
		return

	visible = true

	# Get the AnimatedSprite2D (might not be ready during @onready if called early)
	if not animated_sprite:
		animated_sprite = get_node_or_null("AnimatedSprite2D")

	if animated_sprite:
		animated_sprite.play("release")
	else:
		push_error("ReleaseEffect.play() - AnimatedSprite2D not found!")


## Called when animation finishes - hide the effect and return to pool
func _on_animation_finished() -> void:
	visible = false
	# Reset animation to first frame
	if animated_sprite:
		animated_sprite.stop()
		animated_sprite.frame = 0
