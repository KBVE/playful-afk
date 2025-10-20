extends Control
class_name Bartender

## Bartender background scene for NPC conversations
## Static background showing a bar interior
## Will be used for dialogue and NPC interactions

signal dialogue_finished

@onready var background: TextureRect = $Background
@onready var chat_ui: ChatUI = $ChatUI

## Current NPC being talked to
var current_npc: Node2D = null


func _ready() -> void:
	# Connect chat UI signals
	if chat_ui:
		chat_ui.dialogue_closed.connect(_on_dialogue_closed)
	print("Bartender scene initialized")


## Show the bartender scene with an NPC for conversation
func show_dialogue_with_npc(npc: Node2D, npc_name: String) -> void:
	visible = true
	current_npc = npc

	# Get the NPC's AnimatedSprite2D for the portrait (will be duplicated in ChatUI)
	var npc_sprite: AnimatedSprite2D = null
	if npc.has_node("AnimatedSprite2D"):
		npc_sprite = npc.get_node("AnimatedSprite2D")

	# Show chat UI with NPC (ChatUI will duplicate the sprite)
	if chat_ui:
		chat_ui.show_dialogue(npc_name, npc_sprite)
		# Set default dialogue text
		chat_ui.set_dialogue_text("Hello traveler! What can I do for you?")

	print("Bartender: Showing dialogue with ", npc_name)


## Show the bartender scene (fade in, animate in, etc.)
func show_scene() -> void:
	visible = true
	print("Bartender scene shown")


## Hide the bartender scene
func hide_scene() -> void:
	visible = false
	current_npc = null
	if chat_ui:
		chat_ui.hide_dialogue()
	print("Bartender scene hidden")


## Handle dialogue closed
func _on_dialogue_closed() -> void:
	print("Bartender: Dialogue closed")
	hide_scene()
	# Signal to main scene to return to ground view
	dialogue_finished.emit()
