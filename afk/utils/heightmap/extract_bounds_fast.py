#!/usr/bin/env python3
"""
Extract walkable bounds from background4.png alpha channel (FAST version)
Reads alpha channel PGM file and finds topmost opaque pixel at each X
"""

import json

IMAGE_PATH = "alpha_channel.pgm"
SAMPLE_INTERVAL = 10  # Sample every 10 pixels
ALPHA_THRESHOLD = 128  # 50% opacity threshold (0-255)

def main():
    print("Reading alpha channel...")

    with open(IMAGE_PATH, 'rb') as f:
        # Read PGM header
        magic = f.readline().strip()

        # Skip comments
        line = f.readline()
        while line.startswith(b'#'):
            line = f.readline()

        # Read dimensions
        width, height = map(int, line.split())
        max_val = int(f.readline().strip())

        print(f"Dimensions: {width}x{height}")
        print(f"Max value: {max_val}")

        # Read pixel data
        pixels = f.read()

    heightmap = {}

    # Convert to 2D array for easier access
    alpha = []
    for y in range(height):
        row = []
        for x in range(width):
            idx = y * width + x
            row.append(pixels[idx])
        alpha.append(row)

    print(f"Sampling every {SAMPLE_INTERVAL}px...")

    # Sample at regular intervals
    for x in range(0, width, SAMPLE_INTERVAL):
        # Find topmost opaque pixel at this X
        top_y = height - 1  # Default to bottom

        for y in range(height):
            if alpha[y][x] > ALPHA_THRESHOLD:
                top_y = y
                break

        heightmap[x] = top_y
        print(f"X={x:3d}: Y={top_y:3d}")

    # Save as JSON
    output_file = "walkable_heightmap.json"
    with open(output_file, 'w') as f:
        json.dump(heightmap, f, indent=2)

    print(f"\nHeightmap saved to {output_file}")

    # Print stats
    y_values = list(heightmap.values())
    print(f"\nStats:")
    print(f"  Min Y (highest point): {min(y_values)}")
    print(f"  Max Y (lowest point): {max(y_values)}")
    print(f"  Range: {max(y_values) - min(y_values)} pixels")

    # Print GDScript format
    print(f"\n# GDScript format:")
    print(f"const WALKABLE_HEIGHTMAP = {{")
    for x, y in sorted(heightmap.items()):
        print(f"    {x}: {y},")
    print(f"}}")

if __name__ == "__main__":
    main()
