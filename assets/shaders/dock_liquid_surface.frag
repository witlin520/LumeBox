#include <flutter/runtime_effect.glsl>

// Base glass surface of the dock.
//
// Applied as the outer filter of:
//   ImageFilter.compose(outer: this, inner: ImageFilter.blur)
// The blur is produced by the engine from the *raw* backdrop; this shader then
// masks the frosted result so the lens region stays clear. Because the frosted
// layer becomes nearly transparent in the lens core, the untouched page below
// shows through and the lens pass keeps real background detail.
//
// Uniforms are grouped in vec4 blocks: Flutter packs image-filter uniforms by
// declaration order, and vec4 blocks keep the float indexes unambiguous.
uniform vec2 u_size;
// Lens rectangle in physical pixels: xy = top-left, zw = size.
uniform vec4 u_lens;
// radius, feather, clarity, tint
uniform vec4 u_shape;
// core alpha, tint r, g, b
uniform vec4 u_glass;
// background light adaptation amount (0 = fixed tint, 1 = fully adaptive)
uniform float u_adapt;
uniform sampler2D u_base;

out vec4 fragColor;

float sdRoundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + vec2(radius);
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 uv = clamp(coord / u_size, vec2(0.0001), vec2(0.9999));
  vec4 base = texture(u_base, uv);

  vec2 halfSize = u_lens.zw * 0.5;
  vec2 center = u_lens.xy + halfSize;
  float radius = min(u_shape.x, min(halfSize.x, halfSize.y));
  float d = sdRoundedBox(coord - center, halfSize, radius);
  // 1 inside the lens core, 0 outside the soft transition band.
  float inside = 1.0 - smoothstep(-u_shape.y, u_shape.y, d);
  float clarity = clamp(inside * u_shape.z, 0.0, 1.0);

  // Outside: opaque frosted glass (white tint over blurred page).
  // Inside: only a faint glass veil; the rest is the untouched page below.
  // frost = 1 at rest; it only drops toward u_glass.x inside the lens core.
  float frost = mix(1.0, u_glass.x, clarity);
  // 背景明暗联动：背景越暗，玻璃越偏白以保住图标/文字对比度；亮背景
  // 回到设定白度，避免整条变成一块更厚的白板。过渡连续，不跳变。
  float bgLuma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
  float lightAdapt = mix(1.25, 1.0, smoothstep(0.05, 0.85, bgLuma));
  float adapt = mix(1.0, lightAdapt, clamp(u_adapt, 0.0, 1.0));
  // 背景颜色联动：高饱和内容让白度略降，让玻璃保留背景色相，避免所有
  // 花色海报都被统一糊成灰白。
  float hi = max(max(base.r, base.g), base.b);
  float lo = min(min(base.r, base.g), base.b);
  float backgroundSaturation = clamp((hi - lo) * 2.5, 0.0, 1.0);
  float colorKeep = mix(
    1.0,
    0.82,
    backgroundSaturation * clamp(u_adapt, 0.0, 1.0)
  );
  float tint = clamp(
    u_shape.w * (1.0 - clarity) * adapt * colorKeep,
    0.0,
    1.0
  );
  vec3 rgb = mix(base.rgb, u_glass.yzw, tint);
  fragColor = vec4(rgb * frost, frost);
}
