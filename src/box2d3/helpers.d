module box2d3.helpers;

import box2d3.all;

b2WorldId createWorld(void delegate(b2WorldDef*) callback = null) {
    auto def = b2DefaultWorldDef();
    if (callback) callback(&def);
    auto worldId = b2CreateWorld(&def);
    return worldId;
}
//──────────────────────────────────────────────────────────────────────────────────────────────────

//──────────────────────────────────────────────────────────────────────────────────────────────────
string toString(b2WorldId worldId) {
    return "b2WorldId(%s, gravity=%s)".format(worldId, b2World_GetGravity(worldId));
}
string toString(b2BodyId bodyId) {
    return "b2BodyId(%s)".format(bodyId);
}
string toString(b2Polygon poly, b2BodyId bodyId) {
    float2 pos = b2Body_GetPosition(bodyId).as!float2;
    string s = poly.vertices[0..poly.count].map!(it=>"%s".format(it.as!float2+pos)).join(", ");
    return format("b2Polygon(cenroid=%s, vertices=(%s))", poly.centroid.as!float2, s);
}

void dumpBodyShapes(b2BodyId bodyId) {
    uint numShapes = b2Body_GetShapeCount(bodyId);
    b2ShapeId[] shapeIds = new b2ShapeId[numShapes];
    b2Body_GetShapes(bodyId, shapeIds.ptr, numShapes);

    foreach(i; 0..numShapes) {
        b2ShapeId shapeId = shapeIds[i];
        b2Polygon poly = b2Shape_GetPolygon(shapeId);
        log("polygon = %s", poly.toString(bodyId));
    }
}
