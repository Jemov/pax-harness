shader_type canvas_item;
render_mode unshaded;

uniform float extent = 98.0;
uniform int sector_count = 0;
uniform vec4 sector_shapes[12]; // offset.xy, radius, angular span
uniform vec4 sector_edges[12]; // start.xy, end.xy
uniform vec4 sector_colors[12] : source_color;

void fragment() {
    vec2 point = (UV - vec2(0.5)) * extent * 2.0;
    vec3 premultiplied = vec3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 12; i++) {
        if (i >= sector_count) { break; }
        vec4 shape = sector_shapes[i];
        if (shape.w <= 0.0) { continue; }
        vec2 p = point - shape.xy;
        float distance_to_edge = length(p) - shape.z;
        if (shape.w < 6.28318) {
            vec4 edge = sector_edges[i];
            float from_start = edge.y * p.x - edge.x * p.y;
            float past_end = edge.z * p.y - edge.w * p.x;
            float sector_distance = shape.w <= 3.141592654 ? max(from_start, past_end) : min(from_start, past_end);
            distance_to_edge = max(distance_to_edge, sector_distance);
        }
        float pixel_width = max(fwidth(distance_to_edge), 0.0001);
        float coverage = 1.0 - smoothstep(-0.5 * pixel_width, 0.5 * pixel_width, distance_to_edge);
        float weight = sector_colors[i].a * coverage;
        premultiplied += sector_colors[i].rgb * weight;
        alpha += weight;
    }
    // Resolve adjoining sectors together, before blending with the background.
    // Two half-covered sectors form an opaque join instead of a dark alpha seam.
    vec4 pie = vec4(premultiplied / max(alpha, 0.00001), min(alpha, 1.0));
    COLOR *= pie;
}
