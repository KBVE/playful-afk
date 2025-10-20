extends Control
class_name ChatUI

## Chat UI for NPC dialogue
## Left side: NPC portrait (20%)
## Right side: Dialogue box with text and buttons (80%)

## Signals
signal dialogue_option_selected(option_index: int)
signal dialogue_closed

## Node references
@onready var npc_portrait_panel: Panel = $CenterContainer/Panel/HBoxContainer/NPCPortraitPanel
@onready var npc_name_label: Label = $CenterContainer/Panel/HBoxContainer/NPCPortraitPanel/VBoxContainer/NPCNameLabel
@onready var npc_portrait_container: CenterContainer = $CenterContainer/Panel/HBoxContainer/NPCPortraitPanel/VBoxContainer/NPCPortraitContainer

@onready var dialogue_panel: Panel = $CenterContainer/Panel/HBoxContainer/DialoguePanel
@onready var dialogue_text: RichTextLabel = $CenterContainer/Panel/HBoxContainer/DialoguePanel/VBoxContainer/DialogueText
@onready var button_container: VBoxContainer = $CenterContainer/Panel/HBoxContainer/DialoguePanel/VBoxContainer/ButtonContainer
@onready var close_button: Button = $CenterContainer/Panel/HBoxContainer/DialoguePanel/VBoxContainer/ButtonContainer/CloseButton

## Current NPC data
var current_npc_name: String = ""
var current_npc_sprite: AnimatedSprite2D = null


func _ready() -> void:
	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

	# Start hidden
	visible = false
	print("ChatUI initialized")


## Show the chat UI with NPC (DOES NOT make visible - caller must do that)
## Uses cached UI sprite from NPCManager for better performance
func show_dialogue(npc_name: String, npc: Node2D = null) -> void:
	current_npc_name = npc_name
	print("ChatUI: show_dialogue called with npc_name=", npc_name, " npc=", npc)

	# Set NPC name
	if npc_name_label:
		npc_name_label.text = npc_name
		print("ChatUI: Set NPC name to ", npc_name)
	else:
		print("ChatUI ERROR: npc_name_label is null!")

	# Remove previous NPC sprite from UI (but don't free it - it's cached)
	if current_npc_sprite and npc_portrait_container:
		npc_portrait_container.remove_child(current_npc_sprite)
		current_npc_sprite = null

	# Get cached UI sprite from NPCManager (no duplication!)
	if npc and npc_portrait_container:
		var npc_type = NPCManager.get_npc_type(npc)
		if npc_type != "":
			current_npc_sprite = NPCManager.get_ui_sprite(npc_type)
			if current_npc_sprite:
				# Add cached sprite to UI (will be removed, not freed, when dialogue closes)
				npc_portrait_container.add_child(current_npc_sprite)
				current_npc_sprite.play("idle")  # Play idle animation
				current_npc_sprite.scale = Vector2(3, 3)  # Scale up for portrait
				print("ChatUI: Using cached UI sprite for ", npc_type)
			else:
				push_warning("ChatUI: No cached UI sprite found for ", npc_type)
	else:
		print("ChatUI: npc or npc_portrait_container is null")

	# Clear previous dialogue
	if dialogue_text:
		dialogue_text.text = ""

	# NOTE: Do NOT set visible = true here - let the caller control visibility after camera pans
	print("ChatUI: Dialogue prepared for ", npc_name)


## Hide the chat UI
func hide_dialogue() -> void:
	visible = false
	current_npc_name = ""

	# Remove cached sprite from UI (but don't free it - it's cached in NPCManager)
	if current_npc_sprite and npc_portrait_container:
		npc_portrait_container.remove_child(current_npc_sprite)
		current_npc_sprite = null

	print("ChatUI: Dialogue hidden")


## Set the dialogue text
func set_dialogue_text(text: String) -> void:
	if dialogue_text:
		dialogue_text.text = text


## Add a dialogue option button (for future branching dialogue)
func add_dialogue_option(option_text: String, option_index: int) -> void:
	var button = Button.new()
	button.text = option_text
	button.pressed.connect(func(): _on_dialogue_option_pressed(option_index))

	# Insert before close button
	if button_container:
		var close_button_index = button_container.get_child_count() - 1
		button_container.add_child(button)
		button_container.move_child(button, close_button_index)


## Clear all dialogue option buttons
func clear_dialogue_options() -> void:
	if not button_container:
		return

	# Remove all buttons except the close button
	for child in button_container.get_children():
		if child != close_button:
			child.queue_free()


## Handle dialogue option button pressed
func _on_dialogue_option_pressed(option_index: int) -> void:
	print("ChatUI: Dialogue option ", option_index, " selected")
	dialogue_option_selected.emit(option_index)


## Handle close button pressed
func _on_close_button_pressed() -> void:
	print("ChatUI: Close button pressed")
	dialogue_closed.emit()
	hide_dialogue()
