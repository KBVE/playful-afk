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

	# Test NPCDataWarehouse (Rust GDExtension)
	_test_npc_data_warehouse()

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

	# Check if controller exists
	if not cat.controller:
		print("ERROR: Cat controller not found!")
		return


	# Start in idle state - will begin moving after idle period
	if cat.controller.animated_sprite:
		idle_timer = 0.0
		cat.controller.play_state("idle")
	else:
		print("ERROR: AnimatedSprite2D not found!")



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


func _cycle_cat_animation() -> void:
	# Move to next animation
	current_animation_index = (current_animation_index + 1) % animation_states.size()
	var new_state = animation_states[current_animation_index]

	# Play the animation
	NPCManager.cat.controller.play_state(new_state)


func _test_npc_data_warehouse() -> void:
	print("=== NPCDataWarehouse Test Start ===")

	# Test pool registration
	NPCDataWarehouse.register_pool("warrior", 10, "res://nodes/npc/warrior/warrior.tscn")
	NPCDataWarehouse.register_pool("archer", 8, "res://nodes/npc/archer/archer.tscn")
	print("✓ Registered 2 pools")

	# Test NPC storage
	var test_ulid_1 = "01HZQK4YX9ABCDEF1234567890"
	var test_ulid_2 = "01HZQK4YX9ABCDEF0987654321"
	var npc_data_1 = '{"type":"warrior","hp":100,"position":[50,50]}'
	var npc_data_2 = '{"type":"archer","hp":80,"position":[100,100]}'

	NPCDataWarehouse.store_npc(test_ulid_1, npc_data_1)
	NPCDataWarehouse.store_npc(test_ulid_2, npc_data_2)
	print("✓ Stored 2 NPCs")

	# Test NPC retrieval
	var retrieved_1 = NPCDataWarehouse.get_npc(test_ulid_1)
	var retrieved_2 = NPCDataWarehouse.get_npc(test_ulid_2)
	print("✓ Retrieved NPCs: [%s] and [%s]" % [retrieved_1, retrieved_2])

	# Test has_npc
	var has_1 = NPCDataWarehouse.has_npc(test_ulid_1)
	var has_missing = NPCDataWarehouse.has_npc("missing_ulid")
	print("✓ Has checks: warrior=%s, missing=%s" % [has_1, has_missing])

	# Test AI state storage
	var ai_state = '{"target":"enemy","behavior":"aggressive"}'
	NPCDataWarehouse.store_ai_state(test_ulid_1, ai_state)
	var retrieved_ai = NPCDataWarehouse.get_ai_state(test_ulid_1)
	print("✓ AI state stored and retrieved: %s" % retrieved_ai)

	# Test combat state storage
	var combat_state = '{"in_combat":true,"target_ulid":"enemy_123"}'
	NPCDataWarehouse.store_combat_state(test_ulid_1, combat_state)
	var retrieved_combat = NPCDataWarehouse.get_combat_state(test_ulid_1)
	print("✓ Combat state stored and retrieved: %s" % retrieved_combat)

	# Test diagnostic counts before sync
	var write_count = NPCDataWarehouse.write_store_count()
	var read_count = NPCDataWarehouse.read_store_count()
	var total = NPCDataWarehouse.total_entries()
	print("✓ Before sync - write_count=%d, read_count=%d, total=%d" % [write_count, read_count, total])

	# Test manual sync
	NPCDataWarehouse.sync()
	print("✓ Manual sync triggered")

	# Test diagnostic counts after sync
	write_count = NPCDataWarehouse.write_store_count()
	read_count = NPCDataWarehouse.read_store_count()
	print("✓ After sync - write_count=%d, read_count=%d" % [write_count, read_count])

	# Test remove
	var removed = NPCDataWarehouse.remove_npc(test_ulid_2)
	print("✓ Removed NPC: %s" % removed)

	# Test clear
	NPCDataWarehouse.clear_all()
	var final_total = NPCDataWarehouse.total_entries()
	print("✓ Cleared all data, final total: %d" % final_total)

	# Test NPCState bitflags
	print("\n=== Testing NPCState Bitflags ===")

	var idle = NPCDataWarehouse.get_state("IDLE")
	var melee = NPCDataWarehouse.get_state("MELEE")
	var ally = NPCDataWarehouse.get_state("ALLY")
	print("✓ Got state constants: IDLE=%d, MELEE=%d, ALLY=%d" % [idle, melee, ally])

	# Combine states to create an idle melee ally
	var warrior_idle = NPCDataWarehouse.combine_states(idle, melee)
	warrior_idle = NPCDataWarehouse.combine_states(warrior_idle, ally)
	print("✓ Combined states: IDLE | MELEE | ALLY = %d" % warrior_idle)
	print("  → String representation: %s" % NPCDataWarehouse.state_to_string(warrior_idle))

	# Check if flags are set
	var has_melee = NPCDataWarehouse.has_state_flag(warrior_idle, "MELEE")
	var has_ranged = NPCDataWarehouse.has_state_flag(warrior_idle, "RANGED")
	print("✓ Flag checks: has_melee=%s, has_ranged=%s" % [has_melee, has_ranged])

	# Modify states
	var walking_warrior = NPCDataWarehouse.remove_state_flag(warrior_idle, "IDLE")
	walking_warrior = NPCDataWarehouse.add_state_flag(walking_warrior, "WALKING")
	print("✓ Modified state: %s" % NPCDataWarehouse.state_to_string(walking_warrior))

	# Test attacking monster
	var attacking = NPCDataWarehouse.get_state("ATTACKING")
	var monster = NPCDataWarehouse.get_state("MONSTER")
	var ranged = NPCDataWarehouse.get_state("RANGED")
	var monster_attacking = NPCDataWarehouse.combine_states(attacking, monster)
	monster_attacking = NPCDataWarehouse.combine_states(monster_attacking, ranged)
	print("✓ Monster state: %s" % NPCDataWarehouse.state_to_string(monster_attacking))

	# Test binary ULID generation (MAXIMUM PERFORMANCE!)
	print("\n=== Testing Binary ULID Generation ===")
	var ulid_bytes = NPCDataWarehouse.generate_ulid_bytes()
	print("✓ Generated binary ULID: %d bytes" % ulid_bytes.size())
	var ulid_hex = NPCDataWarehouse.ulid_bytes_to_hex(ulid_bytes)
	print("✓ Converted to hex: %s" % ulid_hex)
	var ulid_bytes_back = NPCDataWarehouse.ulid_hex_to_bytes(ulid_hex)
	print("✓ Converted back to bytes: %d bytes" % ulid_bytes_back.size())
	print("✓ Round-trip successful: %s" % (ulid_bytes == ulid_bytes_back))

	# Test legacy string ULID (for backwards compatibility)
	var ulid_string = NPCDataWarehouse.generate_ulid()
	print("✓ Generated string ULID: %s" % ulid_string)
	print("✓ ULID is valid: %s" % NPCDataWarehouse.validate_ulid(ulid_string))

	# Test Rust combat logic methods
	print("\n=== Testing Rust Combat Logic ===")

	# Test damage calculation
	var damage = NPCDataWarehouse.calculate_damage(50.0, 20.0)
	print("✓ Damage calculation: attack=50, defense=20 → damage=%0.1f" % damage)

	# Test hostility checks
	var warrior_state = NPCDataWarehouse.combine_states(
		NPCDataWarehouse.get_state("IDLE"),
		NPCDataWarehouse.combine_states(
			NPCDataWarehouse.get_state("MELEE"),
			NPCDataWarehouse.get_state("ALLY")
		)
	)
	var goblin_state = NPCDataWarehouse.combine_states(
		NPCDataWarehouse.get_state("IDLE"),
		NPCDataWarehouse.combine_states(
			NPCDataWarehouse.get_state("MELEE"),
			NPCDataWarehouse.get_state("MONSTER")
		)
	)
	var chicken_state = NPCDataWarehouse.combine_states(
		NPCDataWarehouse.get_state("IDLE"),
		NPCDataWarehouse.get_state("PASSIVE")
	)

	print("✓ Warrior vs Goblin hostile: %s" % NPCDataWarehouse.are_hostile(warrior_state, goblin_state))
	print("✓ Warrior vs Chicken hostile: %s" % NPCDataWarehouse.are_hostile(warrior_state, chicken_state))
	print("✓ Warrior can attack: %s" % NPCDataWarehouse.can_attack(warrior_state))
	print("✓ Goblin can attack: %s" % NPCDataWarehouse.can_attack(goblin_state))

	# Test combat type detection
	var combat_type = NPCDataWarehouse.get_combat_type(warrior_state)
	print("✓ Warrior combat type: %d (MELEE=%d)" % [combat_type, NPCDataWarehouse.get_state("MELEE")])

	# Test state transitions
	print("\n=== Testing Rust State Transitions ===")

	var peaceful_state = warrior_state
	print("  Starting state: %s" % NPCDataWarehouse.state_to_string(peaceful_state))

	var entered_combat_state = NPCDataWarehouse.enter_combat_state(peaceful_state)
	print("  → Enter combat: %s" % NPCDataWarehouse.state_to_string(entered_combat_state))
	print("  → Is in combat: %s" % NPCDataWarehouse.is_in_combat(entered_combat_state))

	var attacking_state = NPCDataWarehouse.start_attack(entered_combat_state)
	print("  → Start attack: %s" % NPCDataWarehouse.state_to_string(attacking_state))

	var stopped_attack = NPCDataWarehouse.stop_attack(attacking_state)
	print("  → Stop attack: %s" % NPCDataWarehouse.state_to_string(stopped_attack))

	var exited_combat = NPCDataWarehouse.exit_combat_state(stopped_attack)
	print("  → Exit combat: %s" % NPCDataWarehouse.state_to_string(exited_combat))

	# Test movement transitions
	var walking = NPCDataWarehouse.start_walking(peaceful_state)
	print("  → Start walking: %s" % NPCDataWarehouse.state_to_string(walking))

	var stopped = NPCDataWarehouse.stop_walking(walking)
	print("  → Stop walking: %s" % NPCDataWarehouse.state_to_string(stopped))

	# Test death
	var dead_state = NPCDataWarehouse.mark_dead(attacking_state)
	print("  → Mark dead: %s" % NPCDataWarehouse.state_to_string(dead_state))
	print("  → Dead warrior can attack: %s" % NPCDataWarehouse.can_attack(dead_state))

	print("\n=== NPCDataWarehouse Test Complete ===")
