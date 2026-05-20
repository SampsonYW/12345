shader_type 3d;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx, unshaded;

uniform vec3 player_position;
uniform float vision_radius;
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.65;
uniform vec4 fog_color : source_color = vec4(0.05, 0.06, 0.08, 1.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(world_position.xz, player_position.xz);
	// Smooth transition from fully transparent to semi-transparent fog
	float mask = smoothstep(vision_radius - 1.5, vision_radius, d);
	
	ALBEDO = fog_color.rgb;
	ALPHA = mask * fog_opacity;
}
