extends Control
class_name ChatBubble

## Floating chat bubble that appears above NPCs
## Displays emojis based on NPC index with randomized timing

## Signals
signal bubble_hidden  # Emitted when bubble finishes hiding (for pool management)

## Configuration
@export var bubble_offset: Vector2 = Vector2(0, -60)  # Offset from parent position
@export var fade_duration: float = 0.3
@export var display_duration: float = 2.0  # How long to show the emoji

## Node references
@onready var bubble_sprite: Sprite2D = $BubbleSprite
@onready var emoji_label: RichTextLabel = $BubbleSprite/EmojiLabel

## State
var is_visible_bubble: bool = false
var display_timer: Timer
var parent_entity: Node2D = null


func _ready() -> void:
	# Start invisible
	modulate.a = 0.0
	visible = false

	# Create and configure timer
	display_timer = Timer.new()
	add_child(display_timer)
	display_timer.one_shot = true
	display_timer.timeout.connect(_on_display_timeout)


## Show the chat bubble with an emoji
func show_bubble(emoji: String) -> void:
	if is_visible_bubble:
		return

	is_visible_bubble = true

	# Set emoji text (wrapped in BBCode center tags)
	if emoji_label:
		emoji_label.text = "[center]%s[/center]" % emoji

	# Make visible and fade in
	visible = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished

	# Start display timer
	display_timer.start(display_duration)


## Hide the chat bubble
func hide_bubble() -> void:
	if not is_visible_bubble:
		return

	is_visible_bubble = false

	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished

	visible = false

	# Emit signal for pool management
	bubble_hidden.emit()


## Called when display timer expires
func _on_display_timeout() -> void:
	hide_bubble()


## Update position to follow parent entity
func _process(_delta: float) -> void:
	if parent_entity and is_instance_valid(parent_entity):
		global_position = parent_entity.global_position + bubble_offset


## Set the parent entity to follow
func set_parent_entity(entity: Node2D) -> void:
	parent_entity = entity
	if parent_entity:
		global_position = parent_entity.global_position + bubble_offset
