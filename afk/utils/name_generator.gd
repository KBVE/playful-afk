extends Node

## NameGenerator - Random name generation for NPCs
## Generates fantasy-style names using first name + last name pools
## Can be used for warriors, archers, and other NPCs

## ===== NAME POOLS =====

const FIRST_NAMES: Array[String] = [
	# Human/Fantasy First Names
	"Aldric", "Bran", "Cedric", "Darius", "Elden", "Finn", "Gareth", "Haldor",
	"Iris", "Jaren", "Kael", "Lyra", "Mira", "Nolan", "Orin", "Petra",
	"Quinn", "Raven", "Soren", "Thalia", "Uther", "Vera", "Wren", "Xander",
	"Yara", "Zane", "Aria", "Bjorn", "Cora", "Drake", "Elara", "Freya",
	"Galen", "Helena", "Ivan", "Jade", "Kane", "Luna", "Magnus", "Nyx",
	"Orion", "Piper", "Roland", "Sage", "Thorn", "Una", "Victor", "Willow",
	"Axel", "Brynn", "Cassia", "Dorian", "Ember", "Felix", "Giselle", "Hugo",
	"Isla", "Jasper", "Kira", "Liam", "Maya", "Nash", "Olive", "Phoenix"
]

const LAST_NAMES: Array[String] = [
	# Fantasy Last Names
	"Ironwood", "Stormborn", "Nightshade", "Firehart", "Frostbane", "Thornwood",
	"Silverwind", "Darkwater", "Brightblade", "Shadowmere", "Goldleaf", "Steelheart",
	"Wolfsbane", "Ravenwood", "Stonefist", "Quicksilver", "Blackthorn", "Whiteoak",
	"Redcliff", "Greywood", "Bluestone", "Ashwood", "Emberforge", "Icewind",
	"Thunderstrike", "Swiftarrow", "Strongbow", "Ironside", "Dragonheart", "Moonshadow",
	"Sunblade", "Starfall", "Windwalker", "Earthshaker", "Flamebringer", "Frostweaver",
	"Stormcaller", "Shadowblade", "Lightbringer", "Darkhand", "Silvermoon", "Goldenshield",
	"Oakenshield", "Ironforge", "Steelbreaker", "Stonehammer", "Fireborn", "Iceborn",
	"Bloodmoon", "Grimward", "Brightforge", "Darkforge", "Wildhart", "Trueblade",
	"Swiftfoot", "Keenblade", "Valorheart", "Dawnbringer", "Duskwalker", "Starweaver"
]

## Random number generator
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _initialized: bool = false


## ===== INITIALIZATION =====

static func _ensure_initialized() -> void:
	if not _initialized:
		rng.randomize()
		_initialized = true


## ===== NAME GENERATION =====

## Generate a random full name (First + Last)
static func generate_full_name() -> String:
	_ensure_initialized()

	var first = FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
	var last = LAST_NAMES[rng.randi() % LAST_NAMES.size()]

	return first + " " + last


## Generate a random first name only
static func generate_first_name() -> String:
	_ensure_initialized()
	return FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]


## Generate a random last name only
static func generate_last_name() -> String:
	_ensure_initialized()
	return LAST_NAMES[rng.randi() % LAST_NAMES.size()]


## Generate a warrior name (with title)
static func generate_warrior_name() -> String:
	_ensure_initialized()

	var titles = ["the Bold", "the Brave", "the Mighty", "the Fierce", "the Strong"]
	var name = generate_full_name()

	# 50% chance to add title
	if rng.randf() < 0.5:
		var title = titles[rng.randi() % titles.size()]
		return name + " " + title

	return name


## Generate an archer name (with title)
static func generate_archer_name() -> String:
	_ensure_initialized()

	var titles = ["the Swift", "the Keen", "the Sure", "the Silent", "the Deadly"]
	var name = generate_full_name()

	# 50% chance to add title
	if rng.randf() < 0.5:
		var title = titles[rng.randi() % titles.size()]
		return name + " " + title

	return name


## Generate a name based on NPC type
static func generate_name_for_type(npc_type: String) -> String:
	match npc_type.to_lower():
		"warrior":
			return generate_warrior_name()
		"archer":
			return generate_archer_name()
		_:
			return generate_full_name()


## ===== BATCH GENERATION =====

## Generate multiple unique names (ensures no duplicates in batch)
static func generate_unique_names(count: int) -> Array[String]:
	_ensure_initialized()

	var names: Array[String] = []
	var attempts = 0
	var max_attempts = count * 10  # Safety limit

	while names.size() < count and attempts < max_attempts:
		var name = generate_full_name()
		if not names.has(name):
			names.append(name)
		attempts += 1

	if attempts >= max_attempts:
		push_warning("NameGenerator: Could not generate %d unique names, got %d" % [count, names.size()])

	return names


## Generate unique names for specific NPC type
static func generate_unique_names_for_type(npc_type: String, count: int) -> Array[String]:
	_ensure_initialized()

	var names: Array[String] = []
	var attempts = 0
	var max_attempts = count * 10

	while names.size() < count and attempts < max_attempts:
		var name = generate_name_for_type(npc_type)
		if not names.has(name):
			names.append(name)
		attempts += 1

	return names


## ===== UTILITY =====

## Get total possible combinations
static func get_possible_combinations() -> int:
	return FIRST_NAMES.size() * LAST_NAMES.size()


## Debug - print some example names
static func print_example_names(count: int = 10) -> void:
	print("=== Example Generated Names ===")
	for i in range(count):
		print("  %d. %s" % [i + 1, generate_full_name()])

	print("\n=== Warrior Names ===")
	for i in range(5):
		print("  %d. %s" % [i + 1, generate_warrior_name()])

	print("\n=== Archer Names ===")
	for i in range(5):
		print("  %d. %s" % [i + 1, generate_archer_name()])

	print("\nTotal possible combinations: %d" % get_possible_combinations())
