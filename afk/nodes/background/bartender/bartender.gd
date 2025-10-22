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


## Show the bartender scene with an NPC for conversation
func show_dialogue_with_npc(npc: Node2D, npc_name: String) -> void:
	visible = true
	current_npc = npc

	# Show chat UI with NPC (ChatUI will use cached sprite from NPCManager)
	if chat_ui:
		chat_ui.show_dialogue(npc_name, npc)
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
	# NOTE: Don't hide scene here - EventManager controls visibility
	# Just emit the signal so main scene knows to transition
	dialogue_finished.emit()
