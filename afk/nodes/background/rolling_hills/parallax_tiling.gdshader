shader_type canvas_item;

uniform float scroll_offset = 0.0;
uniform vec2 texture_size = vec2(640.0, 384.0);  // Size of the texture in pixels
uniform vec2 screen_size = vec2(1152.0, 648.0);  // Size of the screen/container

void fragment() {
	// Calculate the aspect-corrected UV coordinates
	vec2 uv = UV;

	// Scale UV to maintain aspect ratio and tile horizontally
	float aspect_ratio = texture_size.y / texture_size.x;
	float screen_aspect = screen_size.y / screen_size.x;

	// Scale to fit screen height while maintaining aspect ratio
	float scale = screen_size.y / texture_size.y;

	// Adjust UV coordinates
	uv.x *= screen_size.x / (texture_size.x * scale);

	// Add scroll offset for horizontal parallax
	// Divide by tile width (640 * 1.6875 = 1080) to convert pixels to UV units
	uv.x += scroll_offset / 1080.0;

	// Wrap only X coordinate for horizontal tiling
	uv.x = fract(uv.x);

	// Sample the texture
	vec4 tex_color = texture(TEXTURE, uv);

	COLOR = tex_color;
}
