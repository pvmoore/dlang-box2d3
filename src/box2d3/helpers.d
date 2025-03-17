module box2d3.helpers;

import box2d3.all;

b2WorldId createWorld(void delegate(b2WorldDef*) callback = null) {
    auto def = b2DefaultWorldDef();
    if (callback) callback(&def);
    auto worldId = b2CreateWorld(&def);
    return worldId;
}
//──────────────────────────────────────────────────────────────────────────────────────────────────
b2BodyDef staticBodyDef(float2 pos, Angle!float rotationACW = 0.degrees) {
    b2BodyDef def = b2DefaultBodyDef();
    def.position = pos.as!b2Vec2;
    def.rotation = rotation(rotationACW.radians);
    return def;
}
b2BodyDef dynamicBodyDef(float2 pos, Angle!float rotationACW = 0.degrees) {
    b2BodyDef def = b2DefaultBodyDef();
    def.type = b2BodyType.b2_dynamicBody;
    def.position = pos.as!b2Vec2;
    def.rotation = rotation(rotationACW.radians);
    return def;
}
b2BodyDef kinematicBodyDef(float2 pos, Angle!float rotationACW = 0.degrees) {
    b2BodyDef def = b2DefaultBodyDef();
    def.type = b2BodyType.b2_kinematicBody;
    def.position = pos.as!b2Vec2;
    def.rotation = rotation(rotationACW.radians);
    return def;
}
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
void dumpVertices(b2Polygon* poly) {
    foreach(i; 0..poly.count) {
        log("poly[%s] = %s", i, poly.vertices[i].as!float2);
    }
}

//──────────────────────────────────────────────────────────────────────────────────────────────────
b2Polygon b2MakeCapsule(b2Vec2 p1, b2Vec2 p2, float radius) {
	b2Polygon shape;
	shape.vertices[0] = p1;
	shape.vertices[1] = p2;
	shape.centroid = b2Lerp( p1, p2, 0.5f );

	b2Vec2 d = b2Sub( p2, p1 );
	assert( b2LengthSquared( d ) > FLT_EPSILON );
	b2Vec2 axis = b2Normalize( d );
	b2Vec2 normal = b2RightPerp( axis );

	shape.normals[0] = normal;
	shape.normals[1] = b2Neg( normal );
	shape.count = 2;
	shape.radius = radius;

	return shape;
}
b2Vec2 b2Normalize(b2Vec2 v) {
    return v.as!float2.normalised().as!b2Vec2;
}
b2Rot rotation(float radiansACW) {
    return b2ComputeCosSin(radiansACW).as!b2Rot;
}
