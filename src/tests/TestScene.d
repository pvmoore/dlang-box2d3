module tests.TestScene;

import box2d3;
import vulkan        : RGBA;
import std.algorithm : map;
import std.range     : array;

enum { 
    SIMULATION_SPEED = 1.0 * 0.1,
    SIMULATION_STEPS = 4
}

struct Entity {
    string name;

    // Body properties
    b2BodyId bodyId;
    b2BodyType type;
    float2 pos;
    Angle!float rotationACW;
    bool isAwake = true;

    // Shape properties
    Shape[] shapes;

    // Render properties
    RGBA innerColour = RGBA(0,0,1,1);

    void createBody(b2WorldId worldId, b2BodyDef def) {
        this.type = def.type;
        this.pos = def.position.as!float2;
        this.rotationACW = b2Rot_GetAngle(def.rotation).radians;
        this.bodyId = b2CreateBody(worldId, &def);
    }

    void addRectangleShape(b2ShapeDef def, float2 size) {
        b2Polygon box = b2MakeBox(size.x, size.y);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &box);
        Shape shape = {type: ShapeType.RECTANGLE, def: def, shapeId: shapeId};
        shape.data.rectangle = RectangleData(size);
        this.shapes ~= shape;
    }
    void addCircleShape(b2ShapeDef def, float radius, float2 centre = float2(0,0)) {
        b2Circle circle = {centre.as!b2Vec2, radius};
        auto shapeId = b2CreateCircleShape(bodyId, &def, &circle);
        Shape shape = {type: ShapeType.CIRCLE, def: def, shapeId: shapeId};
        shape.data.circle = CircleData(centre, radius);
        this.shapes ~= shape;
    }
    void addCapsuleShape(b2ShapeDef def, float2 p1, float2 p2, float radius) {
        b2Polygon capsule = b2MakeCapsule(p1.as!b2Vec2, p2.as!b2Vec2, radius);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &capsule);
        Shape shape = {type: ShapeType.CAPSULE, def: def, shapeId: shapeId};
        shape.data.capsule = CapsuleData(p1, p2, radius);
        this.shapes ~= shape;
    }
    /** 
     * params:
     *   def: The shape definition
     *   vertices: The vertices of the polygon (in local model coordinates, x is right, y is up)
     *   radius: If 0, the polygon will have sharp edges (default)
     *           If > 0, the polygon will have extra padding around the outside 
     *           If < 0, the edge will be inset
     */
    void addPolygonShape(b2ShapeDef def, float2[] vertices, float radius = 0) {
        // Calcutate the hull
        b2Hull hull = b2ComputeHull(vertices.ptr.as!(b2Vec2*), vertices.length.as!uint);
        throwIfNot(b2ValidateHull(&hull));

        // Create the polygon
        b2Polygon poly = b2MakePolygon(&hull, radius);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &poly);

        // Create the shape
        Shape shape = {type: ShapeType.POLYGON, def: def, shapeId: shapeId};
        shape.data.polygon = PolygonData(vertices, radius);

        this.shapes ~= shape;
    }

    void addSegmentShape(b2ShapeDef def, float2 p1, float2 p2) {
        b2Segment segment = {
            point1: p1.as!b2Vec2, 
            point2: p2.as!b2Vec2
        };
        auto shapeId = b2CreateSegmentShape(bodyId, &def, &segment);
        Shape shape = {type: ShapeType.SEGMENT, def: def, shapeId: shapeId};
        shape.data.segment = SegmentData(p1, p2);

        this.shapes ~= shape;
    }

    string toString() {
        return format("'%s': pos=%s, rot=%s", name, pos, rotationACW);
    }
}
//──────────────────────────────────────────────────────────────────────────────────────────────────

struct Shape {
    ShapeType type;
    ShapeData data;
    b2ShapeId shapeId;
    uint renderId;
    b2ShapeDef def;
}
struct RectangleData {
    float2 size;
}
struct CircleData {
    float2 centre = float2(0,0);
    float radius;
}
struct CapsuleData {
    float2 p1;
    float2 p2;
    float radius;
}
struct PolygonData {
    float2[] vertices;
    float radius;
}
struct SegmentData {
    float2 p1;
    float2 p2;
}
union ShapeData {
    RectangleData rectangle;
    CircleData circle;
    CapsuleData capsule;
    PolygonData polygon;
    SegmentData segment;
}
//──────────────────────────────────────────────────────────────────────────────────────────────────

Entity[] createScene(b2WorldId worldId, float width, float height) {

    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity ground = {
        name: "Ground",
        innerColour: RGBA(1,1,0,1)
    };
    ground.createBody(worldId, staticBodyDef(float2(width / 2, 70), 0.degrees));
    ground.addRectangleShape(shapeDef, float2(650.0f, 10.0f));

    Entity fallingBox = {
        name: "Falling box",
        innerColour: RGBA(0,1,0,1)
    };
    fallingBox.createBody(worldId, dynamicBodyDef(float2(width / 2, 500.0f), 25.degrees));
    fallingBox.addRectangleShape(shapeDef, float2(40, 40));

    Entity fallingCircle = {
        name: "Falling circle",
        innerColour: RGBA(0,1,1,1)
    };
    fallingCircle.createBody(worldId, dynamicBodyDef(float2(width / 2 + 200, 600.0f), 0.degrees));
    fallingCircle.addCircleShape(shapeDef, 40);

    Entity fallingCapsule = {
        name: "Falling capsule",
        innerColour: RGBA(0.7,0.1,0.8,1)
    }; 
    fallingCapsule.createBody(worldId, dynamicBodyDef(float2(width / 2 - 300, 600.0f), 20.degrees));
    fallingCapsule.addCapsuleShape(shapeDef, float2(0, -50), float2(0, 50), 50);    

    Entity fallingPolygon = {
        name: "Falling polygon",
        innerColour: RGBA(0.3,0.3,0.8,1)
    };
    fallingPolygon.createBody(worldId, dynamicBodyDef(float2(width / 2 + 450, 600.0f), 45.degrees));    
    fallingPolygon.addPolygonShape(shapeDef, [
            float2( 0.5, 0.7),   
            float2(-0.5, 1),
            float2(-1, 0), 
            float2(-0.5, -1),
            float2(0.5, -1),
            float2(1, 0)     
        ].map!(it=>it * float2(70, 70)).array,
        0);    

    Entity segment = {
        name: "Segment 1",
        innerColour: RGBA(0.8,0.3,0.8,1)
    };
    segment.createBody(worldId, staticBodyDef(float2(width / 2 + 350, 300.0f)));
    segment.addSegmentShape(shapeDef, float2(-145,-40), float2(200,100));

    //segment.addSegmentShape(shapeDef, float2(0,0), float2(200,100));

    return [
        ground, 
        fallingBox, 
        fallingCircle, 
        fallingCapsule,
        fallingPolygon,
        segment
    ];
}
