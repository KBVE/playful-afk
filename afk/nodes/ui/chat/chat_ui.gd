extends Control
class_name ChatUI

## Chat UI for NPC dialogue
## Left side: NPC portrait (20%)
## Right side: Dialogue box with text and buttons (80%)

## Signals
signal dialogue_option_selected(option_index: int)
signal dialogue_closed

## Node references
@onready var npc_portrait_panel: Panel = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel
@onready var npc_name_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/NPCNameMargin/NPCNameLabel
@onready var npc_portrait_container: CenterContainer = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/NPCPortraitContainer

## Stats display labels
@onready var hp_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/HPLabel
@onready var mana_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/ManaLabel
@onready var energy_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/EnergyLabel
@onready var hunger_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/HungerLabel
@onready var emotion_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/EmotionLabel
@onready var attack_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/AttackLabel
@onready var defense_label: Label = $CenterContainer/Panel/MainVBox/HBoxContainer/NPCPortraitPanel/VBoxContainer/StatsMargin/NPCStatsContainer/DefenseLabel

@onready var dialogue_panel: Panel = $CenterContainer/Panel/MainVBox/HBoxContainer/DialoguePanel
@onready var dialogue_text: RichTextLabel = $CenterContainer/Panel/MainVBox/HBoxContainer/DialoguePanel/VBoxContainer/MarginContainer/DialogueText
@onready var button_container: VBoxContainer = $CenterContainer/Panel/MainVBox/HBoxContainer/DialoguePanel/VBoxContainer/BottomContainer/ButtonContainer
@onready var close_button: Button = $CenterContainer/Panel/MainVBox/HBoxContainer/DialoguePanel/VBoxContainer/BottomContainer/ButtonContainer/CloseButton
@onready var x_close_button: Button = $CenterContainer/Panel/MainVBox/TitleBar/XCloseButton

## Current NPC data
var current_npc_name: String = ""
var current_npc_sprite: AnimatedSprite2D = null
var current_npc_stats: NPCStats = null
var current_npc: Node2D = null  # Reference to the NPC for state checking

## Animation properties
var animation_duration: float = 0.3  # Duration for fade in/out
var is_animating: bool = false
var typewriter_speed: float = 0.03  # Seconds per character
var is_typing: bool = false


func _ready() -> void:
	# Connect close buttons (both use the same handler)
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

	if x_close_button:
		x_close_button.pressed.connect(_on_close_button_pressed)
		x_close_button.mouse_entered.connect(_on_x_button_hover_enter)
		x_close_button.mouse_exited.connect(_on_x_button_hover_exit)

	# Start hidden with alpha 0
	visible = false
	modulate.a = 0.0


func _process(delta: float) -> void:
	# Update stats display in realtime while dialogue is visible
	if visible and current_npc_stats:
		_update_stats_display()


## Show the chat UI with NPC (DOES NOT make visible - caller must do that)
## Uses cached UI sprite from NPCManager for better performance
func show_dialogue(npc_name: String, npc: Node2D = null) -> void:
	current_npc_name = npc_name
	current_npc = npc  # Store NPC reference for state checking

	# Extract NPC stats if available
	current_npc_stats = null

	if npc and "stats" in npc and npc.stats:
		current_npc_stats = npc.stats
		_update_stats_display()
	else:
		_clear_stats_display()

	# Set NPC name (use generated name from stats if available)
	if npc_name_label:
		if current_npc_stats and not current_npc_stats.npc_name.is_empty():
			npc_name_label.text = current_npc_stats.npc_name
		else:
			npc_name_label.text = npc_name
	else:
		push_error("ChatUI: npc_name_label is null!")

	# Remove previous NPC sprite from UI (but don't free it - it's cached)
	if current_npc_sprite and npc_portrait_container:
		npc_portrait_container.remove_child(current_npc_sprite)
		current_npc_sprite = null

	# Get cached UI sprite from NPCManager (no duplication!)
	if npc and npc_portrait_container:
		var npc_type = NPCManager.get_npc_type(npc)
		if npc_type != "":
			current_npc_sprite = NPCManager.get_ui_sprite(npc_type)
			if current_npc_sprite:
				# Add cached sprite to UI (will be removed, not freed, when dialogue closes)
				npc_portrait_container.add_child(current_npc_sprite)
				current_npc_sprite.play("idle")  # Play idle animation
				current_npc_sprite.scale = Vector2(3, 3)  # Scale up for portrait
			else:
				push_warning("ChatUI: No cached UI sprite found for %s" % npc_type)

	# Clear previous dialogue
	if dialogue_text:
		dialogue_text.text = ""


## Fade in the chat UI with animation
func fade_in() -> void:
	if is_animating:
		return

	is_animating = true
	visible = true

	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished

	is_animating = false


## Fade out the chat UI with animation
func fade_out() -> void:
	if is_animating:
		return

	is_animating = true

	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished

	visible = false
	is_animating = false


## Hide the chat UI (with fade animation)
func hide_dialogue() -> void:
	# Fade out first
	await fade_out()

	current_npc_name = ""
	current_npc_stats = null
	current_npc = null  # Clear NPC reference

	# Remove cached sprite from UI (but don't free it - it's cached in NPCManager)
	if current_npc_sprite and npc_portrait_container:
		npc_portrait_container.remove_child(current_npc_sprite)
		current_npc_sprite = null


## Update stats display labels from current_npc_stats
func _update_stats_display() -> void:
	if not current_npc_stats:
		_clear_stats_display()
		return

	# Update HP
	if hp_label:
		hp_label.text = "HP: %d/%d" % [current_npc_stats.hp, current_npc_stats.max_hp]

	# Update Mana
	if mana_label:
		mana_label.text = "Mana: %d/%d" % [current_npc_stats.mana, current_npc_stats.max_mana]

	# Update Energy
	if energy_label:
		energy_label.text = "Energy: %d/%d" % [current_npc_stats.energy, current_npc_stats.max_energy]

	# Update Hunger
	if hunger_label:
		hunger_label.text = "Hunger: %d/100" % current_npc_stats.hunger

	# Update Emotion
	if emotion_label:
		var emotion_str = current_npc_stats.get_emotion_string()
		emotion_label.text = "Emotion: %s" % emotion_str

	# Update Attack
	if attack_label:
		attack_label.text = "Attack: %d" % current_npc_stats.attack

	# Update Defense
	if defense_label:
		defense_label.text = "Defense: %d" % current_npc_stats.defense


## Clear stats display (show default values)
func _clear_stats_display() -> void:
	if hp_label:
		hp_label.text = "HP: --/--"
	if mana_label:
		mana_label.text = "Mana: --/--"
	if energy_label:
		energy_label.text = "Energy: --/--"
	if hunger_label:
		hunger_label.text = "Hunger: --/--"
	if emotion_label:
		emotion_label.text = "Emotion: --"
	if attack_label:
		attack_label.text = "Attack: --"
	if defense_label:
		defense_label.text = "Defense: --"


## Set the dialogue text with typewriter effect
func set_dialogue_text(text: String) -> void:
	if not dialogue_text:
		return

	# Add state-based message if NPC has a current_state
	var full_text = text
	if current_npc and "current_state" in current_npc:
		var state_message = _get_state_message(current_npc.current_state)
		if not state_message.is_empty():
			full_text = text + "\n\n" + state_message

	# Start typewriter effect
	_typewriter_effect(full_text)


## Get state-based message from NPCState enum
func _get_state_message(state: int) -> String:
	# Map NPCState enum to descriptive messages
	match state:
		NPCManager.NPCState.IDLE:
			return "[i](Currently idle)[/i]"
		NPCManager.NPCState.WALKING:
			return "[i](Currently walking around)[/i]"
		NPCManager.NPCState.ATTACKING:
			return "[i](Currently attacking!)[/i]"
		NPCManager.NPCState.WANDERING:
			return "[i](Currently wandering)[/i]"
		NPCManager.NPCState.COMBAT:
			return "[i](Currently in combat!)[/i]"
		NPCManager.NPCState.RETREATING:
			return "[i](Currently retreating from danger)[/i]"
		NPCManager.NPCState.PURSUING:
			return "[i](Currently pursuing a target)[/i]"
		NPCManager.NPCState.HURT:
			return "[i](Currently hurt and recovering)[/i]"
		NPCManager.NPCState.DAMAGED:
			return "[i](Just took damage!)[/i]"
		NPCManager.NPCState.DEAD:
			return "[i](Deceased)[/i]"
		_:
			return "[i](Unknown state: %d)[/i]" % state


## Typewriter effect for dialogue text
func _typewriter_effect(full_text: String) -> void:
	if is_typing:
		return

	is_typing = true
	dialogue_text.visible_ratio = 0.0
	dialogue_text.text = full_text

	# Calculate total duration based on text length
	var char_count = full_text.length()
	var total_duration = char_count * typewriter_speed

	# Animate the visible_ratio from 0 to 1
	var tween = create_tween()
	tween.tween_property(dialogue_text, "visible_ratio", 1.0, total_duration).set_trans(Tween.TRANS_LINEAR)
	await tween.finished

	is_typing = false


## Add a dialogue option button (for future branching dialogue)
func add_dialogue_option(option_text: String, option_index: int) -> void:
	var button = Button.new()
	button.text = option_text
	button.pressed.connect(func(): _on_dialogue_option_pressed(option_index))

	# Insert before close button
	if button_container:
		var close_button_index = button_container.get_child_count() - 1
		button_container.add_child(button)
		button_container.move_child(button, close_button_index)


## Clear all dialogue option buttons
func clear_dialogue_options() -> void:
	if not button_container:
		return

	# Remove all buttons except the close button
	for child in button_container.get_children():
		if child != close_button:
			child.queue_free()


## Handle dialogue option button pressed
func _on_dialogue_option_pressed(option_index: int) -> void:
	dialogue_option_selected.emit(option_index)


## Handle X button hover enter
func _on_x_button_hover_enter() -> void:
	if x_close_button:
		var tween = create_tween()
		tween.tween_property(x_close_button, "scale", Vector2(1.1, 1.1), 0.1)


## Handle X button hover exit
func _on_x_button_hover_exit() -> void:
	if x_close_button:
		var tween = create_tween()
		tween.tween_property(x_close_button, "scale", Vector2(1.0, 1.0), 0.1)


## Handle close button pressed (both X button and regular close button)
func _on_close_button_pressed() -> void:
	# Hide with fade animation first, then emit signal
	await hide_dialogue()
	dialogue_closed.emit()
