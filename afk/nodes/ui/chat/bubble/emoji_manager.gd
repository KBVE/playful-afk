extends Node
class_name EmojiManager

## Manages emoji bubbles for NPCs with pooling and state-based display
## Uses a pool of 4 reusable emoji bubbles
## Shows emojis 10% of the time on NPC state changes

## State-to-Emoji mapping
const STATE_EMOJIS: Dictionary = {
	NPCManager.NPCState.IDLE: "😌",       # Relaxed face
	NPCManager.NPCState.WALKING: "🚶",    # Walking person
	NPCManager.NPCState.ATTACKING: "⚔️",  # Crossed swords
	NPCManager.NPCState.COMBAT: "💥",     # Collision/combat
	NPCManager.NPCState.DAMAGED: "😵",    # Dizzy face (just got hit)
	NPCManager.NPCState.DEAD: "💀",       # Skull
	NPCManager.NPCState.WANDERING: "🤔",  # Thinking face
	NPCManager.NPCState.RETREATING: "😰", # Anxious/scared face
	NPCManager.NPCState.PURSUING: "😠",   # Angry face (chasing)
}

## Default emoji set (fallback if NPC doesn't have EMOJIS constant)
const DEFAULT_EMOJIS: Array[String] = ["😊", "🎯", "⭐", "💫"]

## Emoji bubble pool (4 reusable bubbles)
const POOL_SIZE: int = 8
var emoji_bubble_pool: Array[Node] = []
var active_bubbles: Dictionary = {}  # entity -> bubble

## Bubble scene
var bubble_scene: PackedScene = preload("res://nodes/ui/chat/bubble/chat_bubble.tscn")


func _ready() -> void:
	# Pre-allocate emoji bubble pool
	_initialize_bubble_pool()


## Initialize the emoji bubble pool
func _initialize_bubble_pool() -> void:
	for i in range(POOL_SIZE):
		var bubble = bubble_scene.instantiate()
		bubble.visible = false

		# Add to scene tree (as child of main scene root for proper z-index)
		# Use call_deferred to avoid "parent busy setting up children" error
		if get_tree():
			get_tree().root.add_child.call_deferred(bubble)

		emoji_bubble_pool.append(bubble)


## Show emoji for NPC based on state change
## Called by NPCManager when an NPC changes state
## Always tries to show, but silently fails if pool is full
func try_show_state_emoji(npc: Node2D, old_state: int, new_state: int) -> void:
	# Get emoji for the new state (or fall back to entity-specific emoji)
	var emoji = _get_emoji_for_state(npc, new_state)

	# Show the emoji (will silently fail if pool is full)
	show_emoji(npc, emoji)


## Show a specific emoji for an NPC
func show_emoji(npc: Node2D, emoji: String) -> void:
	if not is_instance_valid(npc):
		return

	# Get available bubble from pool
	var bubble = _get_available_bubble()
	if not bubble:
		# Pool is full - silently fail (this is normal/expected)
		return

	# Mark bubble as active for this NPC
	active_bubbles[npc] = bubble

	# Connect to bubble's hidden signal (one-shot connection)
	if not bubble.bubble_hidden.is_connected(_on_bubble_hidden):
		bubble.bubble_hidden.connect(_on_bubble_hidden.bind(npc, bubble), CONNECT_ONE_SHOT)

	# Set up the bubble
	bubble.set_parent_entity(npc)
	bubble.show_bubble(emoji)


## Get an available bubble from the pool
func _get_available_bubble() -> Node:
	# Find first inactive bubble
	for bubble in emoji_bubble_pool:
		if bubble.visible == false:
			return bubble

	# All bubbles in use - reuse the oldest one
	if emoji_bubble_pool.size() > 0:
		return emoji_bubble_pool[0]

	return null


## Called when a bubble finishes hiding
func _on_bubble_hidden(npc: Node2D, bubble: Node) -> void:
	# Return bubble to pool
	if active_bubbles.get(npc) == bubble:
		active_bubbles.erase(npc)

	# Ensure bubble is truly hidden
	bubble.visible = false


## Get appropriate emoji for NPC state
func _get_emoji_for_state(npc: Node2D, state: int) -> String:
	# Try state-based emoji first
	if STATE_EMOJIS.has(state):
		return STATE_EMOJIS[state]

	# Fall back to entity-type specific emoji
	return _get_emoji_for_entity_type(npc)


## Get emoji based on NPC type
func _get_emoji_for_entity_type(npc: Node2D) -> String:
	var emoji_set: Array[String] = DEFAULT_EMOJIS  # Default

	# Try to get EMOJIS constant from NPC's script
	if npc and "EMOJIS" in npc:
		emoji_set = npc.EMOJIS
	elif npc and npc.get_script():
		# Fallback: try to get it from the script's constants
		var script = npc.get_script()
		if script and script.has_script_method("get_script_constant_map"):
			var constants = script.get_script_constant_map()
			if "EMOJIS" in constants:
				emoji_set = constants["EMOJIS"]

	# Random emoji from set
	return emoji_set[randi() % emoji_set.size()]


## Clean up all active bubbles
func clear_all() -> void:
	active_bubbles.clear()
	for bubble in emoji_bubble_pool:
		bubble.visible = false


func _exit_tree() -> void:
	clear_all()
	# Clean up pooled bubbles
	for bubble in emoji_bubble_pool:
		if is_instance_valid(bubble):
			bubble.queue_free()
	emoji_bubble_pool.clear()
