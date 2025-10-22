extends Node2D
class_name ReleaseEffect

## Release Effect - One-off animation when NPCs/monsters die and return to pool
## Plays a smoke/puff effect at the death location
## The entity is removed from the scene mid-way through the animation

signal animation_finished
signal midpoint_reached  # Emitted when entity should be removed (halfway through animation)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _has_reached_midpoint: bool = false


func _ready() -> void:
	# Connect to animation frame changed to detect midpoint
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)
		animated_sprite.frame_changed.connect(_on_frame_changed)


## Play the release effect at the given position
func play_at(position: Vector2) -> void:
	global_position = position
	visible = true
	_has_reached_midpoint = false

	if animated_sprite:
		animated_sprite.play("release")


## Called when animation frame changes
func _on_frame_changed() -> void:
	if not _has_reached_midpoint and animated_sprite:
		# Emit midpoint signal at frame 5 (roughly middle of 11 frames)
		if animated_sprite.frame == 5:
			_has_reached_midpoint = true
			midpoint_reached.emit()


## Called when animation finishes
func _on_animation_finished() -> void:
	animation_finished.emit()
	# Clean up after animation
	queue_free()
