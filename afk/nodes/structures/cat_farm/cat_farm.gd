extends Node2D
class_name CatFarm

## A cat farm structure that can be placed in parallax backgrounds
## Automatically handles sprite rendering, floating animation, and click detection

signal farm_clicked

@onready var sprite: Sprite2D = $Sprite2D
@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D

## Floating animation properties
@export var float_amplitude: float = 10.0  ## How high/low it floats
@export var float_speed: float = 2.0  ## Speed of floating animation

var time_elapsed: float = 0.0
var initial_y_position: float = 0.0

func _ready() -> void:
	# Set up the sprite with the cat farm texture
	if sprite:
		sprite.centered = true
		sprite.scale = Vector2(1.0, 1.0)
		initial_y_position = sprite.position.y

	# Connect click area signal
	if click_area:
		click_area.input_event.connect(_on_click_area_input_event)
		click_area.mouse_entered.connect(_on_mouse_entered)
		click_area.mouse_exited.connect(_on_mouse_exited)

func _process(delta: float) -> void:
	# Update floating animation
	time_elapsed += delta
	if sprite:
		sprite.position.y = initial_y_position + sin(time_elapsed * float_speed) * float_amplitude

## Handle input events on the click area
func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_farm_clicked()

## Called when the farm is clicked
func _on_farm_clicked() -> void:
	print("Cat Farm clicked!")
	farm_clicked.emit()
	# Add a small bounce effect when clicked
	_play_click_animation()

## Play a small bounce animation when clicked
func _play_click_animation() -> void:
	var tween = create_tween()
	var original_scale = sprite.scale
	tween.tween_property(sprite, "scale", original_scale * 1.2, 0.1)
	tween.tween_property(sprite, "scale", original_scale, 0.1)

## Handle mouse enter for visual feedback
func _on_mouse_entered() -> void:
	# Slightly brighten the sprite when hovered
	if sprite:
		sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)

## Handle mouse exit
func _on_mouse_exited() -> void:
	# Return to normal color
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

## Set the scale of the cat farm
func set_farm_scale(new_scale: Vector2) -> void:
	if sprite:
		sprite.scale = new_scale

## Get the bounds of the farm for collision or placement purposes
func get_farm_bounds() -> Rect2:
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(position - scaled_size / 2, scaled_size)
	return Rect2()
