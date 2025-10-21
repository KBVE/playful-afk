# AFK

This is an [itch.io](https://kbve.itch.io/afk/) gamejam that is for Playful's Gamejam.
However my plan is to not only build this game for it but also expand it out whenever I need to take a break from Unity.

The basics of this game is simple, you are a leader of a cat but not any random cat, one that will become a god!

### Structures

The structures will be under the "/afk/nodes/structures" folder and will provide active and passive benefits for your kingdom.

#### Stone Home

A sturdy stone dwelling that provides shelter and comfort for your pets and villagers. This town structure serves as basic housing for your growing settlement, offering a safe haven for your citizens. The Stone Home is built at ground level and acts as a foundational building for your kingdom's expansion.

- **Type**: TOWN
- **Level**: GROUND
- **Benefits**: Housing, basic shelter

#### Cat Farm

The heart of your resource generation! The Cat Farm is where you manage your cats, collect resources, and expand your farming operations. This structure allows you to gather materials, breed cats, and establish the economic foundation of your kingdom. Essential for early-game resource management.

- **Type**: FARM
- **Level**: GROUND
- **Benefits**: Resource collection, cat management

#### Castle

A grand castle standing tall as the center of your kingdom's power. This majestic fortress serves dual purposes - managing your kingdom's resources and providing strong defensive capabilities. The Castle unlocks powerful upgrades and acts as a command center for your entire realm.

- **Type**: CASTLE, DEFENSE
- **Level**: GROUND
- **Benefits**: Kingdom management, resource upgrades, defense

#### City Tower

A magnificent tower that reaches into the sky, watching over your entire kingdom from the clouds. This multi-purpose structure provides aerial defense, serves as a town hub for advanced features, and is one of the starting structures that appears when you begin your journey. Its elevated position gives strategic advantages for protecting your realm.

- **Type**: TOWN, DEFENSE, SPAWN
- **Level**: SKY
- **Benefits**: Advanced defense, town hub, starting structure
- **Special**: Spawns at game start

#### Dragon Den

A fearsome dragon's lair that provides the ultimate defensive power for your kingdom. Perched high in the sky, the Dragon Den is home to powerful dragons that protect your realm from above. As a spawn structure, it appears at the beginning of your journey, giving you early access to powerful defensive capabilities. This mysterious den holds great power waiting to be unleashed.

- **Type**: DEFENSE, SPAWN
- **Level**: SKY
- **Benefits**: Powerful defense, dragon allies, aerial superiority
- **Special**: Spawns at game start

#### Inn

A cozy inn where travelers rest and gather. Built on elevated ground for better visibility, this warm and welcoming establishment serves as a town hub, providing comfort and hospitality to visitors and citizens alike. As a spawn structure, the Inn appears at the start of your journey, offering a place for weary adventurers to find respite and share tales of their travels.

- **Type**: TOWN, SPAWN
- **Level**: ELEVATED
- **Benefits**: Comfort, town hub, traveler services
- **Special**: Spawns at game start

#### Barracks

Military training grounds where your forces hone their skills. Positioned on elevated ground for strategic advantage, the Barracks is essential for building and maintaining a strong army to defend your kingdom. Train soldiers, improve their combat abilities, and prepare them for battle. As a spawn structure, it appears at the beginning of your journey to ensure you have military support from day one.

- **Type**: DEFENSE, SPAWN
- **Level**: ELEVATED
- **Benefits**: Military training, soldier recruitment, defense
- **Special**: Spawns at game start

### NPCs

The game features various NPCs that inhabit your kingdom. All NPCs are managed through the data-driven NPC Registry system located in `/afk/nodes/npc/npc_manager.gd`, making it easy to add new characters.

#### Cat (Virtual Pet)

Your divine companion on the journey to godhood! The Cat is your primary character and the heart of your kingdom. Manage its hunger, happiness, and health while watching it grow in level and experience. The Cat can walk around, be clicked to view its stats, and is central to your kingdom's story.

- **Type**: Virtual Pet
- **Location**: Ground level, follows player interaction
- **Stats**: Hunger, Happiness, Health, Level, Experience
- **Features**: Interactive, state-based animations (idle, walking, sitting, eating, sleeping, playing)
- **Special**: Primary character, scalable (4x size)

#### Warrior

A brave melee fighter protecting your kingdom! The Warrior patrols the grounds with sword ready, demonstrating combat prowess through various animations. Click to interact and engage in dialogue. Part of the NPC character pool system.

- **Type**: Melee NPC
- **Category**: Melee
- **Location**: Character pool (Layer4), autonomous movement
- **Stats**: Health, Strength, Defense, Level
- **Animations**: Idle, Walking (run), Attack
- **Features**: Click-to-dialogue, autonomous patrol, hover highlighting
- **Pool Slot**: 0 (active by default)
- **Scale**: 2x

#### Archer

A skilled ranged combatant who keeps watch over your realm! The Archer moves gracefully with bow in hand, ready to defend from afar. Features comprehensive animation states including hurt and death sequences. Click to interact and start a conversation.

- **Type**: Ranged NPC
- **Category**: Ranged
- **Location**: Character pool (Layer4), autonomous movement
- **Stats**: Health, Agility, Attack Range, Level
- **Animations**: Idle, Walk, Attack, Hurt, Dead
- **Features**: Click-to-dialogue, autonomous patrol, hover highlighting
- **Pool Slot**: 1 (active by default)
- **Scale**: 2x

#### Adding New NPCs

Thanks to the NPC Registry system, adding new NPCs is straightforward:

1. Create NPC files in `/afk/nodes/npc/[npc_name]/`
   - `[npc_name].gd` - Main NPC class
   - `[npc_name]_controller.gd` - Animation/movement controller
   - `[npc_name].tscn` - Scene file
   - Animation sprite sheets

2. Register in `/afk/nodes/npc/npc_manager.gd`:
```gdscript
const NPC_REGISTRY: Dictionary = {
    "your_npc": {
        "scene": "res://nodes/npc/your_npc/your_npc.tscn",
        "class_name": "YourNPC",
        "category": "melee/ranged/magic"
    }
}
```

3. Spawn using the unified API:
```gdscript
NPCManager.add_npc_to_pool("your_npc", slot_index, position, activate, movement_bounds)
```

For detailed instructions, see [`/docs/adding-new-npcs.md`](/docs/adding-new-npcs.md)





#### Credits

Cat asset from Elthen
https://elthen.itch.io/2d-pixel-art-cat-sprites

Red Forest asset
https://brullov.itch.io/oak-woods

Mondstadt Theme Forest Intro
https://theflavare.itch.io/mondstadt-theme-background-pixel-art

Background Hill
https://szadiart.itch.io/bakcground-hill

Free Sky Background
https://free-game-assets.itch.io/free-sky-with-clouds-background-pixel-art-set

Dice
https://srspooky.itch.io/pixel-spritesheet-dice20d

Pocker Cards
https://ivoryred.itch.io/pixel-poker-cards

Kobold Warrior
https://xzany.itch.io/kobold-warrior-2d-pixel-art

Gandalf Hardcore The Archer
https://gandalfhardcore.itch.io/pixel-art-archer-character

Forest Monster Mushroom
https://monopixelart.itch.io/forest-monsters-pixel-art/

Monsters Fantasy
https://luizmelo.itch.io/monsters-creatures-fantasy