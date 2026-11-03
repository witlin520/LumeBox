#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 u_imageSize;
uniform vec4 u_source;
uniform vec4 u_destination;
uniform vec3 u_adjustments; // gamma, sharpness, denoise
uniform sampler2D u_image;
out vec4 fragColor;

vec4 corrected(vec2 pixel) {
  vec4 value = texture(u_image, clamp(pixel / u_imageSize,
      .5 / u_imageSize, (u_imageSize - .5) / u_imageSize));
  vec3 rgb = value.a > .0001 ? value.rgb / value.a : vec3(0.);
  rgb = floor(pow(max(rgb, vec3(0.)), vec3(1. / u_adjustments.x)) * 255. + .5) / 255.;
  return vec4(rgb, value.a);
}

void main() {
  vec2 pixel = u_source.xy + (FlutterFragCoord().xy - u_destination.xy)
      / u_destination.zw * u_source.zw;
  vec4 center = corrected(pixel);
  vec3 sum = center.rgb;
  vec3 count = vec3(1.);
  for (int i = 0; i < 4; i++) {
    vec2 stepSize = i == 0 ? vec2(-1., 0.) : i == 1 ? vec2(1., 0.)
        : i == 2 ? vec2(0., -1.) : vec2(0., 1.);
    vec3 value = corrected(pixel + stepSize).rgb;
    vec3 keep = u_adjustments.z > .5
        ? vec3(1.) - step(vec3(28. / 255.), abs(value - center.rgb)) : vec3(1.);
    sum += value * keep;
    count += keep;
  }
  vec3 average = sum / count;
  vec3 smoothed = u_adjustments.z > .5 ? mix(center.rgb, average, .6) : center.rgb;
  vec3 result = clamp(smoothed + u_adjustments.y * (center.rgb - average), 0., 1.);
  if (pixel.x < 1. || pixel.y < 1. || pixel.x >= u_imageSize.x - 1.
      || pixel.y >= u_imageSize.y - 1.) result = center.rgb;
  result = floor(result * 255. + .5) / 255.;
  fragColor = vec4(result * center.a, center.a);
}
