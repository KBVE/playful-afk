# Adding New NPCs to the Game

## Overview

The NPC system has been refactored to use a **data-driven registry pattern**. This makes adding new NPCs extremely simple and scalable.

## Quick Start: Adding a New NPC

### Step 1: Create NPC Files

Create your NPC following the existing pattern (see `warrior` or `archer` as examples):

```
afk/nodes/npc/mage/
  ├── mage.gd              # Main NPC class
  ├── mage_controller.gd   # Animation/movement controller
  ├── mage.tscn            # Scene file
  └── MAGE_*.png           # Animation spritesheets
```

### Step 2: Register in NPCManager

Open [`afk/nodes/npc/npc_manager.gd`](../afk/nodes/npc/npc_manager.gd) and add your NPC to the `NPC_REGISTRY`:

```gdscript
const NPC_REGISTRY: Dictionary = {
	"warrior": {
		"scene": "res://nodes/npc/warrior/warrior.tscn",
		"class_name": "Warrior",
		"category": "melee"
	},
	"archer": {
		"scene": "res://nodes/npc/archer/archer.tscn",
		"class_name": "Archer",
		"category": "ranged"
	},
	"mage": {  # <-- Add your new NPC here!
		"scene": "res://nodes/npc/mage/mage.tscn",
		"class_name": "Mage",
		"category": "magic"
	}
}
```

**That's it!** The system will automatically:
- Load the scene at startup
- Create UI sprite cache for ChatUI/Modals
- Make it available via `add_npc_to_pool()`
- Handle type detection in `get_npc_type()`

## Usage

### Spawning NPCs in the Character Pool

```gdscript
# New unified API - works for all NPC types!
NPCManager.add_npc_to_pool("mage", slot_index, position, activate, movement_bounds)
NPCManager.add_npc_to_pool("warrior", slot_index, position, activate, movement_bounds)
NPCManager.add_npc_to_pool("archer", slot_index, position, activate, movement_bounds)

# Legacy functions still work (backwards compatibility)
NPCManager.add_warrior_to_pool(slot_index, position, activate, movement_bounds)
NPCManager.add_archer_to_pool(slot_index, position, activate, movement_bounds)
```

### Getting Available NPC Types

```gdscript
# Get all registered NPC types
var npc_types = NPCManager.get_registered_npc_types()
# Returns: ["warrior", "archer", "mage"]

# Check if NPC type exists
if NPCManager.is_valid_npc_type("mage"):
	# Spawn mage
```

### Creating NPCs Directly

```gdscript
# Create an NPC instance
var mage = NPCManager.create_npc("mage")
if mage:
	add_child(mage)
```

## NPC Registry Structure

Each NPC in the registry has these properties:

| Property | Type | Description | Required |
|----------|------|-------------|----------|
| `scene` | String | Path to .tscn file | ✅ Yes |
| `class_name` | String | GDScript class name | ✅ Yes |
| `category` | String | NPC category (melee/ranged/magic/etc) | ❌ Optional |

You can add custom metadata fields as needed!

## Benefits of the New System

### Before (Old System)
```gdscript
# Adding a new NPC required changes in multiple places:

# 1. Add variable
var mage: Mage = null

# 2. Add scene preload
var mage_scene: PackedScene = preload("res://nodes/npc/mage/mage.tscn")

# 3. Add to UI cache
var ui_sprite_cache: Dictionary = {
	"cat": null,
	"warrior": null,
	"archer": null,
	"mage": null  # <-- Remember to add!
}

# 4. Create initialization function
func _initialize_mage() -> void: ...

# 5. Create pool function
func add_mage_to_pool(...) -> Mage: ...

# 6. Update get_npc_type()
func get_npc_type(npc: Node2D) -> String:
	if npc is Mage:
		return "mage"
	# ...

# 7. Create UI sprite caching code
var temp_mage = mage_scene.instantiate()
# ... 10+ lines of code
```

### After (New System)
```gdscript
# Just add to NPC_REGISTRY - that's it!
const NPC_REGISTRY: Dictionary = {
	"mage": {
		"scene": "res://nodes/npc/mage/mage.tscn",
		"class_name": "Mage",
		"category": "magic"
	}
}
```

## Architecture Details

### NPC Registry System

- **`NPC_REGISTRY`**: Central dictionary defining all NPC types
- **`_npc_scenes`**: Runtime cache of loaded PackedScenes
- **`ui_sprite_cache`**: Automatically populated with sprites from all registered NPCs

### Key Functions

| Function | Purpose |
|----------|---------|
| `_load_npc_scenes()` | Loads all scenes from registry at startup |
| `get_npc_scene(type)` | Get cached scene for an NPC type |
| `create_npc(type)` | Instantiate an NPC by type string |
| `add_npc_to_pool(type, ...)` | Add any NPC type to character pool |
| `get_npc_type(npc)` | Get type string from NPC instance |
| `_cache_npc_ui_sprite(type)` | Cache UI sprite for an NPC type |

### Type Detection

The system automatically detects NPC types by matching the `get_class()` name against the registry's `class_name` field. This means you don't need to update type checking code when adding new NPCs!

## Examples

### Example: Adding a Tank NPC

1. Create files: `afk/nodes/npc/tank/tank.gd`, `tank_controller.gd`, `tank.tscn`

2. Add to registry:
```gdscript
"tank": {
	"scene": "res://nodes/npc/tank/tank.tscn",
	"class_name": "Tank",
	"category": "melee",
	"max_health": 200  // Custom metadata!
}
```

3. Use it:
```gdscript
NPCManager.add_npc_to_pool("tank", 0, Vector2(100, 500), true)
```

### Example: Spawning Random NPCs

```gdscript
func spawn_random_npc(slot: int) -> void:
	var npc_types = NPCManager.get_registered_npc_types()
	var random_type = npc_types[randi() % npc_types.size()]
	NPCManager.add_npc_to_pool(random_type, slot, Vector2.ZERO, true)
```

## Migration Notes

The old functions (`add_warrior_to_pool`, `add_archer_to_pool`) still work for backwards compatibility but are marked as **LEGACY**. It's recommended to use the new `add_npc_to_pool()` API for all new code.

## Future Enhancements

Potential improvements to the system:

- Add `stats` metadata to registry for default NPC stats
- Add `spawn_weight` for random NPC spawning
- Add `unlock_level` for progression systems
- Support NPC variants (e.g., "warrior_elite", "archer_fire")
