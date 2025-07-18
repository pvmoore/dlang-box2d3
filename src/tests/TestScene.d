module tests.TestScene;

import box2d3;
import vulkan        : RGBA;
import std.algorithm : map;
import std.range     : array;
import std.random    : uniform01;
import std.format    : format;

enum { 
    SIMULATION_SPEED = 1.0 * 0.5,
    SIMULATION_STEPS = 4
}

struct Entity {
    string name;

    // Body properties
    b2BodyId bodyId;
    b2BodyType type;
    b2coord pos;
    Angle!float rotationACW = 0.degrees;
    bool isAwake = true;

    // Shape properties
    Shape[] shapes;

    // Indexes into the Scene.joints array for Joints that are connected to this Entity
    uint[] jointIndexes;

    void createBody(b2WorldId worldId, b2BodyDef def) {
        this.type = def.type;
        this.pos = def.position.as!b2coord;
        this.rotationACW = b2Rot_GetAngle(def.rotation).radians;
        this.bodyId = b2CreateBody(worldId, &def);
    }

    void addRectangleShape(b2ShapeDef def, float2 size, RGBA colour) {
        b2Polygon box = b2MakeBox(size.x, size.y);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &box);
        Shape shape = {type: ShapeType.RECTANGLE, colour: colour};
        shape.data.rectangle = RectangleData(def, shapeId, size);
        this.shapes ~= shape;
    }
    void addCircleShape(b2ShapeDef def, float radius, RGBA colour, b2coord centre = b2coord(0,0)) {
        b2Circle circle = {centre.as!b2Vec2, radius};
        auto shapeId = b2CreateCircleShape(bodyId, &def, &circle);
        Shape shape = {type: ShapeType.CIRCLE, colour: colour};
        shape.data.circle = CircleData(def, shapeId, centre, radius);
        this.shapes ~= shape;
    }
    void addCapsuleShape(b2ShapeDef def, b2coord p1, b2coord p2, float radius, RGBA colour) {
        b2Polygon capsule = b2MakeCapsule(p1.as!b2Vec2, p2.as!b2Vec2, radius);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &capsule);
        Shape shape = {type: ShapeType.CAPSULE, colour: colour};
        shape.data.capsule = CapsuleData(def, shapeId, p1, p2, radius);
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
    void addPolygonShape(b2ShapeDef def, b2coord[] vertices, RGBA colour, float radius = 0) {
        // Calcutate the hull
        b2Hull hull = b2ComputeHull(vertices.ptr.as!(b2Vec2*), vertices.length.as!uint);
        throwIfNot(b2ValidateHull(&hull));

        // Create the polygon
        b2Polygon poly = b2MakePolygon(&hull, radius);
        auto shapeId = b2CreatePolygonShape(bodyId, &def, &poly);

        // Create the shape
        Shape shape = {type: ShapeType.POLYGON, colour: colour};
        shape.data.polygon = PolygonData(def, shapeId, vertices, radius);

        this.shapes ~= shape;
    }

    void addSegmentShape(b2ShapeDef def, b2coord p1, b2coord p2, RGBA colour) {
        b2Segment segment = {
            point1: p1.as!b2Vec2, 
            point2: p2.as!b2Vec2
        };
        auto shapeId = b2CreateSegmentShape(bodyId, &def, &segment);
        Shape shape = {type: ShapeType.SEGMENT, colour: colour};
        shape.data.segment = SegmentData(def, shapeId, p1, p2);

        this.shapes ~= shape;
    }

    void addChainSegmentShape(b2ChainDef def, b2coord[] vertices, RGBA colour) {
        throwIf(vertices.length < 2, "Must have at least 2 vertices");

        def.points = vertices.ptr.as!(b2Vec2*);
        def.count = vertices.length.as!uint;

        auto chainId = b2CreateChain(bodyId, &def);

        Shape shape = {type: ShapeType.CHAIN_SEGMENT, colour: colour};
        shape.data.chainSegment = ChainSegmentData(def, chainId);
        shape.data.chainSegment.vertices = vertices;

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
    RGBA colour = RGBA(1,1,1,1);
    uint renderId;
}
struct RectangleData {
    b2ShapeDef def;
    b2ShapeId shapeId;  
    float2 size;
}
struct CircleData {
    b2ShapeDef def;
    b2ShapeId shapeId;  
    b2coord centre;
    float radius;
}
struct CapsuleData {
    b2ShapeDef def;
    b2ShapeId shapeId;  
    b2coord p1;
    b2coord p2;
    float radius;
}
struct PolygonData {
    b2ShapeDef def;
    b2ShapeId shapeId;  
    b2coord[] vertices;
    float radius;
}
struct SegmentData {
    b2ShapeDef def;
    b2ShapeId shapeId;  
    b2coord p1;
    b2coord p2;
}
struct ChainSegmentData {
    b2ChainDef chainDef;
    b2ChainId chainId;
    b2coord[] vertices;
    uint[] renderIds;
}
union ShapeData {
    RectangleData rectangle;
    CircleData circle;
    CapsuleData capsule;
    PolygonData polygon;
    SegmentData segment;
    ChainSegmentData chainSegment;  
}

struct Joint {
    b2JointId jointId;
    Entity* entityA;
    Entity* entityB;
    b2coord localAnchorA;
    b2coord localAnchorB;
    uint renderId;
}
class Scene {
    b2WorldId worldId;
    float width;
    float height;
    Entity[] entities;
    Joint[] joints;

    this(b2WorldId worldId, float width, float height) {
        this.worldId = worldId;
        this.width = width;
        this.height = height;
    }
}
//──────────────────────────────────────────────────────────────────────────────────────────────────

Scene createScene(b2WorldId worldId, float width, float height) {

    Scene scene = new Scene(worldId, width, height);    
    addGround(scene);
    addBox(scene);
    addCircle(scene);
    addCapsule(scene);
    addPolygon(scene);
    addSegment(scene);
    addChain(scene);
    
    addDistanceJoint(scene, b2coord(0,0), false);
    addDistanceJoint(scene, b2coord(200,200), true);

    addRevoluteJoint(scene, b2coord(400,0), false);
    addRevoluteJoint(scene, b2coord(500,200), true);

    addPrismaticJoint(scene);

    return scene;
}
void addGround(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Ground",
        pos: b2coord(scene.width / 2, 70),
        rotationACW: 0.degrees
    };
    e.createBody(scene.worldId, staticBodyDef(e.pos, e.rotationACW));
    e.addRectangleShape(shapeDef, float2(650.0f, 10.0f), RGBA(1,1,1,1));

    scene.entities ~= e;
}
void addBox(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Falling box",
        pos: b2coord(scene.width / 2, 500.0f),
        rotationACW: 25.degrees
    };
    e.createBody(scene.worldId, dynamicBodyDef(e.pos, e.rotationACW));
    e.addRectangleShape(shapeDef, float2(40, 40), RGBA(0,1,0,1));
   
    scene.entities ~= e;
}
void addCircle(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Falling circle",
        pos: b2coord(scene.width / 2 + 200, 600.0f),
        rotationACW: 0.degrees
    };
    e.createBody(scene.worldId, dynamicBodyDef(e.pos, e.rotationACW));
    e.addCircleShape(shapeDef, 40, RGBA(0,1,1,1));
   
    scene.entities ~= e;
}
void addCapsule(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Falling capsule",
        pos: b2coord(scene.width/2 - 50, 900.0f),
        rotationACW: 20.degrees
    }; 
    e.createBody(scene.worldId, dynamicBodyDef(e.pos, e.rotationACW));
    e.addCapsuleShape(shapeDef, b2coord(0, -50), b2coord(0, 50), 50, RGBA(0.7, 0.5, 0.2,1));    

    scene.entities ~= e;
}
void addPolygon(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Falling polygon",
        pos: b2coord(scene.width / 2 + 450, 600.0f),
        rotationACW: 45.degrees
    };
    e.createBody(scene.worldId, dynamicBodyDef(e.pos, e.rotationACW));    
    e.addPolygonShape(shapeDef, 
        [
            b2coord( 0.5, 0.7),   
            b2coord(-0.5, 1),
            b2coord(-1, 0), 
            b2coord(-0.5, -1),
            b2coord(0.5, -1),
            b2coord(1, 0)     
        ].map!(it=>it * b2coord(70, 70)).array,
        RGBA(0.3,0.3,0.8,1),
        0);    

    scene.entities ~= e;
}
void addSegment(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    Entity e = {
        name: "Segment 1",
        pos: b2coord(scene.width / 2 + 350, 400.0f),
        rotationACW: 0.degrees
    };
    e.createBody(scene.worldId, staticBodyDef(e.pos, e.rotationACW));
    e.addSegmentShape(shapeDef, b2coord(-145,-40), b2coord(200,100), RGBA(0.8,0.3,0.8,1));

    scene.entities ~= e;
}
void addChain(Scene scene) {
    Entity e = {
        name: "Chain",
        pos: b2coord(scene.width / 2 + 150, 300.0f),
        rotationACW: 0.degrees
    };
    e.createBody(scene.worldId, staticBodyDef(e.pos, e.rotationACW));

    e.addChainSegmentShape(b2DefaultChainDef(), 
        [
            // only the right side of the chain will collide
            b2coord(70,-60),     // ghost
            b2coord(20,-80),
            b2coord(-100,-50), 
            b2coord(-200,-50), 
            b2coord(-300,0),     // ghost
        ].map!(it=>it + b2coord(-40, 0)).array,
        RGBA(1, 0.5, 0.8, 1));    

    scene.entities ~= e;    
}
void addDistanceJoint(Scene scene, b2coord pos, bool spring) {

    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    RGBA[2] colours = [
        RGBA(0.9, uniform01(), 0.5, 1), 
        RGBA(uniform01(), 0.9, 0.5, 1)
    ];

    // Body A
    Entity bodyA = {
        name: "Body A",
        pos: pos + b2coord(400, 600),
        rotationACW: 0.degrees
    }; 
    bodyA.createBody(scene.worldId, dynamicBodyDef(bodyA.pos, bodyA.rotationACW));
    bodyA.addCircleShape(shapeDef, 50, colours[0]); 
    auto bodyAPtr = scene.entities.appendAndReturnPtr(bodyA);   

    // Body B
    Entity bodyB = {
        name: "Body B",
        pos: pos + b2coord(500, 800),
        rotationACW: 0.degrees
    }; 
    bodyB.createBody(scene.worldId, dynamicBodyDef(bodyB.pos, bodyB.rotationACW));
    bodyB.addCircleShape(shapeDef, 50, colours[1]);    
    auto bodyBPtr = scene.entities.appendAndReturnPtr(bodyB); 

    // Distance joint
    b2DistanceJointDef jointDef = b2DefaultDistanceJointDef();
    jointDef.bodyIdA = bodyA.bodyId;
    jointDef.bodyIdB = bodyB.bodyId;
    jointDef.localAnchorA = b2Vec2(0,0);
    jointDef.localAnchorB = b2Vec2(0,0);

    float2 anchorA = b2Body_GetWorldPoint(bodyA.bodyId, jointDef.localAnchorA).as!float2;
    float2 anchorB = b2Body_GetWorldPoint(bodyB.bodyId, jointDef.localAnchorB).as!float2;
    jointDef.length = (anchorB - anchorA).length();
    jointDef.collideConnected = false;

    if(spring) {
        jointDef.enableSpring = true;
        jointDef.dampingRatio = 0.05;
        jointDef.hertz        = 1.0;
        jointDef.minLength    = 0;
        jointDef.maxLength    = jointDef.length + 100;
    }

    b2JointId jointId = b2CreateDistanceJoint(scene.worldId, &jointDef);

    uint jointIndex = scene.joints.length.as!uint;
    bodyAPtr.jointIndexes ~= jointIndex;
    bodyBPtr.jointIndexes ~= jointIndex;

    scene.joints ~= Joint(
        jointId, 
        bodyAPtr, 
        bodyBPtr, 
        jointDef.localAnchorA.as!b2coord, 
        jointDef.localAnchorB.as!b2coord);
}
void addRevoluteJoint(Scene scene, b2coord pos, bool spring) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    RGBA[2] colours = [
        RGBA(uniform01(), 0.5, 0.5, 1), 
        RGBA(0.9, 0.5, uniform01(), 1)
    ];

    b2coord posA      = pos + b2coord(800, 900);
    b2coord posB      = posA + b2coord(50, 50);
    b2Vec2 worldPivot = (posB + b2coord(0, 0)).as!b2Vec2;

    // Body A
    Entity bodyA = {
        name: "Body A - revolute",
        pos: posA,
        rotationACW: 0.degrees
    }; 
    bodyA.createBody(scene.worldId, dynamicBodyDef(bodyA.pos, bodyA.rotationACW));
    bodyA.addCircleShape(shapeDef, 70, colours[0]); 
    auto bodyAPtr = scene.entities.appendAndReturnPtr(bodyA);   

    // Body B
    Entity bodyB = {
        name: "Body B - revolute",
        pos: posB,
        rotationACW: 0.degrees
    }; 
    bodyB.createBody(scene.worldId, dynamicBodyDef(bodyB.pos, bodyB.rotationACW));
    bodyB.addRectangleShape(shapeDef, float2(60,40), colours[1]);    
    auto bodyBPtr = scene.entities.appendAndReturnPtr(bodyB); 


    b2RevoluteJointDef jointDef = b2DefaultRevoluteJointDef();
    jointDef.bodyIdA = bodyA.bodyId;
    jointDef.bodyIdB = bodyB.bodyId;
    jointDef.localAnchorA = b2Body_GetLocalPoint(bodyA.bodyId, worldPivot);
    jointDef.localAnchorB = b2Body_GetLocalPoint(bodyB.bodyId, worldPivot);

    jointDef.referenceAngle = 0;
    jointDef.lowerAngle     = -0.5 * 3.14159265359f;
    jointDef.upperAngle     = 0.25 * 3.14159265359f;
    jointDef.enableLimit    = true;
    
    jointDef.collideConnected = false;
    
    if(spring) {
        jointDef.enableSpring = true;
        jointDef.dampingRatio = 0.01;
        jointDef.hertz        = 1.0;
    }

    b2JointId jointId = b2CreateRevoluteJoint(scene.worldId, &jointDef);

    uint jointIndex = scene.joints.length.as!uint;
    bodyAPtr.jointIndexes ~= jointIndex;
    bodyBPtr.jointIndexes ~= jointIndex;

    scene.joints ~= Joint(
        jointId, 
        bodyAPtr, 
        bodyBPtr, 
        jointDef.localAnchorA.as!b2coord, 
        jointDef.localAnchorB.as!b2coord);
}
void addPrismaticJoint(Scene scene) {
    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.friction = 0.6f;

    RGBA[2] colours = [
        RGBA(0.5, 0.5, uniform01(), 1), 
        RGBA(0.9, 0.5, uniform01(), 1)
    ];

    b2coord posA = b2coord(250, 1000);
    b2coord posB = posA + b2coord(100, 0);

    b2Vec2 worldPivot = (posA + (posB-posA) / 2).as!b2Vec2;
    b2Vec2 worldAxis = (b2coord(1,0)).as!b2Vec2;

    // Body A
    Entity bodyA = {
        name: "Body A - prismatic",
        pos: posA,
        rotationACW: 0.degrees
    }; 
    bodyA.createBody(scene.worldId, dynamicBodyDef(bodyA.pos, bodyA.rotationACW));
    bodyA.addRectangleShape(shapeDef, float2(60,40), colours[0]); 
    auto bodyAPtr = scene.entities.appendAndReturnPtr(bodyA);   

    // Body B
    Entity bodyB = {
        name: "Body B - prismatic",
        pos: posB,
        rotationACW: 0.degrees
    }; 
    bodyB.createBody(scene.worldId, dynamicBodyDef(bodyB.pos, bodyB.rotationACW));
    bodyB.addRectangleShape(shapeDef, float2(60,40), colours[1]);    
    auto bodyBPtr = scene.entities.appendAndReturnPtr(bodyB); 

    b2PrismaticJointDef jointDef = b2DefaultPrismaticJointDef();
    jointDef.bodyIdA = bodyA.bodyId;
    jointDef.bodyIdB = bodyB.bodyId;
    jointDef.localAnchorA = b2Body_GetLocalPoint(bodyA.bodyId, worldPivot);
    jointDef.localAnchorB = b2Body_GetLocalPoint(bodyB.bodyId, worldPivot);
    jointDef.localAxisA = b2Body_GetLocalVector(bodyA.bodyId, worldAxis);

    jointDef.lowerTranslation = -100;
    jointDef.upperTranslation = 100;
    jointDef.enableLimit      = true;

    jointDef.collideConnected = false;

    b2JointId jointId = b2CreatePrismaticJoint(scene.worldId, &jointDef);

    uint jointIndex = scene.joints.length.as!uint;
    bodyAPtr.jointIndexes ~= jointIndex;
    bodyBPtr.jointIndexes ~= jointIndex;

    scene.joints ~= Joint(
        jointId, 
        bodyAPtr, 
        bodyBPtr, 
        jointDef.localAnchorA.as!b2coord, 
        jointDef.localAnchorB.as!b2coord);
}
