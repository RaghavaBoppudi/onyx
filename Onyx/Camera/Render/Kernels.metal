#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
namespace coreimage {

float2 flutedGlassWarp(float sectionWidth, float maxDisplacement, float2 axis, destination dest) {
    float2 position = dest.coord();
    float coord = dot(position, axis);
    float localCoord = (fract(coord / sectionWidth) - 0.5) * 2.0;
    float offset = localCoord * localCoord * localCoord * maxDisplacement;
    return position + axis * offset;
}

float4 flutedGlassShading(
    sample_t image,
    float sectionWidth,
    float shadingStrength,
    float shadingSharpness,
    float2 axis,
    destination dest
) {
    float coord = dot(dest.coord(), axis);
    float localCoord = (fract(coord / sectionWidth) - 0.5) * 2.0;
    float shade = sign(localCoord) * pow(abs(localCoord), shadingSharpness) * shadingStrength;
    float3 shaded = image.rgb * (1.0 + shade);
    return float4(clamp(shaded, 0.0, 1.0), image.a);
}

float4 monoBlueFilter(sample_t image, float strength) {
    float baseLuma = dot(image.rgb, float3(0.2126, 0.7152, 0.0722));
    float blueBias = image.b - max(image.r, image.g);
    float darken = clamp(blueBias, 0.0, 1.0) * strength;
    float gray = clamp(baseLuma - darken, 0.0, 1.0);
    return float4(gray, gray, gray, image.a);
}

}
}
