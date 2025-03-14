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
    
    let rotationMatrix = float3x3(
        cos(clockwiseRadians), -sin(clockwiseRadians), 0,
        sin(clockwiseRadians), cos(clockwiseRadians), 0,
        0, 0, 1
    );

    let scaleMatrix = float3x3(
        size.x, 0, 0,
        0, size.y, 0,
        0, 0, 1
    );
    let translationMatrix = float3x3(
        1, 0, translation.x,
        0, 1, translation.y,
        0, 0, 1
    );

    float3 p1 = mul(scaleMatrix, float3(modelPos, 1));
    float3 p2 = mul(rotationMatrix, p1);
    float3 worldPos = mul(translationMatrix, p2);

    float4 ndcPos = mul(ubo.viewProj, float4(worldPos, 1));

    return VSOutput(shapeType, ndcPos, modelPos, innerColour, outerColour, size);
}

struct VSOutput {
    uint shapeType;
    float4 position  : SV_POSITION;
    float2 modelPos;
    float4 innerColour;
    float4 outerColour;
    float2 size;
};

groupshared uint lock;

[shader("fragment")]
float4 fsmain(VSOutput input) : SV_TARGET { 

    // Switch on shapeType. 
    // It would be more efficient to have a different shader for 
    // each shape but this will be fine for now
    float dist;
    switch(input.shapeType) {
        case 0: dist = sdfBox(input.modelPos, float2(0.5)); break;
        case 1: dist = sdfCircle(input.modelPos, 0.5); break;
        case 2:
            float2 ratio = float2(1, input.size.y / input.size.x);
            float offset = (ratio.y - 1) * 0.5;
            float2 p = input.modelPos * ratio;

            dist = sdfCircle(p - float2(0, offset) , 0.5);
            dist = min(dist, sdfCircle(p + float2(0, offset) , 0.5));
            dist = min(dist, sdfBox(p, float2(0.5, offset)));
            break;
    } 

    // negative dist = inside the shape
    // 0 = on the edge 
    // positive dist = outside the shape

    if(dist > 0) {
        discard;
    }
    
    // Add the outer edge
    float n = 100 / vmin(input.size);
    float edge = clamp(n*n*n*n, 5, 20);

    dist = clamp(dist*300+edge, 0, 1);

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
