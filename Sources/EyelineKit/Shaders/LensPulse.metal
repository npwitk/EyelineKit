#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// A single refraction wave that travels out from the lens, like the one iOS plays around the
/// under-display camera when it turns on. Content is sampled at an offset, so whatever is on
/// screen bends as the wave passes: pushed outward on the wave's leading half, pulled back on
/// its trailing half, with a faint highlight and shade to sell the glassy edge.
///
/// - origin: the lens centre, in the view's coordinates
/// - elapsed: seconds since the pulse started
/// - speed: how fast the wave front travels, in points per second
/// - width: thickness of the wave, in points
/// - strength: maximum displacement, in points
[[ stitchable ]] half4 eyelineLensPulse(float2 position, SwiftUI::Layer layer,
                                        float2 origin, float elapsed,
                                        float speed, float width, float strength) {
    float2 delta = position - origin;
    float d = length(delta);
    float2 dir = d > 0.001 ? delta / d : float2(0.0);

    // Where this point sits relative to the wave front, in wave widths.
    float x = (d - elapsed * speed) / width;
    // Derivative of a Gaussian: one smooth push-and-pull across the front, zero elsewhere.
    float wave = -x * exp(-x * x) * 1.65;

    // The wave dies out over time and weakens as it spreads.
    float fade = exp(-elapsed * 2.6);
    float spread = 1.0 / (1.0 + d / 360.0);
    float amount = strength * wave * fade * spread;

    half4 color = layer.sample(position - dir * amount);
    color.rgb += half(0.10 * wave * fade * spread) * color.a;
    return color;
}
