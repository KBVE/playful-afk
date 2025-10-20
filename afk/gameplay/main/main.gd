extends Control

## Main Gameplay Scene for AFK Virtual Pet Game
## This is where the player interacts with their pet and manages resources

@onready var pet_container: Control = $PetContainer
@onready var background: Control = $RollingHillsBackground

# Game state
var is_paused: bool = false

# Cat tracking for parallax
var cat: Cat = null
var cat_start_position: float = 0.0


func _ready() -> void:
	print("Main gameplay scene loaded")

	# Wait a frame to ensure NPCManager is ready
	await get_tree().process_frame

	# Setup the pet
	_setup_pet()

	# Connect to event manager
	EventManager.game_paused.connect(_on_game_paused)


func _setup_pet() -> void:
	# Get the global cat from NPCManager
	print("Checking for cat in NPCManager...")
	if not NPCManager or not NPCManager.cat:
		push_error("Cat not found in NPCManager!")
		return

	cat = NPCManager.cat
	print("Found cat: ", cat)

	# Reparent cat to pet container
	cat.reparent(pet_container)

	# Position cat in the center-bottom of the screen
	var viewport_size = get_viewport_rect().size
	cat.position = Vector2(viewport_size.x / 2, viewport_size.y - 150)
	cat.scale = Vector2(4, 4)  # Make cat bigger for main gameplay

	# Store starting position for parallax
	cat_start_position = cat.position.x

	# Enable physics for the cat
	cat.set_physics_process(false)  # Keep physics disabled for now
	cat.set_player_controlled(false)  # Allow autonomous behavior

	print("Cat setup complete in main scene at position: ", cat.position)


func _on_game_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	print("Game paused: ", paused)


func _process(_delta: float) -> void:
	# Update parallax background based on cat movement
	if cat and background:
		_update_background_scroll()


func _update_background_scroll() -> void:
	if not background or not cat:
		return

	# Calculate how far the cat has moved from its starting position
	var cat_offset = cat.position.x - cat_start_position

	# Scroll the background based on cat's movement
	background.scroll_to(cat_offset)


func _input(event: InputEvent) -> void:
	# Handle escape key to pause
	if event.is_action_pressed("ui_cancel"):
		EventManager.game_paused.emit(not is_paused)
