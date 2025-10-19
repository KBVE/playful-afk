shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// Sample the texture
	vec4 tex_color = texture(TEXTURE, UV);

	// Apply tint color multiplication to the texture
	// This preserves the texture details while applying the color
	COLOR = tex_color * tint_color;
}
