#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
    float pointSize [[point_size]];
};

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float3x3 normalMatrix;
    float pointSize;
};

vertex VertexOut vertex_main(VertexIn vertexIn [[stage_in]],
                           constant Uniforms& uniforms [[buffer(2)]]) {
    VertexOut vertexOut;
    vertexOut.position = uniforms.modelViewProjectionMatrix * float4(vertexIn.position, 1.0);
    vertexOut.color = vertexIn.color;
    vertexOut.pointSize = uniforms.pointSize;
    return vertexOut;
}

fragment float4 fragment_main(VertexOut fragmentIn [[stage_in]],
                            float2 pointCoord [[point_coord]]) {
    float distance = length(pointCoord - 0.5);
    if (distance > 0.5) {
        discard_fragment();
    }

    float alpha = 1.0 - smoothstep(0.3, 0.5, distance);
    return float4(fragmentIn.color, alpha);
}