extends Node
class_name EmojiManager

## Manages emoji introductions for NPCs with index-based assignment
## Different entity types get different emoji sets
## Randomized timing for each NPC

## Emoji sets for different entity types
const NPC_EMOJIS: Array[String] = [
	"👋",  # Index 0: Wave
	"😊",  # Index 1: Smile
	"🎮",  # Index 2: Game
	"🌟",  # Index 3: Star
	"💪",  # Index 4: Flex
	"🎯",  # Index 5: Target
	"🔥",  # Index 6: Fire
	"⚡",  # Index 7: Lightning
	"🌈",  # Index 8: Rainbow
	"🎨",  # Index 9: Art
]

const WARRIOR_EMOJIS: Array[String] = [
	"⚔️",  # Index 0: Crossed Swords
	"🛡️",  # Index 1: Shield
	"💪",  # Index 2: Flex
	"🔥",  # Index 3: Fire
	"⚡",  # Index 4: Lightning
	"🏹",  # Index 5: Bow (even warriors can appreciate archery)
	"🎖️",  # Index 6: Medal
	"👊",  # Index 7: Fist
	"⭐",  # Index 8: Star
	"🗡️",  # Index 9: Dagger
]

const ARCHER_EMOJIS: Array[String] = [
	"🏹",  # Index 0: Bow and Arrow
	"🎯",  # Index 1: Target
	"👁️",  # Index 2: Eye (for precision)
	"🌟",  # Index 3: Star
	"🦅",  # Index 4: Eagle
	"🍃",  # Index 5: Leaf (nature/stealth)
	"💨",  # Index 6: Wind
	"🎪",  # Index 7: Circus (agility)
	"🔭",  # Index 8: Telescope (vision)
	"🌙",  # Index 9: Moon
]

## Timing configuration
const MIN_INTRO_DELAY: float = 1.0  # Minimum delay before first intro
const MAX_INTRO_DELAY: float = 5.0  # Maximum delay before first intro
const MIN_REPEAT_INTERVAL: float = 8.0  # Minimum time between repeats
const MAX_REPEAT_INTERVAL: float = 20.0  # Maximum time between repeats

## Tracked entities
var entity_data: Dictionary = {}  # entity_instance -> {type, index, timer, bubble}


## Register an entity for emoji introductions
func register_entity(entity: Node2D, entity_type: String, entity_index: int) -> void:
	if entity_data.has(entity):
		push_warning("EmojiManager: Entity already registered: %s" % entity)
		return

	# Create chat bubble for this entity
	var bubble = preload("res://nodes/ui/chat/bubble/chat_bubble.tscn").instantiate()

	# Add bubble to the scene (as child of main scene, not entity, for proper z-index)
	if entity.get_tree():
		entity.get_tree().root.add_child(bubble)
		bubble.set_parent_entity(entity)

	# Create timer for this entity
	var timer = Timer.new()
	add_child(timer)
	timer.one_shot = false
	timer.timeout.connect(func(): _on_entity_timer_timeout(entity))

	# Store entity data
	entity_data[entity] = {
		"type": entity_type,
		"index": entity_index,
		"timer": timer,
		"bubble": bubble,
		"intro_shown": false
	}

	# Start with random initial delay
	var initial_delay = randf_range(MIN_INTRO_DELAY, MAX_INTRO_DELAY)
	timer.start(initial_delay)

	print("EmojiManager: Registered %s (type: %s, index: %d)" % [entity, entity_type, entity_index])


## Unregister an entity
func unregister_entity(entity: Node2D) -> void:
	if not entity_data.has(entity):
		return

	var data = entity_data[entity]

	# Clean up timer
	if data.timer:
		data.timer.stop()
		data.timer.queue_free()

	# Clean up bubble
	if data.bubble and is_instance_valid(data.bubble):
		data.bubble.queue_free()

	# Remove from tracking
	entity_data.erase(entity)

	print("EmojiManager: Unregistered %s" % entity)


## Called when an entity's timer expires
func _on_entity_timer_timeout(entity: Node2D) -> void:
	if not entity_data.has(entity):
		return

	if not is_instance_valid(entity):
		unregister_entity(entity)
		return

	var data = entity_data[entity]

	# Get the emoji for this entity
	var emoji = _get_emoji_for_entity(data.type, data.index)

	# Show the bubble
	if data.bubble and is_instance_valid(data.bubble):
		data.bubble.show_bubble(emoji)

	# Mark intro as shown
	data.intro_shown = true

	# Set up next display with random interval
	var next_interval = randf_range(MIN_REPEAT_INTERVAL, MAX_REPEAT_INTERVAL)
	data.timer.start(next_interval)


## Get the appropriate emoji for an entity
func _get_emoji_for_entity(entity_type: String, entity_index: int) -> String:
	var emoji_set: Array[String] = []

	# Select emoji set based on type
	match entity_type.to_lower():
		"warrior":
			emoji_set = WARRIOR_EMOJIS
		"archer":
			emoji_set = ARCHER_EMOJIS
		_:
			emoji_set = NPC_EMOJIS

	# Use modulo to wrap index if it exceeds array size
	var emoji_index = entity_index % emoji_set.size()
	return emoji_set[emoji_index]


## Clean up all entities
func clear_all() -> void:
	var entities_to_remove = entity_data.keys()
	for entity in entities_to_remove:
		unregister_entity(entity)


func _exit_tree() -> void:
	clear_all()
