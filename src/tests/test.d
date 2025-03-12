module tests.test;

import std.stdio : writefln;

import box2d3;

void main() {
    writefln("Hello World");

    b2Version version_ = b2GetVersion();
    writefln("Box2D version: %s.%s.%s", version_.major, version_.minor, version_.revision);


    b2WorldId worldId = createWorld((def) {
        def.gravity = b2Vec2(0.0f, -10.0f);
    });
    scope(exit) b2DestroyWorld(worldId);

    b2BodyId groundId = createGround(worldId);
    b2BodyId fallingBoxId = createFallingBox(worldId, float2(700.0f, 500.0f), float2(20, 20));

    foreach(i; 0..90) {
        b2World_Step(worldId, 1 / 60f, 8);
        b2Vec2 position = b2Body_GetPosition(fallingBoxId);
        b2Rot rotation = b2Body_GetRotation(fallingBoxId);
        writefln("%4.2f %4.2f %4.2f", position.x, position.y, b2Rot_GetAngle(rotation));
    }

}

private:

b2BodyId createGround(b2WorldId worldId) {
    b2BodyDef groundBodyDef = b2DefaultBodyDef();
    groundBodyDef.position = b2Vec2(10.0f, 10.0f);

    b2BodyId groundBodyId = b2CreateBody(worldId, &groundBodyDef);
    b2Polygon groundBox = b2MakeBox(50.0f, 10.0f);

    b2ShapeDef groundShapeDef = b2DefaultShapeDef();
    b2CreatePolygonShape(groundBodyId, &groundShapeDef, &groundBox);
    return groundBodyId;
}   
b2BodyId createFallingBox(b2WorldId worldId, float2 pos, float2 size) {
    b2BodyId bodyId = createDynamicBody(worldId, pos);
    b2Polygon fallingBox = b2MakeBox(size.x, size.y);

    b2ShapeDef shapeDef = b2DefaultShapeDef();
    shapeDef.density = 1.0f;
    shapeDef.friction = 0.3f;

    b2CreatePolygonShape(bodyId, &shapeDef, &fallingBox);

    return bodyId;
}

b2BodyId createBody(b2WorldId worldId, void delegate(b2BodyDef*) callback = null) {
    b2BodyDef def = b2DefaultBodyDef();
    if (callback) callback(&def);
    return b2CreateBody(worldId, &def);
}

b2BodyId createDynamicBody(b2WorldId worldId, float2 pos) {
    b2BodyId b = createBody(worldId, (def) {
        def.type = b2BodyType.b2_dynamicBody;
        def.position = pos.as!b2Vec2;
    });
    return b;
}
