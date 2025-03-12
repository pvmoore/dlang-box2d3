[require(GL_EXT_debug_printf)]

struct UBO {
    float4x4 viewProj;
};

[[vk::binding(0, 0)]] ConstantBuffer<UBO> ubo;

[shader("vertex")]
VSOutput vsmain(uint shapeType,
                float2 modelPos,
                float2 translation,
                float2 size,
                float anticlockwiseRadians,
                float4 innerColour,
                float4 outerColour,
                uint vertexId : SV_VertexID) 
{
    float clockwiseRadians = -anticlockwiseRadians;
    
    //           Rotation                    Scale              Translation
    //
    // [cos(angle), -sin(angle), 0]   [size.x,      0, 0]   [1, 0, translation.x]
    // [sin(angle),  cos(angle), 0] x [     0, size.y, 0] x [0, 1, translation.y]
    // [         0,           0, 1]   [     0,      0, 1]   [0, 0, 1            ]
    //
    let modelTransform:float3x3 = {
        size.x * cos(clockwiseRadians), size.x * -sin(clockwiseRadians), translation.x, 
        size.y * sin(clockwiseRadians), size.y * cos(clockwiseRadians),  translation.y,
        0,                      0,                       1
    };

    float3 worldPos = mul(modelTransform, float3(modelPos, 1));
    float4 ndcPos = mul(ubo.viewProj, float4(worldPos, 1));

    return VSOutput(shapeType, ndcPos, modelPos, innerColour, outerColour, vmin(size));
}

struct VSOutput {
    uint shapeType;
    float4 position  : SV_POSITION;
    float2 modelPos;
    float4 innerColour;
    float4 outerColour;
    float size;
};

groupshared uint lock;

[shader("fragment")]
float4 fsmain(VSOutput input) : SV_TARGET { 

    // Switch on shapeType. 
    // It would be more efficient to have a different shader for 
    // each shape but this will be fine for now
    float dist;
    switch(input.shapeType) {
        case 0: dist = sdfBox(input.modelPos, float2(0.5)) * 300; break;
        case 1: dist = sdfCircle(input.modelPos, 0.5) * 300; break;
    } 

    // negative dist = inside the shape
    // 0 = on the edge 
    // positive dist = outside the shape

    if(dist > 0) discard;
    
    // Add the outer edge
    float n = 100 / input.size;
    float edge = clamp(n*n*n*n, 5, 20);

    dist = clamp(dist+edge, 0, 1);

    return lerp(input.innerColour, input.outerColour, dist);
}
float sdfBox(float2 p, float2 b) {
	float2 d = abs(p) - b;
	return length(max(d, float2(0))) + vmax(min(d, float2(0)));
}
float sdfCircle(float2 p, float r) {
    return length(p) - r;
}

[ForceInline]
float vmin(float2 v) {
	return min(v.x, v.y);
}
[ForceInline]
float ndot(float2 a, float2 b) { 
    return a.x*b.x - a.y*b.y; 
}
[ForceInline]
float vmax(float2 v) {
	return max(v.x, v.y);
}
