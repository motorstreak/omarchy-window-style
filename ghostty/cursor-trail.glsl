// Cursor trail for Ghostty, like Kitty's cursor_trail (Window Style plugin,
// Terminal tab). When the cursor jumps 2+ cells, a fading streak follows it.

const float DURATION = 0.22; // seconds for the trail to catch up and fade
const float OPACITY  = 0.55; // trail strength at the start

float segmentDistance(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);

    // Cursor rects: xy = top-left corner, zw = width/height (pixels).
    vec2 cur  = iCurrentCursor.xy  + vec2(iCurrentCursor.z,  -iCurrentCursor.w)  * 0.5;
    vec2 prev = iPreviousCursor.xy + vec2(iPreviousCursor.z, -iPreviousCursor.w) * 0.5;
    float h = iCurrentCursor.w;

    // Skip small moves such as typing one character.
    if (distance(cur, prev) < h) return;

    float t = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    if (t >= 1.0) return;

    float ease = 1.0 - pow(1.0 - t, 3.0);         // ease-out
    vec2 tail = mix(prev, cur, ease);              // tail chases the cursor
    float radius = h * 0.35 * (1.0 - 0.5 * t);     // thins as it fades

    float d = segmentDistance(fragCoord, tail, cur) - radius;
    float alpha = (1.0 - smoothstep(-1.0, 1.0, d)) * OPACITY * (1.0 - t);

    fragColor.rgb = mix(fragColor.rgb, iCurrentCursorColor.rgb, alpha);
}
