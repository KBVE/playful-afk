extends Node2D
class_name Arrow

## Arrow Projectile
## Manages arrow movement, collision, and lifecycle
## Designed to work with ProjectileManager's object pooling system

## Arrow properties
@export var speed: float = 300.0
@export var max_distance: float = 1000.0  # Max travel distance before returning to pool
@export var damage: float = 10.0

# Movement
var velocity: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var start_position: Vector2 = Vector2.ZERO
var is_active: bool = false

# References
@onready var sprite: Sprite2D = $Sprite2D

# Projectile type (for returning to pool)
const PROJECTILE_TYPE: String = "arrow"


func _ready() -> void:
	# Arrow starts inactive
	is_active = false
	process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	if not is_active:
		return

	# Move arrow
	position += velocity * delta

	# Check if arrow has traveled max distance
	var distance_traveled = start_position.distance_to(position)
	if distance_traveled >= max_distance:
		_return_to_pool()
		return

	# Optionally check if arrow is off-screen
	# (Add screen bounds check here if needed)


## Fire the arrow towards a target
func fire(target: Vector2, fire_speed: float = 300.0) -> void:
	is_active = true
	target_position = target
	start_position = position
	speed = fire_speed

	# Calculate velocity
	var direction = (target_position - position).normalized()
	velocity = direction * speed

	# Rotate arrow to face direction of travel
	rotation = velocity.angle()

	# Enable processing
	process_mode = Node.PROCESS_MODE_INHERIT

	print("Arrow fired from %s to %s at speed %d" % [position, target, speed])


## Return arrow to pool
func _return_to_pool() -> void:
	is_active = false
	velocity = Vector2.ZERO
	process_mode = Node.PROCESS_MODE_DISABLED

	# Return to ProjectileManager
	if ProjectileManager:
		ProjectileManager.return_projectile(self, PROJECTILE_TYPE)
		print("Arrow returned to pool")


## Handle collision (to be called externally or via Area2D signal)
func on_hit(target: Node2D) -> void:
	print("Arrow hit: %s" % target.name)

	# Apply damage if target has a method to take damage
	if target.has_method("take_damage"):
		target.take_damage(damage)

	# Return to pool
	_return_to_pool()


## Reset arrow state (called by pool manager)
func reset() -> void:
	is_active = false
	velocity = Vector2.ZERO
	position = Vector2.ZERO
	rotation = 0.0
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
