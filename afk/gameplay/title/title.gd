extends Control

## Title Screen for AFK Virtual Pet Game
## Handles the main menu and game start flow

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready() -> void:
	# Connect button signals
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	# TODO: Transition to main game scene
	print("Start game pressed")
	# get_tree().change_scene_to_file("res://gameplay/main/main.tscn")


func _on_options_pressed() -> void:
	# TODO: Open options/settings menu
	print("Options pressed")


func _on_quit_pressed() -> void:
	# Quit the game
	get_tree().quit()
