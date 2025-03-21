module box2d3.b2coord;

import box2d3.all;

/**
 * Wrap b2Vec2 to add operator overloads and convenience functions
 */
struct b2coord {
    float x = 0;
    float y = 0;

    this(float v) {
        this.x = v;
        this.y = v;
    }
    this(float x, float y) {
        this.x = x;
        this.y = y;
    }
    float length() {
        import std.math : sqrt;
        return sqrt(x*x + y*y);
    }
    b2coord normalised() {
        return this / length();
    }
    b2coord abs() {
        import std.math : abs;
        return b2coord(abs(x), abs(y));
    }
    float min() {
        import std.algorithm : min;
        return min(x, y);
    }
    float max() {
        import std.algorithm : max;
        return max(x, y);
    }
    b2coord min(b2coord rhs) {
        import std.algorithm : min;
        return b2coord(min(x, rhs.x), min(y, rhs.y));
    }
    b2coord max(b2coord rhs) {
        import std.algorithm : max;
        return b2coord(max(x, rhs.x), max(y, rhs.y));
    }
    /**
     * Assumes 0 is up (0,1), positive angle is anticlockwise
     */
	Angle!float angle() {
		auto n = this.normalised();
		return Angle!float(-atan2(n.x, n.y));
	}

    b2coord opUnary(string)() {
        static assert(op == "-");
        return b2coord(-x, -y);
    }
    b2coord opBinary(string op)(b2coord rhs) {
        static if(op == "+") {
            return b2coord(x + rhs.x, y + rhs.y);
        } else static if(op == "-") {
            return b2coord(x - rhs.x, y - rhs.y);
        } else static if(op == "*") {
            return b2coord(x * rhs.x, y * rhs.y);
        } else static if(op == "/") {
            return b2coord(x / rhs.x, y / rhs.y);
        } else {
            static assert(0, "Unsupported operator: " ~ op);
        }
    }
    b2coord opBinary(string op)(float rhs) {
        static if(op == "+") {
            return b2coord(x + rhs, y + rhs);
        } else static if(op == "-") {
            return b2coord(x - rhs, y - rhs);
        } else static if(op == "*") {
            return b2coord(x * rhs, y * rhs);
        } else static if(op == "/") {
            return b2coord(x / rhs, y / rhs);
        } else {
            static assert(0, "Unsupported operator: " ~ op);
        }
    }
    string toString() {
        return "(%s, %s)".format(x, y);
    }
}
