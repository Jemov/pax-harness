shader_type spatial;
render_mode diffuse_burley;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	// Small local fill keeps authored geometry readable on the unlit side of space.
	EMISSION = COLOR.rgb * 0.18;
}
