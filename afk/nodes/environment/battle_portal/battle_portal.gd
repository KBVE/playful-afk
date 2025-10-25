extends Node2D
class_name BattlePortal

## Battle Portal - Looping portal animation for NPC spawns
## Plays a continuous portal animation at spawn locations
## Can be used for both ally and monster spawning

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Start portal animation immediately
	if animated_sprite:
		animated_sprite.play("portal")


## Play the portal animation (useful if stopping/starting dynamically)
func play() -> void:
	if animated_sprite:
		animated_sprite.play("portal")


## Stop the portal animation
func stop() -> void:
	if animated_sprite:
		animated_sprite.stop()
