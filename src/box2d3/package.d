module box2d3;

public:

import common;
import maths;
import logging;

import box2d3.api;
import box2d3.b2coord;
import box2d3.helpers;

enum ShapeType { RECTANGLE, CIRCLE, CAPSULE, POLYGON, SEGMENT, CHAIN_SEGMENT }
