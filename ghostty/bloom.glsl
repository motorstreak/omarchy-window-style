// Bloom for Ghostty (Window Style plugin, Terminal tab): text and the cursor
// glow softly into the background around them. The plugin writes this out
// with STRENGTH and SIZE filled in from the panel.
//
// The glow takes the colour of what's nearby that stands out from the
// background, so it brightens on dark themes and stays soft on light ones.

const float STRENGTH = @STRENGTH@; // how strong the glow is, 0 to 1
const float SIZE     = @SIZE@;     // how far it reaches, in pixels

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px = 1.0 / iResolution.xy;
    vec2 uv = fragCoord * px;
    vec4 base = texture(iChannel0, uv);
    vec3 bg = iBackgroundColor.rgb;

    // Three rings of 12 samples, nearer rings weighing more.
    vec3 colour = vec3(0.0);
    float lit = 0.0;
    float total = 0.0;
    for (int ring = 1; ring <= 3; ring++) {
        float r = SIZE * float(ring) / 3.0;
        float w = exp(-float(ring * ring) / 4.5);
        for (int i = 0; i < 12; i++) {
            float a = 6.2831853 * (float(i) + 0.5 * float(ring)) / 12.0;
            vec3 c = texture(iChannel0, uv + vec2(cos(a), sin(a)) * r * px).rgb;
            // How much this sample stands out from the background.
            float k = smoothstep(0.08, 0.45, distance(c, bg)) * w;
            colour += c * k;
            lit += k;
            total += w;
        }
    }
    if (lit <= 0.0) {
        fragColor = base;
        return;
    }
    vec3 glow = colour / lit - bg;    // the nearby text's colour, from the background
    float amount = lit / total;       // how much text is nearby
    fragColor = vec4(clamp(base.rgb + glow * amount * STRENGTH, 0.0, 1.0), base.a);
}
