#!/usr/bin/env python3
"""
Extract walkable bounds from background4.png alpha channel
Finds the topmost opaque pixel at regular X intervals
"""

import subprocess
import json

IMAGE_PATH = "background4.png"
WIDTH = 640
HEIGHT = 384
SAMPLE_INTERVAL = 10  # Sample every 10 pixels

def get_pixel_alpha(x, y):
    """Get alpha value at specific pixel using ImageMagick"""
    cmd = f"magick {IMAGE_PATH} -format '%[pixel:p{{{x},{y}}}]' info:"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    pixel_data = result.stdout.strip()

    # Parse alpha from rgba(r,g,b,a) format
    if 'rgba' in pixel_data:
        alpha = pixel_data.split(',')[-1].strip(')')
        return float(alpha)
    return 0.0

def find_top_opaque_pixel(x):
    """Find the topmost opaque pixel (alpha > 0.5) at given X coordinate"""
    # Start from top and scan downward
    for y in range(HEIGHT):
        alpha = get_pixel_alpha(x, y)
        if alpha > 0.5:  # Consider >50% alpha as opaque
            return y
    return HEIGHT - 1  # Default to bottom if no opaque pixel found

def main():
    heightmap = {}

    print(f"Analyzing {IMAGE_PATH}...")
    print(f"Dimensions: {WIDTH}x{HEIGHT}")
    print(f"Sampling every {SAMPLE_INTERVAL}px")

    # Sample at regular intervals
    for x in range(0, WIDTH, SAMPLE_INTERVAL):
        top_y = find_top_opaque_pixel(x)
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

if __name__ == "__main__":
    main()
