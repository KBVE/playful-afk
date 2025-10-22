extends "res://nodes/environment/environment.gd"
class_name CatFlag

## CatFlag - A decorative flag environment object
## Temporary object that despawns after 1 minute

## Flag animation state
var is_waving: bool = false


## Called when spawned from pool
func on_spawn() -> void:
	# Set properties (these will be set by EnvironmentManager too, but good to ensure)
	is_static = false
	lifetime_seconds = 60.0

	# Start waving animation if using AnimatedSprite
	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation("wave"):
			animated_sprite.play("wave")
			is_waving = true
	elif sprite:
		# Static sprite - could add gentle sway with shaders later
		pass


## Called when despawned
func on_despawn() -> void:
	# Stop animation
	if animated_sprite:
		animated_sprite.stop()
	is_waving = false
