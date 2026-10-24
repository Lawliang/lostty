#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Lostty's absorb (CanvasAbsorb.swift): a window dropped on the canvas's
// title bar falls into the point it was let go at, as into liquid glass.
// As `progress` runs 0 → 1 each pixel draws from farther from `target`,
// so the window shrinks into it, the parts nearest going first, like
// water down a drain; it twists a little round the point, and its colors
// split at the edges, as light does through the edge of glass. `reach`
// is how far the window's farthest corner is from the point.

namespace {
    // Where `position` samples from, pulled by `pull` (how far everything
    // has slid in, as a share of `reach`) and twisted by `twist` radians.
    float2 drawnFrom(float2 position, float2 target, float reach, float pull, float twist) {
        float2 offset = position - target;
        float u = length(offset) / reach;
        // Near the point the window is squeezed hardest; far out it only
        // slides in. 0.08 keeps the point itself finite.
        float k = 1.0 + pull / (u + 0.08);
        float angle = twist * exp(-3.0 * u);
        float2 turned = float2(offset.x * cos(angle) - offset.y * sin(angle),
                               offset.x * sin(angle) + offset.y * cos(angle));
        return target + turned * k;
    }
}

[[ stitchable ]] half4 losttyAbsorb(float2 position, SwiftUI::Layer layer, float2 target, float progress, float reach) {
    float t = clamp(progress, 0.0, 1.0);
    // Slow to start, then faster and faster into the point.
    float e = t * t * (1.6 - 0.6 * t);
    float pull = 1.25 * e;
    float twist = 0.9 * e;
    // Red pulled a little less and blue a little more: a warm fringe on
    // the outside, cyan on the inside, as on Apple Music's glass.
    float split = 0.07 * e;
    half4 red = layer.sample(drawnFrom(position, target, reach, pull * (1.0 - split), twist));
    half4 green = layer.sample(drawnFrom(position, target, reach, pull, twist));
    half4 blue = layer.sample(drawnFrom(position, target, reach, pull * (1.0 + split), twist));
    half alpha = max(green.a, max(red.a, blue.a));
    half3 color = half3(red.r, green.g, blue.b);
    // Brighter as it's squeezed in, as if the light gathers there.
    color += half3(alpha * half(0.4 * e));
    half fade = half(1.0 - smoothstep(0.82, 1.0, t));
    return half4(color, alpha) * fade;
}
