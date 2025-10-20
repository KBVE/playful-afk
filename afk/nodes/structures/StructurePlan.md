# Structure System Architecture

## Overview
The structure system provides a DRY (Don't Repeat Yourself) approach for creating interactive structures in the game. All structures inherit from a common base class and are managed by a centralized singleton manager.

## Core Components

### 1. StructureManager (Singleton)
**Location**: `afk/nodes/structures/structure_manager.gd`
**Autoload**: Yes (registered in project.godot)

**Responsibilities**:
- Centralized click handling for all structures
- Click debouncing (0.5s delay to prevent double-clicks)
- Modal state management
- Structure interaction state tracking

**Key Properties**:
- `is_modal_open: bool` - Prevents interaction when modal is open
- `is_transitioning: bool` - Prevents interaction during camera panning
- `current_structure: Node2D` - Reference to currently interacted structure
- `click_debounce_time: float` - Time between allowed clicks (default: 0.5s)
- `registered_structures: Array[Node2D]` - List of all registered structures
- `structure_spacing: float` - Horizontal spacing between structures (default: 200.0)
- `ground_y_base: float` - Base Y position for ground structures (default: 440.0)
- `ground_y_variance: float` - Random Y offset for natural look (default: 20.0)

**Key Signals**:
- `structure_clicked(structure: Node2D)` - Emitted when structure is clicked
- `structure_modal_opened(structure: Node2D)` - Emitted when modal opens
- `structure_modal_closed(structure: Node2D)` - Emitted when modal closes

**Public Methods**:
```gdscript
func can_interact() -> bool
func handle_structure_click(structure: Node2D, structure_name: String, structure_description: String) -> void
func register_structure(structure: Node2D) -> void
func get_next_structure_position() -> Vector2
func clear_structures() -> void
```

### 2. BaseStructure (Parent Class)
**Location**: `afk/nodes/structures/base_structure.gd`
**Type**: `class_name BaseStructure extends Node2D`

**Responsibilities**:
- Common floating animation for all structures
- Hover effects (fade in/out)
- Click detection and handling
- Integration with InputManager and StructureManager

**Export Properties** (customizable per structure):
```gdscript
@export var structure_name: String = "Structure"
@export var structure_description: String = "This is a structure."
@export var float_amplitude: float = 3.0
@export var float_speed: float = 0.5
@export var distance_opacity: float = 0.6
@export var near_opacity: float = 1.0
@export var click_radius: float = 81.6
```

**Required Child Node**:
- `Sprite2D` - The visual representation of the structure

**Key Features**:
- Automatic floating animation using sine wave
- Distance-based opacity (appears faded, brightens on hover)
- Click detection with configurable radius
- Automatic InputManager integration
- Scale animation on click

## How to Add a New Structure

### Step 1: Create the Script
Create `[structure_name].gd` in `afk/nodes/structures/[structure_name]/`

```gdscript
extends BaseStructure
class_name StructureName

func _ready() -> void:
	# Set structure-specific properties
	structure_name = "Display Name"
	structure_description = "Description text here.\nSupports multiple lines.\n\n(More features coming soon...)"

	# Optional: Override default properties
	# float_amplitude = 5.0
	# float_speed = 0.3

	# Call parent _ready to initialize common functionality
	super._ready()
```

### Step 2: Create the Scene
Create `[structure_name].tscn` in the same folder:

```
[gd_scene load_steps=3 format=3 uid="uid://unique_id"]

[ext_resource type="Script" path="res://nodes/structures/[structure_name]/[structure_name].gd" id="1_script"]
[ext_resource type="Texture2D" path="res://nodes/structures/[structure_name]/[structure_name].png" id="2_texture"]

[node name="StructureName" type="Node2D"]
script = ExtResource("1_script")
click_radius = 81.6

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_texture")
centered = true
```

### Step 3: Add to Scene
Add the structure to `afk/nodes/background/rolling_hills/rolling_hills_background.tscn`:

1. Add external resource at the top:
```
[ext_resource type="PackedScene" uid="uid://unique_id" path="res://nodes/structures/[structure_name]/[structure_name].tscn" id="X_structure_name"]
```

2. Add instance to Layer3Objects (NO position or scale needed - auto-positioned!):
```
[node name="StructureName" parent="Layer3Objects" instance=ExtResource("X_structure_name")]
```

**That's it!** The structure will be automatically:
- Positioned with proper spacing (200px between structures)
- Placed at ground level with slight Y variance for natural look
- Scaled to 2x2 for consistency
- Registered with StructureManager for click handling

## Automatic Structure Positioning

The StructureManager now handles all positioning automatically! When structures are added to `Layer3Objects`, they are:

1. **Auto-registered** - `RollingHillsBackground` registers all child structures on ready
2. **Auto-positioned** - Structures are spaced 200px apart horizontally
3. **Natural variance** - Each structure gets a random Y offset (±20px) based on its index
4. **Auto-scaled** - All structures scaled to 2x2 for consistency

**Positioning Algorithm**:
- First structure: X=200, Y=440±20
- Second structure: X=400, Y=440±20
- Third structure: X=600, Y=440±20
- And so on...

**Customization** (in StructureManager):
```gdscript
var structure_spacing: float = 200.0      # Horizontal spacing
var ground_y_base: float = 440.0          # Base Y position
var ground_y_variance: float = 20.0       # Random Y variance
var start_x: float = 200.0                # First structure X
```

**Benefits**:
- No manual position calculation needed
- Consistent spacing across all structures
- Easy to add new structures - just add to scene!
- Natural look with randomized Y positions
- Future-proof: wraps to next row if too many structures

## Existing Structures

All structures are auto-positioned in order they appear in the scene tree.

### StoneHome (Index 0)
- **Location**: `afk/nodes/structures/stone_home/`
- **Auto-Position**: X=200, Y=440±variance
- **Description**: "A sturdy stone dwelling. Provides shelter and comfort for your pets and villagers."

### CatFarm (Index 1)
- **Location**: `afk/nodes/structures/cat_farm/`
- **Auto-Position**: X=400, Y=440±variance
- **Description**: "This is where you can manage your cats, collect resources, and expand your farm."

### Castle (Index 2)
- **Location**: `afk/nodes/structures/castle/`
- **Auto-Position**: X=600, Y=440±variance
- **Description**: "A grand castle standing tall. Manage your kingdom's resources and unlock powerful upgrades."

**Note**: Order in scene tree determines position! StoneHome is first child, so it appears leftmost.

## Integration with Other Systems

### InputManager
- BaseStructure registers with InputManager on `_ready()`
- InputManager handles global mouse input and hover detection
- When modal is open, InputManager blocks background interactions

### Modal System
- StructureManager creates modal instance when structure is clicked
- Modal displays structure name and description
- Modal uses `nodes/ui/modal/modal.tscn`
- Integrates with InputManager for click blocking

### Camera System
- Camera panning is tracked by StructureManager
- Interactions blocked during camera transitions via `is_transitioning` flag

## Code Statistics

### Before DRY System (cat_farm only)
- Lines of code: ~120

### After DRY System (per structure)
- BaseStructure: ~150 lines (shared)
- StructureManager: ~80 lines (shared)
- Each new structure: ~13 lines

**Benefits**:
- 90% reduction in code per structure
- Consistent behavior across all structures
- Single source of truth for common functionality
- Easy to add new structures
- Centralized bug fixes and improvements

## Best Practices

1. **Always extend BaseStructure** - Never create standalone structure scripts
2. **Use StructureManager** - Don't handle clicks directly in structure scripts
3. **Set meaningful descriptions** - Users will see these in modals
4. **Position thoughtfully** - Avoid overlapping structures
5. **Test hover/click** - Ensure no overlapping UI blocks input
6. **Keep it simple** - Structure scripts should only set properties

## Troubleshooting

### Structure not clickable
- Check that `mouse_filter = 2` is set on background layers
- Verify InputManager is registered as autoload
- Ensure Sprite2D child node exists

### Hover effect not working
- Check InputManager integration
- Verify no UI elements blocking mouse input
- Ensure structure is visible and within screen bounds

### Modal not opening
- Check StructureManager is registered as autoload
- Verify modal scene exists at `nodes/ui/modal/modal.tscn`
- Check console for errors during modal instantiation

### Floating animation too fast/slow
- Adjust `float_speed` export property (lower = slower)
- Adjust `float_amplitude` export property (lower = less movement)

## Future Enhancements

Potential improvements to consider:
- Custom modal content per structure type
- Structure upgrade system
- Resource generation/collection
- Structure dependencies and unlock system
- Save/load structure states
- Structure-specific animations beyond floating
- Multi-layer structure support (foreground/background)
