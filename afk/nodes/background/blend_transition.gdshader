shader_type canvas_item;

// Blend transition shader - creates smooth gradient between ground and sky views
// Samples the top of ground background and bottom of sky background
// Uses vertical gradient mask to blend them together

uniform sampler2D ground_texture : hint_default_white;
uniform sampler2D sky_texture : hint_default_white;
uniform float blend_height : hint_range(0.0, 1.0) = 0.5;  // How much of the transition area to use
uniform float gradient_softness : hint_range(0.1, 1.0) = 0.3;  // How soft the gradient is

void fragment() {
	vec2 uv = UV;

	// Calculate gradient mask (0 at bottom = ground, 1 at top = sky)
	float gradient = smoothstep(blend_height - gradient_softness, blend_height + gradient_softness, uv.y);

	// Sample from ground (top portion) and sky (bottom portion)
	// For ground, we want to sample from the TOP of the texture (near 0.0 y)
	vec2 ground_uv = vec2(uv.x, uv.y * 0.2);  // Sample top 20% of ground

	// For sky, we want to sample from the BOTTOM of the texture (near 1.0 y)
	vec2 sky_uv = vec2(uv.x, 0.8 + uv.y * 0.2);  // Sample bottom 20% of sky

	vec4 ground_color = texture(ground_texture, ground_uv);
	vec4 sky_color = texture(sky_texture, sky_uv);

	// Blend between ground and sky based on gradient
	vec4 blended = mix(ground_color, sky_color, gradient);

	COLOR = blended;
}
