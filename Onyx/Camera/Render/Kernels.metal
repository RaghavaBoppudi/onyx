#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
namespace coreimage {

float4 monoBlueFilter(sample_t image, float strength) {
    float baseLuma = dot(image.rgb, float3(0.2126, 0.7152, 0.0722));
    float blueBias = image.b - max(image.r, image.g);
    float darken = clamp(blueBias, 0.0, 1.0) * strength;
    float gray = clamp(baseLuma - darken, 0.0, 1.0);
    return float4(gray, gray, gray, image.a);
}

}
}
