# Heightmap Utility

Extract walkable terrain bounds from background images for accurate NPC movement.

## Overview

This utility analyzes background images to extract the exact curve/shape of walkable terrain (hills, ground, platforms, etc.) and provides GDScript classes to query walkable Y bounds at any X position.

**Use Case**: Make NPCs follow the actual terrain contours instead of using flat horizontal movement zones.

## Files

### Python Scripts (for image analysis)

- `extract_bounds_rgb.py` - **Main script** - Analyzes PNG images to find walkable terrain
- `extract_bounds_fast.py` - Alternative using alpha channel (PGM format)
- `extract_bounds.py` - Original pixel-by-pixel version (slow, for reference)

### GDScript Classes

- `heightmap_reader.gd` - Runtime utility for converting heightmap data into walkable bounds

## Usage Guide

### Step 1: Extract Heightmap from Background Image

```bash
# Navigate to your background image directory
cd afk/nodes/background/your_background/

# Copy the extraction script
cp ../../../utils/heightmap/extract_bounds_rgb.py .

# Run analysis on your background layer image
python3 extract_bounds_rgb.py
```

**Requirements**:
- Python 3
- PIL/Pillow: `pip3 install Pillow`
- Background image with transparent sky and opaque ground/terrain

The script will:
1. Load `background4.png` (edit script to change filename)
2. Scan for green/opaque pixels (customizable threshold)
3. Find topmost walkable pixel at regular X intervals (every 10px)
4. Generate `walkable_heightmap.json`
5. Print GDScript dictionary format to copy

**Output Example**:
```
Sampling every 10px...
X=  0: Y=241
X= 10: Y=243
...

Stats:
  Min Y (highest point): 234
  Max Y (lowest point): 300
  Range: 66 pixels

# GDScript Dictionary (copy to your background script):
const WALKABLE_HEIGHTMAP: Dictionary = {
    0: 241, 10: 243, 20: 246, ...
}
```

### Step 2: Add Heightmap to Your Background Script

```gdscript
extends Control
class_name YourBackground

# Paste the heightmap data from extraction script
const WALKABLE_HEIGHTMAP: Dictionary = {
    0: 241, 10: 243, 20: 246, 30: 251, 40: 258,
    # ... rest of data
}

const BG_IMAGE_WIDTH: int = 640   # Your image width
const BG_IMAGE_HEIGHT: int = 384  # Your image height

var heightmap_reader: HeightmapReader = null

func _ready() -> void:
    # Initialize heightmap reader
    heightmap_reader = HeightmapReader.new(
        WALKABLE_HEIGHTMAP,
        BG_IMAGE_WIDTH,
        BG_IMAGE_HEIGHT
    )

    # Configure for your background
    heightmap_reader.set_tile_scale(3.0)      # If using tiling shader
    heightmap_reader.set_walkable_margin(20.0)  # Movement variation range

## Public API for NPCs to query bounds
func get_walkable_y_bounds(screen_x: float) -> Vector2:
    var viewport_size = get_viewport_rect().size
    return heightmap_reader.get_walkable_y_bounds(screen_x, viewport_size)
```

### Step 3: Use in NPC Spawning/Movement

```gdscript
# In your main game script
func spawn_npc(x_pos: float):
    # Get accurate Y bounds from background
    var y_bounds = background.get_walkable_y_bounds(x_pos)

    # Spawn NPC at random Y within bounds
    var spawn_y = randf_range(y_bounds.x, y_bounds.y)
    var npc = NPCManager.get_generic_npc("warrior", Vector2(x_pos, spawn_y), y_bounds)
```

The NPC will now:
- Spawn on the actual terrain curve
- Move vertically within the terrain bounds at that X position
- Smoothly transition Y position as they walk (using tween system)

## Customization

### Adjust Detection Threshold

Edit `extract_bounds_rgb.py`:

```python
GREEN_THRESHOLD = 100  # Lower = detect darker greens
                       # Higher = only bright greens

def is_green_pixel(pixel):
    r, g, b, a = pixel
    # Customize detection logic:
    # - For brown ground: check r > g
    # - For snow: check r == g == b and all > 200
    # - For water: check b > r and b > g
    return g > GREEN_THRESHOLD and g > r and g > b and a > 0
```

### Adjust Sample Interval

```python
SAMPLE_INTERVAL = 10  # Pixels between samples
                      # Lower = more accurate but larger data
                      # Higher = faster but less smooth
```

### Runtime Configuration

```gdscript
# Adjust margin for movement variation
heightmap_reader.set_walkable_margin(30.0)  # ±30px range

# Set tile scale for tiling backgrounds
heightmap_reader.set_tile_scale(2.0)

# Get exact walkable Y (no margin)
var exact_y = heightmap_reader.get_exact_walkable_y(screen_x, viewport_size)
```

## How It Works

### Image Analysis
1. Load background image with PIL
2. Scan each X coordinate from top to bottom
3. Find first opaque pixel matching terrain criteria
4. Record Y position for that X
5. Output as dictionary mapping X → Y

### Runtime Interpolation
1. Convert screen X to background image X (accounting for tiling)
2. Find two nearest heightmap samples (e.g., X=200 and X=210)
3. Interpolate between them for smooth curve
4. Scale from image coordinates to screen coordinates
5. Return Y bounds with margin for variation

### Coordinate Spaces
- **Image Space**: Original background PNG dimensions (e.g., 640x384)
- **Screen Space**: Actual game viewport (e.g., 1152x648)
- **Tiling Space**: Repeating pattern if background uses tile shader

The `HeightmapReader` handles all conversions automatically.

## Example: Rolling Hills Background

See `afk/nodes/background/rolling_hills/` for complete implementation:

- Extracted from `background4.png` (640x384)
- 64 sample points (X=0 to X=630, every 10px)
- Y range: 234-300 (66px of vertical variation)
- Used with 3x tiling shader
- ±20px walkable margin

Result: NPCs naturally follow the rolling hill contours!

## Troubleshooting

**Q: All Y values are the same**
A: Your image might be fully opaque or the detection threshold is wrong. Try adjusting `GREEN_THRESHOLD` or customize `is_green_pixel()`.

**Q: NPCs appear in wrong positions**
A: Check that `BG_IMAGE_WIDTH` and `BG_IMAGE_HEIGHT` match your actual image dimensions. Verify `tile_scale` matches your shader parameter.

**Q: Movement looks choppy**
A: Decrease `SAMPLE_INTERVAL` for more sample points, or increase `walkable_margin` for smoother transitions.

**Q: Script runs too slow**
A: Use `extract_bounds_fast.py` with PGM alpha channel extraction, or increase `SAMPLE_INTERVAL`.

## Future Enhancements

- Support for multiple heightmap layers (platforms, flying, underground)
- Dynamic heightmap updates for destructible terrain
- Slope angle calculation for movement speed adjustment
- Integration with pathfinding systems
- Visual debug overlay to preview heightmap curve
