extends CanvasLayer
class_name Modal

## Reusable modal/popup window system
## Can be used for interactions with objects, dialogs, menus, etc.
## Includes animations, overlay darkening, and flexible content area

## Signals
signal modal_opened
signal modal_closed
signal close_button_pressed

## UI Elements
@onready var overlay: ColorRect = $Overlay
@onready var modal_container: Control = $ModalContainer
@onready var panel: NinePatchRect = $ModalContainer/Panel
@onready var title_label: Label = $ModalContainer/Panel/VBoxContainer/TitleBar/TitleLabel
@onready var close_button: Button = $ModalContainer/Panel/VBoxContainer/TitleBar/CloseButton
@onready var content_container: Control = $ModalContainer/Panel/VBoxContainer/ContentContainer

## Modal settings
@export var modal_title: String = "Modal Title"
@export var overlay_color: Color = Color(0, 0, 0, 0.7)
@export var can_close_on_overlay_click: bool = true
@export var animation_duration: float = 0.3

## State
var is_open: bool = false
var is_animating: bool = false


func _ready() -> void:
	# Set layer to be on top of most UI
	layer = 100

	# Initialize as hidden
	visible = false

	# Set up overlay
	if overlay:
		overlay.color = overlay_color
		overlay.modulate.a = 0.0  # Start transparent
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		if can_close_on_overlay_click:
			overlay.gui_input.connect(_on_overlay_clicked)

	# Set up close button
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
		close_button.mouse_entered.connect(_on_close_button_hover_enter)
		close_button.mouse_exited.connect(_on_close_button_hover_exit)

	# Set modal container initial scale for animation
	if modal_container:
		modal_container.pivot_offset = modal_container.size / 2
		modal_container.scale = Vector2(0.8, 0.8)
		modal_container.modulate.a = 0.0  # Start transparent

	print("Modal initialized: ", name)


## Open the modal with animation
func open() -> void:
	if is_open or is_animating:
		return

	is_animating = true
	visible = true

	# Register with InputManager to block background interactions
	if InputManager:
		InputManager.register_modal(self)

	# Set title
	if title_label:
		title_label.text = modal_title

	# Animate in
	var tween = create_tween()
	tween.set_parallel(true)

	# Fade in overlay
	if overlay:
		tween.tween_property(overlay, "modulate:a", 1.0, animation_duration)

	# Scale and fade in modal
	if modal_container:
		tween.tween_property(modal_container, "scale", Vector2(1.0, 1.0), animation_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(modal_container, "modulate:a", 1.0, animation_duration)

	await tween.finished

	is_animating = false
	is_open = true
	modal_opened.emit()
	print("Modal opened: ", name)


## Close the modal with animation
func close() -> void:
	if not is_open or is_animating:
		return

	is_animating = true

	# Unregister from InputManager to restore background interactions
	if InputManager:
		InputManager.unregister_modal(self)

	# Animate out
	var tween = create_tween()
	tween.set_parallel(true)

	# Fade out overlay
	if overlay:
		tween.tween_property(overlay, "modulate:a", 0.0, animation_duration)

	# Scale and fade out modal
	if modal_container:
		tween.tween_property(modal_container, "scale", Vector2(0.8, 0.8), animation_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(modal_container, "modulate:a", 0.0, animation_duration)

	await tween.finished

	visible = false
	is_animating = false
	is_open = false
	modal_closed.emit()
	print("Modal closed: ", name)


## Toggle the modal open/closed
func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Set the modal title
func set_title(new_title: String) -> void:
	modal_title = new_title
	if title_label:
		title_label.text = new_title


## Set custom content in the modal
## You can pass any Control node to be displayed
func set_content(content_node: Control) -> void:
	if not content_container:
		return

	# Clear existing content
	for child in content_container.get_children():
		child.queue_free()

	# Add new content
	content_container.add_child(content_node)
	print("Modal content set")


## Clear all content from the modal
func clear_content() -> void:
	if not content_container:
		return

	for child in content_container.get_children():
		child.queue_free()


## Handle overlay clicks
func _on_overlay_clicked(event: InputEvent) -> void:
	if not can_close_on_overlay_click:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()


## Handle close button press
func _on_close_button_pressed() -> void:
	close_button_pressed.emit()
	close()


## Handle close button hover enter
func _on_close_button_hover_enter() -> void:
	if close_button:
		var tween = create_tween()
		tween.tween_property(close_button, "scale", Vector2(1.2, 1.2), 0.1)


## Handle close button hover exit
func _on_close_button_hover_exit() -> void:
	if close_button:
		var tween = create_tween()
		tween.tween_property(close_button, "scale", Vector2(1.0, 1.0), 0.1)


## Handle escape key to close
func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
