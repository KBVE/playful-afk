extends Resource
class_name NPCStats

## NPCStats - Structured stat system for all NPCs
## Provides type-safe stat management with easy dictionary conversion
## Can be saved/loaded and serialized for persistence

## ===== EMOTION ENUM =====
enum Emotion {
	HAPPY,      # Positive, content
	NEUTRAL,    # Calm, balanced
	SAD,        # Negative, unhappy
	ANGRY,      # Aggressive, frustrated
	EXCITED,    # Energetic, enthusiastic
	TIRED,      # Low energy, sleepy
	SCARED,     # Fearful, anxious
	RELAXED     # Peaceful, at ease
}

## ===== CORE STATS =====

## Health Points - Character's health (0 = dead)
@export var hp: float = 100.0:
	set(value):
		hp = clampf(value, 0.0, max_hp)
		if hp <= 0.0:
			_on_hp_depleted()

@export var max_hp: float = 100.0

## Mana - Magical/skill resource
@export var mana: float = 100.0:
	set(value):
		mana = clampf(value, 0.0, max_mana)

@export var max_mana: float = 100.0

## Energy - Physical stamina/action resource
@export var energy: float = 100.0:
	set(value):
		energy = clampf(value, 0.0, max_energy)

@export var max_energy: float = 100.0

## Hunger - Needs to eat (0 = starving, 100 = full)
@export var hunger: float = 100.0:
	set(value):
		hunger = clampf(value, 0.0, 100.0)
		if hunger <= 0.0:
			_on_starving()

## Attack - Physical attack power
@export var attack: float = 10.0:
	set(value):
		attack = clampf(value, 0.0, 1000.0)

## Defense - Physical defense/damage reduction
@export var defense: float = 5.0:
	set(value):
		defense = clampf(value, 0.0, 1000.0)

## Emotion - Current emotional state
@export var emotion: Emotion = Emotion.NEUTRAL

## Unique identifier for this NPC instance (16-byte binary format)
var ulid: PackedByteArray = PackedByteArray()

## NPC's generated name (e.g., "Aldric Ironwood")
var npc_name: String = ""

## NPC type (e.g., "warrior", "archer")
var npc_type: String = ""


## ===== INITIALIZATION =====

func _init(
	initial_hp: float = 100.0,
	initial_mana: float = 100.0,
	initial_energy: float = 100.0,
	initial_hunger: float = 100.0,
	initial_attack: float = 10.0,
	initial_defense: float = 5.0,
	initial_emotion: Emotion = Emotion.NEUTRAL,
	type: String = "",
	name: String = ""
) -> void:
	max_hp = initial_hp
	max_mana = initial_mana
	max_energy = initial_energy

	hp = initial_hp
	mana = initial_mana
	energy = initial_energy
	hunger = initial_hunger
	attack = initial_attack
	defense = initial_defense
	emotion = initial_emotion

	# Generate unique ULID for this NPC instance
	ulid = ULID.generate()

	# Set type and generate name if not provided
	npc_type = type
	if name.is_empty() and not type.is_empty():
		npc_name = NameGenerator.generate_name_for_type(type)
	else:
		npc_name = name


## ===== STAT MODIFICATION =====

## Take damage
func take_damage(amount: float) -> void:
	hp -= amount


## Heal HP
func heal(amount: float) -> void:
	hp += amount


## Consume mana
func consume_mana(amount: float) -> bool:
	if mana >= amount:
		mana -= amount
		return true
	return false


## Consume energy
func consume_energy(amount: float) -> bool:
	if energy >= amount:
		energy -= amount
		return true
	return false


## Feed the NPC (increase hunger)
func feed(amount: float) -> void:
	hunger += amount


## Set emotion
func set_emotion(new_emotion: Emotion) -> void:
	emotion = new_emotion


## ===== DICTIONARY CONVERSION =====

## Convert stats to Dictionary (for saving/serialization)
func to_dict() -> Dictionary:
	return {
		"ulid": ULID.to_hex(ulid),  # Convert binary to hex for serialization
		"npc_name": npc_name,
		"npc_type": npc_type,
		"hp": hp,
		"max_hp": max_hp,
		"mana": mana,
		"max_mana": max_mana,
		"energy": energy,
		"max_energy": max_energy,
		"hunger": hunger,
		"attack": attack,
		"defense": defense,
		"emotion": emotion
	}


## Load stats from Dictionary
func from_dict(data: Dictionary) -> void:
	if data.has("ulid"):
		ulid = ULID.from_hex(data["ulid"])  # Convert hex back to binary
	if data.has("npc_name"):
		npc_name = data["npc_name"]
	if data.has("npc_type"):
		npc_type = data["npc_type"]

	if data.has("max_hp"):
		max_hp = data["max_hp"]
	if data.has("max_mana"):
		max_mana = data["max_mana"]
	if data.has("max_energy"):
		max_energy = data["max_energy"]

	if data.has("hp"):
		hp = data["hp"]
	if data.has("mana"):
		mana = data["mana"]
	if data.has("energy"):
		energy = data["energy"]
	if data.has("hunger"):
		hunger = data["hunger"]
	if data.has("attack"):
		attack = data["attack"]
	if data.has("defense"):
		defense = data["defense"]
	if data.has("emotion"):
		emotion = data["emotion"]


## ===== UTILITY METHODS =====

## Get HP percentage (0.0 to 1.0)
func get_hp_percent() -> float:
	return hp / max_hp if max_hp > 0 else 0.0


## Get Mana percentage (0.0 to 1.0)
func get_mana_percent() -> float:
	return mana / max_mana if max_mana > 0 else 0.0


## Get Energy percentage (0.0 to 1.0)
func get_energy_percent() -> float:
	return energy / max_energy if max_energy > 0 else 0.0


## Get Hunger percentage (0.0 to 1.0)
func get_hunger_percent() -> float:
	return hunger / 100.0


## Check if NPC is alive
func is_alive() -> bool:
	return hp > 0.0


## Check if NPC is starving
func is_starving() -> bool:
	return hunger <= 10.0


## Check if NPC has enough mana
func has_mana(amount: float) -> bool:
	return mana >= amount


## Check if NPC has enough energy
func has_energy(amount: float) -> bool:
	return energy >= amount


## Get emotion as string
func get_emotion_string() -> String:
	return Emotion.keys()[emotion]


## ===== EVENT HANDLERS =====

## Called when HP reaches 0
func _on_hp_depleted() -> void:
	emotion = Emotion.SAD


## Called when hunger reaches 0
func _on_starving() -> void:
	emotion = Emotion.SAD
	# Apply starvation damage
	take_damage(0.5)


## ===== DEBUG =====

## Print all stats
func print_stats() -> void:
	print("=== NPC Stats ===")
	print("  Name: %s" % npc_name)
	print("  Type: %s" % npc_type)
	print("  ULID: %s" % ULID.to_str(ulid))
	print("  HP: %d/%d (%.0f%%)" % [hp, max_hp, get_hp_percent() * 100])
	print("  Mana: %d/%d (%.0f%%)" % [mana, max_mana, get_mana_percent() * 100])
	print("  Energy: %d/%d (%.0f%%)" % [energy, max_energy, get_energy_percent() * 100])
	print("  Hunger: %d/100 (%.0f%%)" % [hunger, get_hunger_percent() * 100])
	print("  Attack: %d" % attack)
	print("  Defense: %d" % defense)
	print("  Emotion: %s" % get_emotion_string())
	print("  Alive: %s" % is_alive())
