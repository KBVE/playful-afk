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

# Combat tracking
var attacker: Node2D = null  # Who fired this arrow

# References
@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = $HitBox

# Projectile type (for returning to pool)
const PROJECTILE_TYPE: String = "arrow"


func _ready() -> void:
	# Arrow starts inactive
	is_active = false
	process_mode = Node.PROCESS_MODE_DISABLED

	# Connect hitbox signal
	if hitbox:
		hitbox.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if not is_active:
		return

	# Move arrow (velocity is already in global space)
	position += velocity * delta

	# Check if arrow has traveled max distance (use global_position for parallax compatibility)
	var distance_traveled = start_position.distance_to(global_position)
	if distance_traveled >= max_distance:
		_return_to_pool()
		return

	# Check if arrow is off-screen (viewport bounds check)
	if _is_off_screen():
		_return_to_pool()
		return


## Fire the arrow towards a target
func fire(target: Vector2, fire_speed: float = 300.0, from_attacker: Node2D = null) -> void:
	is_active = true
	target_position = target
	start_position = global_position  # Use global_position for parallax compatibility
	speed = fire_speed
	attacker = from_attacker

	# Calculate velocity using global coordinates (parallax-safe)
	var direction = (target_position - global_position).normalized()
	velocity = direction * speed

	# Rotate arrow to face direction of travel
	rotation = velocity.angle()

	# Enable processing
	process_mode = Node.PROCESS_MODE_INHERIT


## Check if arrow is outside viewport bounds
func _is_off_screen() -> bool:
	var viewport = get_viewport()
	if not viewport:
		return false

	var viewport_rect = viewport.get_visible_rect()
	var screen_position = global_position

	# Add margin to allow arrow to travel slightly off-screen before returning
	var margin = 100.0

	return (screen_position.x < -margin or
			screen_position.x > viewport_rect.size.x + margin or
			screen_position.y < -margin or
			screen_position.y > viewport_rect.size.y + margin)


## Return arrow to pool
func _return_to_pool() -> void:
	is_active = false
	velocity = Vector2.ZERO
	process_mode = Node.PROCESS_MODE_DISABLED

	# Return to ProjectileManager
	if ProjectileManager:
		ProjectileManager.return_projectile(self, PROJECTILE_TYPE)


## Handle collision (to be called externally or via Area2D signal)
func on_hit(target: Node2D) -> void:
	# RUST COMBAT: Call Rust to handle damage calculation and application
	if NPCDataWarehouse and attacker and target:
		# Get attacker and target ULIDs
		if "stats" in attacker and attacker.stats and "ulid" in attacker.stats:
			if "stats" in target and target.stats and "ulid" in target.stats:
				var attacker_ulid = attacker.stats.ulid
				var target_ulid = target.stats.ulid

				# Call Rust to handle projectile hit (calculates damage, applies it, returns events)
				var events_json = NPCDataWarehouse.projectile_hit(attacker_ulid, target_ulid)

				# Process damage/death events through NPCManager
				if NPCManager:
					for event_json in events_json:
						var event = JSON.parse_string(event_json)
						if event:
							NPCManager._handle_combat_event(event)

	# Return to pool (deferred to avoid physics callback issues)
	call_deferred("_return_to_pool")


## Reset arrow state (called by pool manager)
func reset() -> void:
	is_active = false
	velocity = Vector2.ZERO
	position = Vector2.ZERO
	rotation = 0.0
	visible = false
	attacker = null
	process_mode = Node.PROCESS_MODE_DISABLED


## Called when arrow's hitbox collides with a body
func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return

	# Don't hit the attacker who fired the arrow
	if body == attacker:
		return

	# Check if body can take damage
	if body.has_method("take_damage"):
		on_hit(body)
