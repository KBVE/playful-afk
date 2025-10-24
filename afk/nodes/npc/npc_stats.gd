extends Resource
class_name NPCStats

## NPCStats - DEPRECATED Backward Compatibility Stub
##
## This class is DEPRECATED. All stats are now managed by Rust NPCDataWarehouse.
## This stub exists only for backward compatibility with legacy code in:
## - npc_manager.gd (migration in progress)
## - chat_ui.gd (displays stats from Rust)
##
## New code should query Rust directly via:
##   NPCDataWarehouse.get_npc_stats_dict(ulid)

enum Emotion {
	HAPPY,
	NEUTRAL,
	SAD,
	ANGRY,
	AFRAID
}

@export var max_hp: float = 100.0
@export var hp: float = 100.0
@export var max_mana: float = 100.0
@export var mana: float = 100.0
@export var max_energy: float = 100.0
@export var energy: float = 100.0
@export var max_hunger: float = 100.0
@export var hunger: float = 100.0
@export var attack: float = 10.0
@export var defense: float = 5.0
@export var emotion: Emotion = Emotion.NEUTRAL
@export var npc_type: String = ""


func _init(
	p_max_hp: float = 100.0,
	p_max_mana: float = 100.0,
	p_max_energy: float = 100.0,
	p_max_hunger: float = 100.0,
	p_attack: float = 10.0,
	p_defense: float = 5.0,
	p_emotion: Emotion = Emotion.NEUTRAL,
	p_npc_type: String = ""
) -> void:
	max_hp = p_max_hp
	hp = p_max_hp
	max_mana = p_max_mana
	mana = p_max_mana
	max_energy = p_max_energy
	energy = p_max_energy
	max_hunger = p_max_hunger
	hunger = p_max_hunger
	attack = p_attack
	defense = p_defense
	emotion = p_emotion
	npc_type = p_npc_type


## Convert Rust dictionary to NPCStats (for backward compatibility)
func from_dict(data: Dictionary) -> void:
	if data.has("max_hp"): max_hp = data["max_hp"]
	if data.has("hp"): hp = data["hp"]
	if data.has("max_mana"): max_mana = data["max_mana"]
	if data.has("mana"): mana = data["mana"]
	if data.has("max_energy"): max_energy = data["max_energy"]
	if data.has("energy"): energy = data["energy"]
	if data.has("max_hunger"): max_hunger = data["max_hunger"]
	if data.has("hunger"): hunger = data["hunger"]
	if data.has("attack"): attack = data["attack"]
	if data.has("defense"): defense = data["defense"]
	if data.has("npc_type"): npc_type = data["npc_type"]

	# Map emotion from Rust
	if data.has("emotion"):
		match data["emotion"]:
			"Happy": emotion = Emotion.HAPPY
			"Neutral": emotion = Emotion.NEUTRAL
			"Sad": emotion = Emotion.SAD
			"Angry": emotion = Emotion.ANGRY
			"Afraid": emotion = Emotion.AFRAID
			_: emotion = Emotion.NEUTRAL


## Convert NPCStats to dictionary (for Rust sync)
func to_dict() -> Dictionary:
	var emotion_str = "Neutral"
	match emotion:
		Emotion.HAPPY: emotion_str = "Happy"
		Emotion.NEUTRAL: emotion_str = "Neutral"
		Emotion.SAD: emotion_str = "Sad"
		Emotion.ANGRY: emotion_str = "Angry"
		Emotion.AFRAID: emotion_str = "Afraid"

	return {
		"max_hp": max_hp,
		"hp": hp,
		"max_mana": max_mana,
		"mana": mana,
		"max_energy": max_energy,
		"energy": energy,
		"max_hunger": max_hunger,
		"hunger": hunger,
		"attack": attack,
		"defense": defense,
		"emotion": emotion_str,
		"npc_type": npc_type
	}
