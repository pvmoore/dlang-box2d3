[require(GL_EXT_debug_printf)]

struct UBO {
    float4x4 viewProj;
};

[[vk::binding(0, 0)]] ConstantBuffer<UBO> ubo;
[[vk::binding(1, 0)]] StructuredBuffer<float2, Std430DataLayout> staticData;

[shader("vertex")]
VSOutput vsmain(uint shapeType,
                float2 modelPos,
                float2 translation,
                float2 size,
                float anticlockwiseRadians,
                float4 innerColour,
                uint isAwake,
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

    return VSOutput(shapeType, ndcPos, modelPos, innerColour, size, isAwake == 1);
}

struct VSOutput {
    uint shapeType;
    float4 position  : SV_POSITION;
    float2 modelPos;
    float4 innerColour;
    float2 size;
    bool isAwake;
};

// Buffer slice
struct Buffer<T> : IArray<T> {
    StructuredBuffer<T, Std430DataLayout> data;
    int offset;
    int count;

    __init(StructuredBuffer<T, Std430DataLayout> data, int offset, int count) {
        this.data = data;
        this.offset = offset;
        this.count = count;
    }
    // IArray interface
    __subscript(int i) -> T {
        get { return data[offset+i]; }
    }
    // IArray interface
    int getCount() {
        return count;
    }
}

// staticData contains 9 float2s per shape
static const uint STATIC_DATA_PER_SHAPE = 9;
static const bool SHOW_BOUNDING_BOX     = false;

[shader("fragment")]
float4 fsmain(VSOutput input, uint primitiveId : SV_PrimitiveID) : SV_TARGET { 

    // Each shape is made up of 2 triangle primitives
    let shapeId          = primitiveId / 2;
    let staticDataOffset = shapeId*STATIC_DATA_PER_SHAPE; 
    let distFromCentre   = length(input.modelPos) / vmax(input.size);

    var colour     = input.innerColour;
    var edgeColour = float4(1,1,1,1);
    
    // Note: It would be more efficient to have a different shader for 
    //       each shape but this will be fine for now

    // Signed distance function. dist = distance from the shape. 
    // ie. negative = inside, 0 = on edge, positive = outside
    float dist;
    switch(input.shapeType) {
        case 0: {
            // Rectangle 
            dist = sdfBox(input.modelPos * (1.1), float2(1)) - 0.1; 
            break;
        }
        case 1:
            // Circle 
            dist = sdfCircle(input.modelPos, 1.0); 
            break;
        case 2: {
            // Capsule 
            let ratio  = getRatio(input.size);
            let p      = input.modelPos * ratio;
            let offset = ratio.y * 0.5;

            dist = sdfCircle(p - float2(0, offset) , 1);
            dist = min(dist, sdfCircle(p + float2(0, offset) , 1));
            dist = min(dist, sdfBox(p, float2(1, offset)));
            break;
        }
        case 3: {
            // Polygon
            let numVertices = uint(staticData[staticDataOffset].x);
            let vertices    = Buffer<float2>(staticData, staticDataOffset+1, numVertices);

            // radius currently unused
            let radius   = staticData[staticDataOffset].y;
            
            //dist = sdfPolygon(input.modelPos * (1.2), vertices) - 0.1;
            dist = sdfPolygon(input.modelPos, vertices);
            break;
        }
        case 4: {
            // Segment (line)
            let isGhost = bool(staticData[staticDataOffset].x);
            let isJoint = bool(staticData[staticDataOffset].y);
            if(isGhost) {
                edgeColour = float4(0.6, 0.6, 0.2, 0.6);
            }
            if(isJoint) {
                edgeColour = float4(0.8, 0.7, 1, 0.6);

                // Create a dashed line
                uint a = uint((input.modelPos.y+1) * 128);
                if((a & 8) == 0) {
                    edgeColour = float4(0,0,0,0);
                    break;
                }
            }

            dist = sdfSegment(input.modelPos, float2(0,-1), float2(0,1)) - 0.3;
            break;
        }
    } 

    // Discard fragments outside the shape
    if(dist > 0) {
        if(SHOW_BOUNDING_BOX) return float4(1,1,1,0.2);
        discard;
    }

    // If the bounding box is really thin just return the outer colour
    if(vmin(input.size) < 6) return edgeColour;

    // Reduce alpha if the shape is asleep
    if(!input.isAwake) {
        colour.a *= 0.5;
    }

    float edge = max(0.07, vmax(input.size) / 500 * 0.07);

    // Draw the shape colour or white if on the edge of the shape
    return (dist > -0.07) ? edgeColour : colour;
}
/** 
 * See https://iquilezles.org/articles/distfunctions2d/
 *   
 * params:
 *  p: point
 *  b: box size
 */
float sdfBox(float2 p, float2 b) {
	float2 d = abs(p) - b;
	return length(max(d, float2(0))) + vmax(min(d, float2(0)));
}
/** 
 * See https://iquilezles.org/articles/distfunctions2d/
 *   
 * params:
 *  p: point
 *  r: circle radius
 */
float sdfCircle(float2 p, float r) {
    return length(p) - r;
}
/** 
 * See https://iquilezles.org/articles/distfunctions2d/
 *
 * params:
 *  p:        point
 *  vertices: vertex array
 */
float sdfPolygon(float2 p, IArray<float2> vertices) {
    int numVertices = vertices.getCount();
    float2 v = p-vertices[0];
    float d = dot(v, v);
    float s = 1.0;
    for(int i=0, j=numVertices-1; i<numVertices; j=i, i++) {
        float2 prev = vertices[j];
        float2 curr = vertices[i];
        float2 e = prev - curr;
        float2 w = p - curr;
        float2 b = w - e*clamp(dot(w,e)/dot(e,e), 0.0, 1.0);
        d = min(d, dot(b,b));
        bool3 c = bool3(p.y>=curr.y, p.y<prev.y, e.x*w.y>e.y*w.x);
        if(all(c) || all(!(c))) s *= -1.0;  
    }
    return s*sqrt(d);
}
/** 
 * See https://iquilezles.org/articles/distfunctions2d/
 *
 * params:
 *  p: point
 *  a: segment start
 *  b: segment end
 */
float sdfSegment(float2 p, float2 a, float2 b) {
    float2 pa = p-a, ba = b-a;
    float h = clamp(dot(pa,ba)/dot(ba,ba), 0.0, 1.0);
    return length(pa - ba*h);
}

/**
 * Multiply model position by this ratio to fill the rectangle correctly
 */
[ForceInline]
float2 getRatio(float2 size) {
    return size.y > size.x ? float2(1, size.y / size.x) : float2(size.x / size.y, 1);
}
/**
 * Return the minimum of vector x and y
 */
[ForceInline]
float vmin(float2 v) {
	return min(v.x, v.y);
}
/**
 * Return the maximum of vector x and y
 */
[ForceInline]
float vmax(float2 v) {
	return max(v.x, v.y);
}
/**
 * Return the negative dot product of two vectors
 */
[ForceInline]
float ndot(float2 a, float2 b) { 
    return a.x*b.x - a.y*b.y; 
}
