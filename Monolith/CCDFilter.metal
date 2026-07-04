#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

extern "C" {
    namespace coreimage {
        float4 ccd_monochrome(sample_t inColor) {
            // 1. Heavy Green Bias (15% R, 75% G, 10% B)
            float luminance = dot(inColor.rgb, float3(0.15, 0.75, 0.10));
            
            // 2. Hard Highlight Clipping (flatline at 85% luminance)
            if (luminance > 0.85) {
                luminance = 1.0;
            } else {
                luminance = luminance * (1.0 / 0.85); // Linear ramp up to the clip point
            }
            
            return float4(luminance, luminance, luminance, 1.0);
        }
    }
}
