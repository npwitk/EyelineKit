#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Soft rings that travel outward from the lens, plus a glow around it. Everything fades with
/// distance, so the screen edges stay calm and the eye is pulled back toward the camera.
///
/// - center: the lens centre, in the view's coordinates
/// - time: seconds; drives the rings
/// - tint: ring colour (premultiplied output)
/// - reach: distance at which the effect has faded out
/// - burst: 0…1, extra intensity right after the instruction changes
/// - motion: 0 for a static glow (Reduce Motion), 1 for moving rings
[[ stitchable ]] half4 eyelineLensRipple(float2 position, half4 color,
                                        float2 center, float time, half4 tint,
                                        float reach, float burst, float motion) {
    float d = distance(position, center);
    float fade = 1.0 - smoothstep(0.0, reach, d);

    // Rings move outward: a crest sits where (d - time * speed) / spacing ≡ 0.5 (mod 1).
    float speed = 70.0;
    float spacing = 64.0;
    float f = fract((d - time * speed) / spacing);
    float ring = pow(saturate(1.0 - abs(f - 0.5) * 2.0), 14.0) * motion;

    float glow = exp(-d / 55.0);
    float alpha = (ring * (0.32 + burst * 0.45) + glow * (0.30 + burst * 0.30)) * fade;
    alpha = saturate(alpha);
    return half4(tint.rgb * half(alpha), half(alpha));
}
