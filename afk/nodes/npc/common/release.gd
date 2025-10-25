extends Node2D
class_name ReleaseEffect

## Release Effect - Pooled death animation managed by Rust
## Plays a smoke/puff effect at death location
## Rust automatically returns effect to pool after animation duration

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Start hidden - Rust will show it when triggered
	visible = false


## Play the release effect (called by Rust via call("play"))
func play() -> void:
	visible = true
	if animated_sprite:
		animated_sprite.play("release")
