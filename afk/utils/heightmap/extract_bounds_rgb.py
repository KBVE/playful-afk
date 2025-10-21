#!/usr/bin/env python3
"""
Extract exact terrain curve from background4.png
Finds every X position where the pixel above is transparent and pixel below is opaque
This gives us the exact boundary curve of the terrain
"""

from PIL import Image
import json

IMAGE_PATH = "../../nodes/background/rolling_hills/background4.png"
ALPHA_THRESHOLD = 50  # Minimum alpha value to consider as "opaque"

def is_transparent(pixel):
    """Check if pixel is transparent"""
    if len(pixel) == 4:
        r, g, b, a = pixel
        return a <= ALPHA_THRESHOLD
    else:
        return False

def is_opaque(pixel):
    """Check if pixel is opaque (not transparent)"""
    if len(pixel) == 4:
        r, g, b, a = pixel
        return a > ALPHA_THRESHOLD
    else:
        return True

def main():
    print(f"Loading {IMAGE_PATH}...")
    img = Image.open(IMAGE_PATH)
    width, height = img.size

    print(f"Dimensions: {width}x{height}")
    print(f"Mode: {img.mode}")
    print(f"Finding exact terrain boundary (transparent above, opaque below)...")

    terrain_curve = []

    # Scan every X position
    for x in range(width):
        # Find the exact boundary: transparent above, opaque below
        boundary_y = None

        for y in range(height - 1):
            pixel_current = img.getpixel((x, y))
            pixel_below = img.getpixel((x, y + 1))

            # Found the boundary: current is transparent, below is opaque
            if is_transparent(pixel_current) and is_opaque(pixel_below):
                boundary_y = y + 1  # The opaque pixel is the start of walkable area
                break

        if boundary_y is not None:
            terrain_curve.append({"x": x, "y": boundary_y})
        else:
            # No boundary found, likely entire column is opaque or transparent
            # Find first opaque pixel as fallback
            for y in range(height):
                if is_opaque(img.getpixel((x, y))):
                    terrain_curve.append({"x": x, "y": y})
                    break

    print(f"Found {len(terrain_curve)} boundary points")

    # Save as JSON array
    output_file = "terrain_curve.json"
    with open(output_file, 'w') as f:
        json.dump(terrain_curve, f, indent=2)

    print(f"\nTerrain curve saved to {output_file}")

    # Print stats
    y_values = [p["y"] for p in terrain_curve]
    print(f"\nStats:")
    print(f"  Min Y (highest point): {min(y_values)}")
    print(f"  Max Y (lowest point): {max(y_values)}")
    print(f"  Range: {max(y_values) - min(y_values)} pixels")

    # Print GDScript format (PackedVector2Array for exact curve)
    print(f"\n# GDScript PackedVector2Array (copy to rolling_hills_background.gd):")
    print(f"const TERRAIN_CURVE: Array[Vector2] = [")

    for i, point in enumerate(terrain_curve):
        if i % 4 == 0:
            print(f"\t", end="")
        print(f"Vector2({point['x']}, {point['y']})", end="")
        if i < len(terrain_curve) - 1:
            print(", ", end="")
        if (i + 1) % 4 == 0 and i < len(terrain_curve) - 1:
            print()  # New line every 4 items
    print(f"\n]")

    print(f"\n# Total points: {len(terrain_curve)} (exact curve, one point per X pixel)")

    # Generate a smooth curve that stays ABOVE all terrain points
    print(f"\n{'='*60}")
    print(f"SAFE BOUNDARY CURVE GENERATION")
    print(f"{'='*60}")

    import numpy as np
    from scipy.optimize import curve_fit

    # Convert to numpy arrays
    x_data = np.array([p["x"] for p in terrain_curve])
    y_data = np.array([p["y"] for p in terrain_curve])

    # Try fitting a Fourier series (sum of sine/cosine waves)
    # This captures the rolling hills pattern perfectly
    def fourier_curve(x, a0, a1, b1, a2, b2, a3, b3):
        """Fourier series: a0 + sum of (a_n*cos + b_n*sin) terms"""
        freq = 2 * np.pi / width  # One cycle across the image
        return (a0 +
                a1 * np.cos(freq * x) + b1 * np.sin(freq * x) +
                a2 * np.cos(2 * freq * x) + b2 * np.sin(2 * freq * x) +
                a3 * np.cos(3 * freq * x) + b3 * np.sin(3 * freq * x))

    # Fit the curve to the terrain data
    print(f"\nFitting Fourier series to terrain data...")
    params, _ = curve_fit(fourier_curve, x_data, y_data)

    print(f"Fitted parameters: a0={params[0]:.2f}, a1={params[1]:.2f}, b1={params[2]:.2f}")
    print(f"                   a2={params[3]:.2f}, b2={params[4]:.2f}, a3={params[5]:.2f}, b3={params[6]:.2f}")

    # Evaluate the fitted curve
    y_fitted = fourier_curve(x_data, *params)

    # Add a safety margin (shift curve down so it's always ABOVE terrain)
    max_error = np.max(y_data - y_fitted)
    safety_margin = max_error + 5  # Add 5px extra margin

    print(f"\nMax error: {max_error:.2f} pixels")
    print(f"Safety margin: {safety_margin:.2f} pixels")

    # Adjusted parameters (shift a0 down)
    safe_params = params.copy()
    safe_params[0] -= safety_margin

    # Verify the safe curve is above all terrain
    y_safe = fourier_curve(x_data, *safe_params)
    min_clearance = np.min(y_data - y_safe)
    max_clearance = np.max(y_data - y_safe)

    print(f"Clearance range: {min_clearance:.2f} to {max_clearance:.2f} pixels")
    print(f"All points above terrain: {np.all(y_safe <= y_data)}")

    # Print GDScript formula
    print(f"\n# GDScript Walkable Boundary (Fourier curve):")
    print(f"# Returns the Y value of the safe boundary at any X position")
    print(f"# NPCs should stay BELOW this curve (Y > boundary_y)")
    print(f"func get_safe_boundary_y(x: float) -> float:")
    print(f"\tvar freq = 2.0 * PI / {width}.0")
    print(f"\treturn ({safe_params[0]:.6f} + ")
    print(f"\t        {safe_params[1]:.6f} * cos(freq * x) + {safe_params[2]:.6f} * sin(freq * x) +")
    print(f"\t        {safe_params[3]:.6f} * cos(2.0 * freq * x) + {safe_params[4]:.6f} * sin(2.0 * freq * x) +")
    print(f"\t        {safe_params[5]:.6f} * cos(3.0 * freq * x) + {safe_params[6]:.6f} * sin(3.0 * freq * x))")

if __name__ == "__main__":
    main()
