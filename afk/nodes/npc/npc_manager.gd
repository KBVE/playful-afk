extends Node

## NPCManager - Global NPC Management System
## Provides centralized access to all NPCs in the game, especially the virtual pet
## Access via: NPCManager.cat anywhere in your code

# Virtual Pet Reference
var cat: Cat = null

# NPC References
var warrior: Warrior = null

# NPC Configuration
var cat_scene: PackedScene = preload("res://nodes/npc/cat/cat.tscn")
var warrior_scene: PackedScene = preload("res://nodes/npc/warrior/warrior.tscn")

# UI Sprite Cache - Pre-cloned sprites for UI display (performance optimization)
# These sprites are created once and reused for ChatUI/Modals instead of cloning every time
var ui_sprite_cache: Dictionary = {
	"cat": null,
	"warrior": null
}

# Character Pool for Layer4 NPCs (scroll with Layer4 at 0.9 speed)
const MAX_POOL_SIZE: int = 16
var character_pool: Array[Dictionary] = []
var foreground_container: Node2D = null

# Save/Load data
var npc_save_data: Dictionary = {}


func _ready() -> void:
	# Initialize the cat (virtual pet)
	_initialize_cat()

	# Initialize the warrior NPC
	_initialize_warrior()

	# Initialize character pool (empty slots)
	_initialize_character_pool()

	# Initialize UI sprite cache (create pre-cloned sprites for UI)
	_initialize_ui_sprite_cache()

	# Connect to save/load events
	EventManager.game_saved.connect(_on_game_saved)
	EventManager.game_loaded.connect(_on_game_loaded)

	print("NPCManager initialized - Cat, Warrior, Character Pool, and UI Sprite Cache ready")


## Initialize the cat virtual pet
func _initialize_cat() -> void:
	if cat == null:
		cat = cat_scene.instantiate()
		add_child(cat)

		# Load saved data if available
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])

		print("Cat virtual pet instantiated and ready")


## Save cat data to dictionary
func save_cat_data() -> Dictionary:
	if cat == null:
		return {}

	return {
		"hunger": cat.hunger,
		"happiness": cat.happiness,
		"health": cat.health,
		"level": cat.level,
		"experience": cat.experience,
		"current_state": cat.current_state,
		"position": {
			"x": cat.position.x,
			"y": cat.position.y
		}
	}


## Load cat data from dictionary
func _load_cat_data(data: Dictionary) -> void:
	if cat == null:
		return

	cat.hunger = data.get("hunger", 100.0)
	cat.happiness = data.get("happiness", 100.0)
	cat.health = data.get("health", 100.0)
	cat.level = data.get("level", 1)
	cat.experience = data.get("experience", 0)
	cat.current_state = data.get("current_state", "Idle")

	# Restore position if available
	if data.has("position"):
		var pos = data["position"]
		cat.position = Vector2(pos.get("x", 0), pos.get("y", 0))

	print("Cat data loaded successfully")


## Reset cat to default state
func reset_cat() -> void:
	if cat:
		cat.queue_free()
		cat = null

	_initialize_cat()
	print("Cat has been reset to default state")


## Initialize the warrior NPC
func _initialize_warrior() -> void:
	if warrior == null:
		warrior = warrior_scene.instantiate()
		add_child(warrior)

		# Load saved data if available
		if npc_save_data.has("warrior"):
			_load_warrior_data(npc_save_data["warrior"])

		print("Warrior NPC instantiated and ready")


## Save warrior data to dictionary
func save_warrior_data() -> Dictionary:
	if warrior == null:
		return {}

	return {
		"health": warrior.health,
		"strength": warrior.strength,
		"defense": warrior.defense,
		"level": warrior.level,
		"current_state": warrior.current_state,
		"position": {
			"x": warrior.position.x,
			"y": warrior.position.y
		}
	}


## Load warrior data from dictionary
func _load_warrior_data(data: Dictionary) -> void:
	if warrior == null:
		return

	warrior.health = data.get("health", 100.0)
	warrior.strength = data.get("strength", 50.0)
	warrior.defense = data.get("defense", 50.0)
	warrior.level = data.get("level", 1)
	warrior.current_state = data.get("current_state", "Idle")

	# Restore position if available
	if data.has("position"):
		var pos = data["position"]
		warrior.position = Vector2(pos.get("x", 0), pos.get("y", 0))

	print("Warrior data loaded successfully")


## Reset warrior to default state
func reset_warrior() -> void:
	if warrior:
		warrior.queue_free()
		warrior = null

	_initialize_warrior()
	print("Warrior has been reset to default state")




## Handle game save event
func _on_game_saved(success: bool) -> void:
	if success:
		npc_save_data["cat"] = save_cat_data()
		npc_save_data["warrior"] = save_warrior_data()
		print("NPC data saved")


## Handle game load event
func _on_game_loaded(success: bool) -> void:
	if success:
		if npc_save_data.has("cat"):
			_load_cat_data(npc_save_data["cat"])
		if npc_save_data.has("warrior"):
			_load_warrior_data(npc_save_data["warrior"])
		print("NPC data loaded")


## Get all NPC data for saving to file
func get_save_data() -> Dictionary:
	return {
		"cat": save_cat_data(),
		"warrior": save_warrior_data()
	}


## Load all NPC data from save file
func load_save_data(data: Dictionary) -> void:
	npc_save_data = data

	if npc_save_data.has("cat"):
		_load_cat_data(npc_save_data["cat"])

	if npc_save_data.has("warrior"):
		_load_warrior_data(npc_save_data["warrior"])


## ===== CHARACTER POOL SYSTEM =====
## Manages Layer4 characters that scroll with background Layer4 at 0.9 speed

## Initialize character pool with empty slots
func _initialize_character_pool() -> void:
	character_pool.clear()

	for i in range(MAX_POOL_SIZE):
		character_pool.append({
			"character": null,
			"is_active": false,
			"slot_index": i,
			"position": Vector2.ZERO,
			"character_type": ""  # "warrior", "cat", etc.
		})

	print("Character pool initialized with %d slots" % MAX_POOL_SIZE)


## Set the Layer4Objects container reference (called from main scene)
func set_layer4_container(container: Node2D) -> void:
	foreground_container = container
	print("Layer4Objects container set - characters will scroll with Layer4 at 0.9 speed")


## Add warrior to pool at a specific slot
func add_warrior_to_pool(slot_index: int, position: Vector2 = Vector2.ZERO, activate: bool = false, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> Warrior:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		push_error("Invalid slot index: %d" % slot_index)
		return null

	# Create a new warrior instance
	var new_warrior = warrior_scene.instantiate() as Warrior

	if _add_character_to_slot(new_warrior, slot_index, position, activate, "warrior", movement_bounds):
		return new_warrior
	else:
		new_warrior.queue_free()
		return null


## Internal: Add any character to a slot
func _add_character_to_slot(character: Node2D, slot_index: int, position: Vector2, activate: bool, char_type: String, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> bool:
	if not foreground_container:
		push_error("ForegroundCharacters container not set! Call set_layer4_container() first.")
		return false

	var slot = character_pool[slot_index]

	# Remove existing character if any
	if slot["character"] != null:
		push_warning("Slot %d already occupied, replacing character" % slot_index)
		_remove_character_from_slot(slot_index)

	# Add character to slot
	slot["character"] = character
	slot["position"] = position
	slot["is_active"] = activate
	slot["character_type"] = char_type

	# Add to scene (in Layer4Objects - will scroll with Layer4)
	foreground_container.add_child(character)
	character.position = position
	character.visible = activate

	# Configure character
	if not activate:
		_deactivate_character(character)
	else:
		_activate_character(character, movement_bounds)

	print("Added %s to pool slot %d (active: %s)" % [char_type, slot_index, activate])
	return true


## Activate a character in a slot
func activate_pool_character(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		return false

	var slot = character_pool[slot_index]
	if slot["character"] == null or slot["is_active"]:
		return false

	slot["is_active"] = true
	var character = slot["character"]
	character.visible = true
	_activate_character(character)

	print("Activated character in slot %d" % slot_index)
	return true


## Deactivate a character in a slot
func deactivate_pool_character(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_POOL_SIZE:
		return false

	var slot = character_pool[slot_index]
	if slot["character"] == null or not slot["is_active"]:
		return false

	slot["is_active"] = false
	var character = slot["character"]
	character.visible = false
	_deactivate_character(character)

	print("Deactivated character in slot %d" % slot_index)
	return true


## Internal: Activate character logic
func _activate_character(character: Node2D, movement_bounds: Vector2 = Vector2(100.0, 1052.0)) -> void:
	# Enable physics
	if character.has_method("set_physics_process"):
		character.set_physics_process(true)

	# Start AI if it's a Warrior with custom movement bounds
	if character is Warrior and character.controller:
		character.controller.start_random_movement(movement_bounds.x, movement_bounds.y)

	# Enable state timer
	if character.has_node("StateTimer"):
		var timer = character.get_node("StateTimer")
		if timer is Timer and timer.is_stopped():
			timer.start()


## Internal: Deactivate character logic
func _deactivate_character(character: Node2D) -> void:
	# Disable physics
	if character.has_method("set_physics_process"):
		character.set_physics_process(false)

	# Stop AI if it's a Warrior
	if character is Warrior and character.controller:
		character.controller.stop_random_movement()

	# Stop state timer
	if character.has_node("StateTimer"):
		var timer = character.get_node("StateTimer")
		if timer is Timer:
			timer.stop()


## Internal: Remove character from slot
func _remove_character_from_slot(slot_index: int) -> void:
	var slot = character_pool[slot_index]
	if slot["character"] != null:
		slot["character"].queue_free()
		slot["character"] = null
		slot["is_active"] = false
		slot["character_type"] = ""


## Update all active pooled characters
func update_pool_characters(delta: float) -> void:
	for slot in character_pool:
		if slot["is_active"] and slot["character"] != null:
			var character = slot["character"]
			# Update Warrior controllers
			if character is Warrior and character.controller:
				character.controller.update_movement(delta)


## Get active character count
func get_active_pool_count() -> int:
	var count = 0
	for slot in character_pool:
		if slot["is_active"]:
			count += 1
	return count


## Get all active pooled characters
func get_active_pool_characters() -> Array:
	var active = []
	for slot in character_pool:
		if slot["is_active"] and slot["character"] != null:
			active.append(slot["character"])
	return active


## ===== UI SPRITE CACHE SYSTEM =====
## Pre-cloned sprites for UI display (ChatUI, Modals, etc.)
## Performance optimization - avoids cloning sprites every time

## Initialize UI sprite cache - create pre-cloned sprites for each NPC type
func _initialize_ui_sprite_cache() -> void:
	# Create cat UI sprite
	if cat and cat.has_node("AnimatedSprite2D"):
		var cat_sprite = cat.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if cat_sprite:
			var cat_ui_sprite = cat_sprite.duplicate() as AnimatedSprite2D
			ui_sprite_cache["cat"] = cat_ui_sprite
			print("NPCManager: Cat UI sprite cached")

	# Create warrior UI sprite
	if warrior and warrior.has_node("AnimatedSprite2D"):
		var warrior_sprite = warrior.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if warrior_sprite:
			var warrior_ui_sprite = warrior_sprite.duplicate() as AnimatedSprite2D
			ui_sprite_cache["warrior"] = warrior_ui_sprite
			print("NPCManager: Warrior UI sprite cached")

	print("NPCManager: UI sprite cache initialized")


## Get cached UI sprite for an NPC type (e.g., "cat", "warrior")
## Returns the pre-cloned sprite ready to be added to UI
## IMPORTANT: Do NOT duplicate or modify this sprite - use it directly
func get_ui_sprite(npc_type: String) -> AnimatedSprite2D:
	if ui_sprite_cache.has(npc_type) and ui_sprite_cache[npc_type] != null:
		return ui_sprite_cache[npc_type]

	push_warning("NPCManager: No UI sprite cached for type: ", npc_type)
	return null


## Get NPC type name from NPC node (used to look up cached sprite)
func get_npc_type(npc: Node2D) -> String:
	if npc is Cat:
		return "cat"
	elif npc is Warrior:
		return "warrior"
	else:
		return ""
