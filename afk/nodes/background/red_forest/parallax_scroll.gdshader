shader_type canvas_item;

uniform float scroll_offset = 0.0;

void fragment() {
	// Offset the UV coordinates based on scroll
	vec2 uv = UV;
	uv.x += scroll_offset / 1000.0; // Divide to control scroll speed

	// Wrap UV coordinates to prevent glitching at boundaries
	uv.x = fract(uv.x);

	// Sample the texture with wrapped coordinates
	COLOR = texture(TEXTURE, uv);
}
