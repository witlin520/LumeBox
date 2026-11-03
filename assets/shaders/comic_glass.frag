#include <flutter/runtime_effect.glsl>
uniform vec2 u_size;
uniform vec4 u_bounds;
uniform float u_radius;
uniform float u_strength;
uniform sampler2D u_backdrop;
out vec4 fragColor;

vec2 textureUV(vec2 pixel) {
  vec2 uv = clamp(pixel / u_size, .5 / u_size, (u_size - .5) / u_size);
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1. - uv.y;
#endif
  return uv;
}

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 halfSize = u_bounds.zw * .5;
  vec2 p = coord - u_bounds.xy - halfSize;
  float radius = min(u_radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - halfSize + radius;
  float distanceToEdge = length(max(q, 0.)) + min(max(q.x, q.y), 0.) - radius;
  vec2 n = q.x > 0. && q.y > 0. ? normalize(max(q, .0001))
      : (q.x > q.y ? vec2(1., 0.) : vec2(0., 1.));
  n *= sign(p);
  float rim = 1. - smoothstep(0., max(1., radius * .7), -distanceToEdge);
  vec2 samplePosition = coord - n * radius * u_strength * rim * rim;
  vec2 dispersion = n * rim * rim * .35;
  vec4 color = texture(u_backdrop, textureUV(samplePosition));
  color.r = texture(u_backdrop, textureUV(samplePosition + dispersion)).r;
  color.b = texture(u_backdrop, textureUV(samplePosition - dispersion)).b;
  fragColor = color;
}
