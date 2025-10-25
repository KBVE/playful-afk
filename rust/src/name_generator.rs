/// Simple name generator for NPCs
/// Uses static name lists and random selection
use rand::Rng;

// Fantasy first names
const FIRST_NAMES: &[&str] = &[
    "Aldric", "Branwen", "Cedric", "Darian", "Elara", "Finnian", "Gwen", "Hector", "Isolde",
    "Jareth", "Kael", "Lyra", "Magnus", "Nessa", "Orin", "Petra", "Quinlan", "Rowan", "Seren",
    "Thane", "Uma", "Vex", "Wren", "Xander", "Yara", "Zephyr", "Aric", "Brynn", "Cael", "Dorian",
    "Elowen", "Faelan",
];

// Fantasy last names
const LAST_NAMES: &[&str] = &[
    "Ironwood",
    "Stormwind",
    "Ashblade",
    "Nightshade",
    "Silverbrook",
    "Ravencroft",
    "Thornheart",
    "Moonwhisper",
    "Fireforge",
    "Frostbane",
    "Starfall",
    "Shadowmere",
    "Brightblade",
    "Darkwater",
    "Goldhammer",
    "Swiftstrike",
    "Earthshaker",
    "Windwalker",
];

// Warrior titles
const WARRIOR_TITLES: &[&str] = &[
    "the Brave",
    "the Mighty",
    "Ironheart",
    "the Defender",
    "Stormbreaker",
    "the Fearless",
    "Warbringer",
    "the Unyielding",
    "Steelborn",
    "the Valiant",
];

// Archer titles
const ARCHER_TITLES: &[&str] = &[
    "the Swift",
    "Eagleeye",
    "the Precise",
    "Windrunner",
    "the Silent",
    "Sharpshot",
    "the Keen",
    "Truearrow",
    "the Watchful",
    "Swiftwing",
];

// Goblin name parts
const GOBLIN_PREFIXES: &[&str] = &[
    "Grik", "Zak", "Nog", "Snik", "Grub", "Mog", "Gob", "Snag", "Krag", "Zig", "Dreg", "Slog",
];

const GOBLIN_SUFFIXES: &[&str] = &[
    "fang", "nail", "shiv", "scurry", "grunt", "snarl", "claw", "snap", "bite", "sneak", "lurk",
    "skulk",
];

// Mushroom types
const MUSHROOM_TYPES: &[&str] = &[
    "Morel",
    "Chanterelle",
    "Puffball",
    "Shimeji",
    "Oyster",
    "Shiitake",
    "Portobello",
    "Enoki",
    "Maitake",
    "Trumpet",
];

// Chicken names
const CHICKEN_NAMES: &[&str] = &[
    "Cluck",
    "Peck",
    "Feather",
    "Nugget",
    "Wing",
    "Beak",
    "Drumstick",
    "Rooster",
    "Hen",
    "Chick",
    "Scramble",
    "Omelet",
];

/// Generate a fantasy name for an NPC based on their type
pub fn generate_name(npc_type: &str) -> String {
    let mut rng = rand::thread_rng();

    match npc_type {
        "warrior" => {
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            let title = WARRIOR_TITLES[rng.gen_range(0..WARRIOR_TITLES.len())];
            format!("{} {}", first, title)
        }
        "archer" => {
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            let title = ARCHER_TITLES[rng.gen_range(0..ARCHER_TITLES.len())];
            format!("{} {}", first, title)
        }
        "goblin" => {
            let prefix = GOBLIN_PREFIXES[rng.gen_range(0..GOBLIN_PREFIXES.len())];
            let suffix = GOBLIN_SUFFIXES[rng.gen_range(0..GOBLIN_SUFFIXES.len())];
            format!("{}{}", prefix, suffix)
        }
        "skeleton" => {
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            let last = LAST_NAMES[rng.gen_range(0..LAST_NAMES.len())];
            format!("Skeletal {} {}", first, last)
        }
        "mushroom" => {
            let mushroom_type = MUSHROOM_TYPES[rng.gen_range(0..MUSHROOM_TYPES.len())];
            format!("{} Mushroom", mushroom_type)
        }
        "eyebeast" => {
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            format!("{} the Watcher", first)
        }
        "chicken" => CHICKEN_NAMES[rng.gen_range(0..CHICKEN_NAMES.len())].to_string(),
        "cat" => {
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            format!("{} the Cat", first)
        }
        _ => {
            // Default: generate a full fantasy name
            let first = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
            let last = LAST_NAMES[rng.gen_range(0..LAST_NAMES.len())];
            format!("{} {}", first, last)
        }
    }
}
