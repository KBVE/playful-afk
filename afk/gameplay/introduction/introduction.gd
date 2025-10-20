extends Control

## Introduction Scene for AFK Virtual Pet Game
## Welcomes the player and introduces the game concept

@onready var background: ForestIntroBackground = $ForestIntroBackground
@onready var welcome_panel: GamePanel = $WelcomePanel
@onready var welcome_text: RichTextLabel = $WelcomePanel/ContentContainer/Content/WelcomeText
@onready var continue_button: Button = $WelcomePanel/ContentContainer/Content/ContinueButton

# Text writer effect variables
var full_text: String = ""
var current_char_index: int = 0
var text_speed: float = 0.03  # Time between each character
var text_timer: float = 0.0
var is_writing: bool = false


func _ready() -> void:
	# Set up the welcome panel
	if welcome_panel:
		welcome_panel.panel_title = ""  # No title for this panel

		# Animate the panel in
		welcome_panel.modulate.a = 0.0
		welcome_panel.scale = Vector2(0.8, 0.8)

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(welcome_panel, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(welcome_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Connect button
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
		# Button is always visible, allowing player to skip text animation

	# Setup text writer effect
	if welcome_text:
		full_text = welcome_text.text
		welcome_text.visible_characters = 0  # Hide all characters initially
		# Start writing after panel animation completes
		await get_tree().create_timer(0.6).timeout
		_start_text_writer()

	# Note: game_started signal is emitted by EventManager.start_new_game()


func _process(delta: float) -> void:
	if is_writing:
		_update_text_writer(delta)


func _on_continue_pressed() -> void:
	# Play button click sound
	EventManager.sfx_play_requested.emit("button_click")

	# If text is still writing, skip to the end
	if is_writing:
		is_writing = false
		if welcome_text:
			welcome_text.visible_characters = -1  # Show all text immediately
		print("Text animation skipped")
		return

	print("Continue pressed - transitioning to main game...")

	# Fade out the panel, then transition to main game
	var tween = create_tween()
	tween.tween_property(welcome_panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): EventManager.start_main_game())


func _start_text_writer() -> void:
	is_writing = true
	current_char_index = 0
	text_timer = 0.0


func _update_text_writer(delta: float) -> void:
	text_timer += delta

	if text_timer >= text_speed:
		text_timer = 0.0
		current_char_index += 1

		# Get total visible characters (excluding BBCode tags)
		var total_chars = welcome_text.get_total_character_count()

		if current_char_index <= total_chars:
			# Update visible characters (this automatically skips BBCode tags)
			welcome_text.visible_characters = current_char_index
		else:
			# Text writing complete
			is_writing = false
			welcome_text.visible_characters = -1  # Show all
			_on_text_complete()


func _on_text_complete() -> void:
	print("Text writing complete")
	# Text animation is done, button is already visible
