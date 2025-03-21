module tests.ShapeRenderer;

import vulkan.all;
import box2d3;
import std.math : abs;

/**
 * Render Rectangles, Circles and Capsules.
 */
final class ShapeRenderer {
public:
    this(VulkanContext context, uint maxShapes) {
        this.context = context;
        this.maxShapes = maxShapes;
        initialise();
    }
    void destroy() {
        if(ubo) ubo.destroy();
        if(vertices) vertices.destroy();
        if(staticVertices) staticVertices.destroy();
        if(pipeline) pipeline.destroy();
        if(descriptors) descriptors.destroy();
    }
    auto camera(Camera2D camera) {
        ubo.write((u) {
            u.viewProj = camera.VP();
        });
        return this;
    }
    /**
     *  Add a rectangle to the renderer.
     *  pos is in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    uint addRectangle(b2coord pos, float2 size, Angle!float rotationACW, RGBA innerColour) {
        float2 pos2 = float2(pos.x, context.vk.windowSize().to!float.y - pos.y);
        return addShape(ShapeType.RECTANGLE, pos2, size, rotationACW, innerColour);
    }
    /**
     *  Add a circle to the renderer.
     *  pos is in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    uint addCircle(b2coord pos, float radius, Angle!float rotationACW, RGBA innerColour) {
        float2 pos2 = float2(pos.x, context.vk.windowSize().to!float.y - pos.y);
        return addShape(ShapeType.CIRCLE, pos2, float2(radius), rotationACW, innerColour);
    }
    /**
     *  Add a capsule to the renderer.
     *  pos is in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    uint addCapsule(b2coord pos, float height, float radius, Angle!float rotationACW, RGBA innerColour) {
        throwIf(height < radius, "Height must be greater than radius");
        float2 pos2 = float2(pos.x, context.vk.windowSize().to!float.y - pos.y);
        return addShape(ShapeType.CAPSULE, pos2, float2(radius, height), rotationACW, innerColour);
    }
    /**
     *  Add a polygon to the renderer.
     *  pos and vertices are in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    uint addPolygon(b2coord pos, float radius, b2coord[] vertices, Angle!float rotationACW, RGBA innerColour) {
        throwIf(vertices.length < 3, "Must have at least 3 vertices");
        throwIf(vertices.length > MAX_POLYGON_VERTICES, "Max number of vertices is %s", MAX_POLYGON_VERTICES);

        float2 pos2 = float2(pos.x, context.vk.windowSize().to!float.y - pos.y);

        // Calculate the render quad size.
        // Normalise vertices to fit into the -1 to +1 range 
        // (or close to this depending on the ratio of x and y)
        float2 maximum = float2(-float.max);
        float2 minimum = float2(float.max);

        foreach(v; vertices) {
            maximum = maximum.max(v.as!float2);
            minimum = minimum.min(v.as!float2);
        }
        float2 size = (maximum - minimum) / 2;

        // Write the vertices to the static buffer
        float2* ptr = staticVertices.map() + (numShapes*STATIC_DATA_PER_SHAPE);

        // Write numVertices and radius into ptr[0]
        ptr[0] = float2(vertices.length.as!float, radius);

        // Write the vertices
        foreach(i; 0..vertices.length) {
            float2 v = vertices[i].as!float2;

            // Swap y to convert from Box2D coordinates to Vulkan
            v = float2(v.x, -v.y);

            // Write normalised vertex 
            ptr[i+1] = v / size;
        }
        staticVertices.setDirtyRange(numShapes*STATIC_DATA_PER_SHAPE, numShapes*STATIC_DATA_PER_SHAPE+1);
        
        return addShape(ShapeType.POLYGON, pos2, size, rotationACW, innerColour);
    }
    /**  
     *  Add a segment to the renderer.
     *  p1 and p2 are in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    auto addSegment(b2coord p1, b2coord p2, RGBA innerColour, bool isGhost, bool isJoint) {

        // Add isGhost to the static buffer
        float2* ptr = staticVertices.map() + (numShapes*STATIC_DATA_PER_SHAPE);
        ptr[0] = float2(isGhost ? 1 : 0, isJoint ? 1 : 0);

        float2 v         = p2.as!float2 - p1.as!float2;
        float length     = v.length();
        float2 centre    = p1.as!float2 + v*0.5;
        auto rotation    = v.angle();

        // Convert to Vulkan coordinates (0,0 is at the top left of the screen)
        float screenY = context.vk.windowSize().to!float.y;
        centre.y = screenY - centre.y;

        // Create a vertical rectangle bounding box (width=5, height=half length)
        float2 rect = float2(5, length/2);    

        return addShape(ShapeType.SEGMENT, centre, rect, rotation, innerColour);
    }
    /** 
     *  Move a joint segment to a new position 
     *  p1 and p2 are in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    auto moveJoint(uint id, b2coord p1, b2coord p2) {
        throwIf(id >= numShapes);

        float2 v         = p2.as!float2 - p1.as!float2;
        float length     = v.length();
        float2 centre    = p1.as!float2 + v*0.5;
        auto rotation    = v.angle();

        float screenY = context.vk.windowSize().to!float.y;
        centre.y = screenY - centre.y;

        float2 rect = float2(5, length/2); 

        Vertex* ptr = vertices.map() + (id*6);

        foreach(i; 0..6) {
            ptr[i].translation = centre;
            ptr[i].size        = rect;
            ptr[i].rotation    = rotation.radians;
        }
        vertices.setDirtyRange(id, id+1);

        return this;
    }
    /** 
     *  Move a shape to a new position and rotation 
     *  newPos is in Box2D coordinates (0,0 is at the bottom left of the screen)
     */
    auto moveShape(uint id, b2coord newPos, Angle!float newRotation, bool isAwake) {
        throwIf(id >= numShapes);

        // Convert to Vulkan coordinates (0,0 is at the top left of the screen)
        float screenY = context.vk.windowSize().to!float.y;
        float2 pos = float2(newPos.x, screenY - newPos.y);

        Vertex* ptr = vertices.map() + (id*6);

        foreach(i; 0..6) {
            ptr[i].translation = pos;
            ptr[i].rotation    = newRotation.radians;
            ptr[i].isAwake     = isAwake ? 1 : 0;
        }

        vertices.setDirtyRange(id, id+1);

        return this;
    }
        
    void beforeRenderPass(Frame frame) {
        auto res = frame.resource;

        ubo.upload(res.adhocCB);
        vertices.upload(res.adhocCB);
        staticVertices.upload(res.adhocCB);
    }
    void insideRenderPass(Frame frame) {
        auto res = frame.resource;
        auto b = res.adhocCB;

        renderRectangles(b);
    }
private:
    enum MAX_POLYGON_VERTICES  = 8;
    enum STATIC_DATA_PER_SHAPE = 9;

    VulkanContext context;
    Descriptors descriptors;
    GPUData!UBO ubo;

    uint maxShapes;
    uint numShapes;
    GPUData!Vertex vertices;
    GraphicsPipeline pipeline;
    GPUData!float2 staticVertices;

    static struct UBO {
        mat4 viewProj;
    }
    static struct Vertex {
        uint shapeType;
        float2 pos;
        float2 translation;
        float2 size;
        float rotation;
        float4 innerColour;
        uint isAwake;
    }

    void initialise() {
        this.ubo = new GPUData!UBO(context, BufID.UNIFORM, true)
            .withUploadStrategy(GPUDataUploadStrategy.RANGE)
            .initialise();
        this.vertices = new GPUData!Vertex(context, BufID.VERTEX, true, maxShapes*6)
            .withUploadStrategy(GPUDataUploadStrategy.RANGE)
            .initialise();
        this.staticVertices = new GPUData!float2(context, BufID.STORAGE, true, maxShapes*8)
            .withUploadStrategy(GPUDataUploadStrategy.RANGE)
            .withAccessAndStageMasks(
                AccessAndStageMasks(
                    VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT,
                    VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT,
                    VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                    VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
                )
            )
            .initialise();

        this.descriptors = new Descriptors(context)
            .createLayout()
                .uniformBuffer(VK_SHADER_STAGE_VERTEX_BIT)
                .storageBuffer(VK_SHADER_STAGE_FRAGMENT_BIT)                
                .sets(1)
            .build();

        descriptors.createSetFromLayout(0)
                   .add(ubo)
                   .add(staticVertices)                  
                   .write();   

        this.pipeline = new GraphicsPipeline(context)
            .withVertexInputState!Vertex(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
            .withDSLayouts(descriptors.getAllLayouts())
            .withVertexShader(context.shaders().getModule("sdf.slang"), null, "vsmain")
            .withFragmentShader(context.shaders().getModule("sdf.slang"), null, "fsmain")
            .withStdColorBlendState()
            .build();            
    }
    uint addShape(uint shapeType, float2 pos, float2 size, Angle!float rotationACW, RGBA innerColour) {
        throwIf(numShapes >= maxShapes, "Max number of shapes reached");
        
        auto i = numShapes * 6;

        const V = [
            float2(-1, -1),
            float2( 1, -1),
            float2( 1,  1),
            float2(-1,  1),
        ];

        // 0-1  (013), (123)
        // |/|
        // 3-2
        vertices
            .write((v) { *v = Vertex(shapeType, V[0], pos, size, rotationACW.radians, innerColour, 1); }, i)
            .write((v) { *v = Vertex(shapeType, V[1], pos, size, rotationACW.radians, innerColour, 1); }, i+1)
            .write((v) { *v = Vertex(shapeType, V[3], pos, size, rotationACW.radians, innerColour, 1); }, i+2)
            .write((v) { *v = Vertex(shapeType, V[1], pos, size, rotationACW.radians, innerColour, 1); }, i+3)
            .write((v) { *v = Vertex(shapeType, V[2], pos, size, rotationACW.radians, innerColour, 1); }, i+4)
            .write((v) { *v = Vertex(shapeType, V[3], pos, size, rotationACW.radians, innerColour, 1); }, i+5);

        return numShapes++;
    }
    void renderRectangles(VkCommandBuffer cmd) {
        if(numShapes == 0) return;

        cmd.bindPipeline(pipeline);

        cmd.bindDescriptorSets(
            VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline.layout,
            0,                          // first set
            [descriptors.getSet(0,0)],  // descriptor sets
            null                        // dynamicOffsets
        );

        cmd.bindVertexBuffers(
            0,                                              // first binding
            [vertices.getDeviceBuffer().handle],   // buffers
            [vertices.getDeviceBuffer().offset]);  // offsets

        cmd.draw(numShapes*6, 1, 0, 0);
    }
}    
