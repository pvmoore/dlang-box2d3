module tests.TestScene;

import box2d3;
import vulkan : RGBA;

enum { 
    SIMULATION_SPEED = 1.0 * 0.15,
    SIMULATION_STEPS = 4
}

struct Entity {
    string name;

    // Body properties
    b2BodyId bodyId;
    b2BodyType type;
    float2 pos;
    Angle!float rotationACW ;

    // Shape properties
    Shape[] shapes;

    // Render properties
    RGBA innerColour = RGBA(0,0,1,1);
    RGBA outerColour = RGBA(1,1,1,1);

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
    void addPolygonShape(b2ShapeDef def, float2[] vertices, float radius) {
        b2Hull hull = b2ComputeHull(vertices.ptr.as!(b2Vec2*), vertices.length.as!uint);
        b2Polygon poly = b2MakePolygon(&hull, radius);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &poly);

        Shape shape = {type: ShapeType.POLYGON, def: def, shapeId: shapeId};
        shape.data.polygon = PolygonData(vertices, radius);

        this.shapes ~= shape;
    }

    string toString() {
        return format("'%s': pos=%s, rot=%s", name, pos, rotationACW);
    }
}
//──────────────────────────────────────────────────────────────────────────────────────────────────
enum ShapeType { RECTANGLE, CIRCLE, CAPSULE, POLYGON }

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
union ShapeData {
    RectangleData rectangle;
    CircleData circle;
    CapsuleData capsule;
    PolygonData polygon;
}
//──────────────────────────────────────────────────────────────────────────────────────────────────

Entity[] createScene(b2WorldId worldId, float width, float height) {

    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity ground = {
        name: "Ground",
        innerColour: RGBA(1,1,0,1),
        outerColour: RGBA(1,1,1,1),
    };
    ground.createBody(worldId, staticBodyDef(float2(width / 2, 70), 0.degrees));
    ground.addRectangleShape(shapeDef, float2(650.0f, 10.0f));

    Entity fallingBox = {
        name: "Falling box",
        innerColour: RGBA(0,1,0,1),
        outerColour: RGBA(1,1,1,1),
    };
    fallingBox.createBody(worldId, dynamicBodyDef(float2(width / 2, 500.0f), 25.degrees));
    fallingBox.addRectangleShape(shapeDef, float2(40, 40));

    Entity fallingCircle = {
        name: "Falling circle",
        innerColour: RGBA(0,1,1,1),
        outerColour: RGBA(1,1,1,1),
    };
    fallingCircle.createBody(worldId, dynamicBodyDef(float2(width / 2 + 200, 600.0f), 0.degrees));
    fallingCircle.addCircleShape(shapeDef, 40);

    Entity fallingCapsule = {
        name: "Falling capsule",
        innerColour: RGBA(0.7,0.1,0.8,1),
        outerColour: RGBA(1,1,1,1),
    }; 
    fallingCapsule.createBody(worldId, dynamicBodyDef(float2(width / 2 - 300, 600.0f), 20.degrees));
    fallingCapsule.addCapsuleShape(shapeDef, float2(0, -50), float2(0, 50), 50);    

    static if(false) {
    Entity fallingPolygon = {
        name: "Falling polygon",
        innerColour: RGBA(0.3,0.3,0.8,1),
        outerColour: RGBA(1,1,1,1),
    };
    fallingPolygon.createBody(worldId, dynamicBodyDef(float2(width / 2 + 400, 600.0f), 0.degrees));    
    fallingPolygon.addPolygonShape(shapeDef, [
        float2(0,0), 
        float2(0,100), 
        float2(100,100), 
        float2(100,0)], 
        10);    
    }

    return [
        ground, 
        fallingBox, 
        fallingCircle, 
        fallingCapsule
    ];
}
