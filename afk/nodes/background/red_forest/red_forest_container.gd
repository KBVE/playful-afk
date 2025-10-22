extends SubViewportContainer
class_name RedForestContainer

## RedForestContainer - Wraps the parallax background in a SubViewport
## This allows proper rendering of the parallax background as a UI element
## The background renders in its own viewport with a camera

@onready var viewport: SubViewport = $SubViewport
@onready var parallax_bg: ParallaxBackground = $SubViewport/RedForestBackground
@onready var camera: Camera2D = $SubViewport/Camera2D

## Camera scroll speed (how responsive the camera follows the target)
@export var camera_scroll_speed: float = 100.0

## Enable/disable auto-scrolling
@export var auto_scroll: bool = false

## Auto-scroll direction
@export var scroll_direction: float = 1.0

# Camera position
var camera_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Make sure viewport updates
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Set viewport size to match container
	call_deferred("_resize_viewport")



func _resize_viewport() -> void:
	if viewport:
		var container_size = size
		viewport.size = container_size
		print("Viewport resized to: %s" % container_size)


func _process(delta: float) -> void:
	if not camera:
		return

	if auto_scroll:
		# Auto-scroll the camera
		camera_position.x += camera_scroll_speed * scroll_direction * delta
		camera.position = camera_position


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Container was resized, update viewport
		call_deferred("_resize_viewport")


## Scroll the background by moving the camera
func scroll_to_position(pos: Vector2) -> void:
	if camera:
		camera_position = pos
		camera.position = camera_position


## Smooth scroll the camera to a position
func scroll_smooth(target_x: float, delta: float, speed: float = 100.0) -> void:
	if camera:
		camera_position.x = lerp(camera_position.x, target_x, speed * delta)
		camera.position = camera_position


## Enable/disable auto-scrolling
func set_auto_scroll(enabled: bool, direction: float = 1.0) -> void:
	auto_scroll = enabled
	scroll_direction = direction


## Reset camera position
func reset_camera() -> void:
	camera_position = Vector2.ZERO
	if camera:
		camera.position = Vector2.ZERO
