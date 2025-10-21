# NPCStats Usage Examples

## Basic Setup

### In Your NPC Script (e.g., archer.gd, warrior.gd)

```gdscript
extends CharacterBody2D
class_name Archer

# Add stats property
var stats: NPCStats

func _ready() -> void:
    # Initialize stats with custom values
    stats = NPCStats.new(
        100.0,  # HP
        50.0,   # Mana
        100.0,  # Energy
        100.0,  # Hunger
        NPCStats.Emotion.NEUTRAL
    )

    # Or use default values
    stats = NPCStats.new()

func _process(delta: float) -> void:
    # Update stats over time (regen, hunger decay)
    stats.update_stats(delta)
```

## Common Operations

### Taking Damage
```gdscript
func take_damage(amount: float) -> void:
    stats.take_damage(amount)

    if not stats.is_alive():
        current_state = "Dead"
```

### Using Mana for Skills
```gdscript
func cast_spell() -> void:
    if stats.consume_mana(20.0):
        # Spell cast successful
        print("Spell cast!")
    else:
        print("Not enough mana!")
```

### Using Energy for Actions
```gdscript
func perform_attack() -> void:
    if stats.consume_energy(15.0):
        # Attack performed
        attack_animation()
    else:
        print("Too tired to attack!")
```

### Feeding the NPC
```gdscript
func eat_food(food_value: float) -> void:
    stats.feed(food_value)
```

### Changing Emotion
```gdscript
func on_player_pet() -> void:
    stats.set_emotion(NPCStats.Emotion.HAPPY)
```

## Dictionary Conversion (For Saving/Loading)

### Save Stats
```gdscript
func save_npc() -> Dictionary:
    return {
        "position": position,
        "stats": stats.to_dict()
    }
```

### Load Stats
```gdscript
func load_npc(data: Dictionary) -> void:
    position = data["position"]

    stats = NPCStats.new()
    stats.from_dict(data["stats"])
```

## Checking Stats

### Health Check
```gdscript
if stats.get_hp_percent() < 0.3:
    # Less than 30% HP
    print("Low health!")
    stats.set_emotion(NPCStats.Emotion.SCARED)
```

### Hunger Check
```gdscript
if stats.is_starving():
    print("NPC is starving!")
    # NPC will automatically take damage when starving
```

### Resource Checks
```gdscript
if stats.has_mana(50.0):
    print("Can cast ultimate spell!")

if stats.has_energy(10.0):
    print("Can perform action!")
```

## Emotion-Based Behavior

```gdscript
func update_behavior() -> void:
    match stats.emotion:
        NPCStats.Emotion.HAPPY:
            animation_speed = 1.2  # Faster animations
        NPCStats.Emotion.SAD:
            animation_speed = 0.8  # Slower animations
        NPCStats.Emotion.EXCITED:
            move_speed *= 1.5
        NPCStats.Emotion.TIRED:
            move_speed *= 0.7
        NPCStats.Emotion.ANGRY:
            damage_multiplier = 1.3
```

## Debug Stats

```gdscript
func _on_debug_button_pressed() -> void:
    stats.print_stats()
    # Outputs:
    # === NPC Stats ===
    #   HP: 85/100 (85%)
    #   Mana: 42/50 (84%)
    #   Energy: 100/100 (100%)
    #   Hunger: 67/100 (67%)
    #   Emotion: HAPPY
    #   Alive: true
```

## Accessing Emotion Enum Globally

```gdscript
# You can access the Emotion enum from anywhere:
var happy = NPCStats.Emotion.HAPPY
var sad = NPCStats.Emotion.SAD

# Get emotion name as string:
var emotion_name = stats.get_emotion_string()  # Returns "HAPPY", "SAD", etc.
```

## Integration with NPCManager

```gdscript
# In npc_manager.gd, you could add:
func get_npc_stats(npc: Node2D) -> NPCStats:
    if "stats" in npc:
        return npc.stats
    return null

func save_all_npc_stats() -> Dictionary:
    var all_stats = {}
    for slot in character_pool:
        if slot["character"] and "stats" in slot["character"]:
            all_stats[slot["character"].name] = slot["character"].stats.to_dict()
    return all_stats
```
