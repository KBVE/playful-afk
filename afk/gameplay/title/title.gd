extends Control

## Title Screen for AFK Virtual Pet Game
## Handles the main menu and game start flow

@onready var game_logo: GameLogo = $VBoxContainer/GameLogo
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var background: RedForestSimple = $RedForestSimple

# Cat testing variables
var screen_width: float
var screen_height: float
var move_right: bool = true
var cat_start_position: float = 0.0

# Animation cycling during idle
var animation_states: Array = ["sleeping", "eating", "playing", "happy", "sad"]
var current_animation_index: int = 0
var animation_change_timer: float = 0.0
var animation_change_interval: float = 4.0  # Change animation every 4 seconds
var idle_duration: float = 8.0  # Stay idle for 8 seconds total
var idle_timer: float = 0.0

func _ready() -> void:
	# Connect button signals
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# Get screen dimensions
	screen_width = get_viewport_rect().size.x
	screen_height = get_viewport_rect().size.y

	# Setup cat for testing
	_setup_cat_testing()


func _on_start_pressed() -> void:
	print("Start game pressed - transitioning to introduction")
	EventManager.sfx_play_requested.emit("button_click")

	# Return cat to NPCManager before scene change
	_cleanup_cat()

	EventManager.start_new_game()


func _cleanup_cat() -> void:
	# Reparent cat back to NPCManager so it persists across scenes
	if NPCManager.cat and NPCManager.cat.get_parent() != NPCManager:
		NPCManager.cat.reparent(NPCManager)
		print("Cat reparented back to NPCManager")


func _on_options_pressed() -> void:
	# TODO: Open options/settings menu
	print("Options pressed")


func _on_quit_pressed() -> void:
	# Quit the game
	get_tree().quit()


func _setup_cat_testing() -> void:
	if not NPCManager.cat:
		print("ERROR: Cat not found in NPCManager")
		return

	print("Cat found! Current parent: %s" % NPCManager.cat.get_parent().name)
	print("Cat initial position: %s" % NPCManager.cat.position)
	print("Cat global position: %s" % NPCManager.cat.global_position)
	print("Screen dimensions: %s x %s" % [screen_width, screen_height])

	# IMPORTANT: Reparent cat to this Control node so it renders in the UI layer
	var cat = NPCManager.cat
	cat.reparent(self)

	# Position cat at bottom left of screen
	cat.position = Vector2(50, screen_height - 100)
	cat_start_position = cat.position.x

	# Scale up the cat so it's visible (32x32 sprite might be small)
	cat.scale = Vector2(3, 3)

	# Make sure cat is visible
	cat.visible = true
	cat.z_index = 100  # Make sure it's on top

	# Disable physics - prevent cat from falling
	cat.set_physics_process(false)

	# Disable player control and state timer
	cat.set_player_controlled(true)  # This stops the random state timer

	# Stop the state timer completely for title screen testing
	if cat.state_timer:
		cat.state_timer.stop()
		print("Cat state timer stopped for testing")

	# Check if controller exists
	if not cat.controller:
		print("ERROR: Cat controller not found!")
		return

	print("Cat controller found!")
	print("AnimatedSprite2D: %s" % cat.controller.animated_sprite)

	# Start in idle state - will begin moving after idle period
	if cat.controller.animated_sprite:
		idle_timer = 0.0
		cat.controller.play_state("idle")
		print("Cat starting in idle state")
	else:
		print("ERROR: AnimatedSprite2D not found!")

	print("Cat testing setup complete - Position: %s, Scale: %s" % [cat.position, cat.scale])
	print("Controller will handle movement and animations")


func _process(delta: float) -> void:
	if not NPCManager.cat:
		return

	var cat = NPCManager.cat
	var controller = cat.controller

	# Let controller handle movement
	controller.update_movement(delta)

	# Update background parallax based on cat's position
	_update_background_scroll(cat)

	# Handle idle behavior
	if not controller.is_moving():
		_handle_idle_animations(delta)
	else:
		# Reset idle timers when moving
		idle_timer = 0.0
		animation_change_timer = 0.0


func _update_background_scroll(cat: Cat) -> void:
	if not background:
		return

	# Calculate how far the cat has moved from its starting position
	var cat_offset = cat.position.x - cat_start_position

	# Scroll the background based on cat's movement
	# The shader will apply parallax effect at different speeds for each layer
	background.scroll_to(cat_offset)


func _handle_idle_animations(delta: float) -> void:
	# Update timers
	idle_timer += delta
	animation_change_timer += delta

	# Play idle for first 2 seconds, then cycle through other animations
	if idle_timer > 2.0 and animation_change_timer >= animation_change_interval:
		animation_change_timer = 0.0
		_cycle_cat_animation()

	# After idle duration, start moving to opposite edge
	if idle_timer >= idle_duration:
		idle_timer = 0.0
		animation_change_timer = 0.0

		# Calculate target position (opposite edge)
		var target_x = (screen_width - 50) if move_right else 50
		move_right = not move_right

		# Tell controller to move to target
		NPCManager.cat.controller.move_to_position(target_x)
		print("Cat moving to: %s" % ("right edge" if not move_right else "left edge"))


func _cycle_cat_animation() -> void:
	# Move to next animation
	current_animation_index = (current_animation_index + 1) % animation_states.size()
	var new_state = animation_states[current_animation_index]

	# Play the animation
	NPCManager.cat.controller.play_state(new_state)

	print("Testing animation: %s (combo: %s)" % [
		new_state,
		NPCManager.cat.controller.get_animation_sequence(new_state)
	])
