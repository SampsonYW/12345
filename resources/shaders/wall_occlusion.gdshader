shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 1.0;

uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float radius = 1.8; // 稍微收紧半径，避免非遮挡区域触发
uniform float min_alpha = 0.4;

void fragment() {
    ALBEDO = albedo.rgb;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // 计算摄像机到玩家的视线向量
    vec3 cam_to_player = player_pos - camera_pos;
    vec3 cam_to_frag = world_pos - camera_pos;
    
    // 将当前像素投影到视线上，求出比例 t
    // t=0 表示在摄像机位置，t=1 表示在玩家位置
    float t = dot(cam_to_frag, cam_to_player) / dot(cam_to_player, cam_to_player);
    
    float alpha = 1.0;
    
    // 只有当像素严格位于摄像机和玩家“之间”时 (t <= 1.0) 才考虑剔除
    // 这样完美避免了“站在墙前（非遮挡）但背后的墙变透明”的错误
    if (t > 0.0 && t <= 1.0) {
        // 计算像素到视线连线的垂直距离，形成一个贯穿视角的圆柱形隧道
        vec3 closest_point = camera_pos + t * cam_to_player;
        float dist_to_line = distance(world_pos, closest_point);
        
        // 只有在隧道半径范围内的墙体才会被挖洞
        if (dist_to_line < radius) {
            float fade = smoothstep(radius * 0.4, radius, dist_to_line);
            alpha = mix(min_alpha, 1.0, fade);
        }
    }
    
    // 采用 Bayer 矩阵在屏幕空间做像素级抖动剔除 (Dither Discard)
    if (alpha < 0.99) {
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        int index = x + y * 4;
        
        float limit = 0.0;
        if (index == 0) limit = 0.0625;
        else if (index == 1) limit = 0.5625;
        else if (index == 2) limit = 0.1875;
        else if (index == 3) limit = 0.6875;
        else if (index == 4) limit = 0.8125;
        else if (index == 5) limit = 0.3125;
        else if (index == 6) limit = 0.9375;
        else if (index == 7) limit = 0.4375;
        else if (index == 8) limit = 0.25;
        else if (index == 9) limit = 0.75;
        else if (index == 10) limit = 0.125;
        else if (index == 11) limit = 0.625;
        else if (index == 12) limit = 1.0;
        else if (index == 13) limit = 0.5;
        else if (index == 14) limit = 0.875;
        else if (index == 15) limit = 0.375;
        
        if (alpha < limit) {
            discard;
        }
    }
}
