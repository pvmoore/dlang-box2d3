module tests.ShapeRenderer;

import vulkan.all;
import box2d3;

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
    uint addRectangle(float2 pos, float2 size, Angle!float rotationACW, RGBA innerColour) {
        return addShape(ShapeType.RECTANGLE, pos, size, rotationACW, innerColour);
    }
    uint addCircle(float2 pos, float radius, Angle!float rotationACW, RGBA innerColour) {
        return addShape(ShapeType.CIRCLE, pos, float2(radius), rotationACW, innerColour);
    }
    uint addCapsule(float2 pos, float height, float radius, Angle!float rotationACW, RGBA innerColour) {
        throwIf(height < radius, "Height must be greater than radius");
        return addShape(ShapeType.CAPSULE, pos, float2(radius, height), rotationACW, innerColour);
    }
    uint addPolygon(float2 pos, float radius, float2[] vertices, Angle!float rotationACW, RGBA innerColour) {
        
        enum MAX_VERTICES       = 8;
        enum VERTICES_PER_SHAPE = MAX_VERTICES + 1;

        throwIf(vertices.length < 3, "Must have at least 3 vertices");
        throwIf(vertices.length > MAX_VERTICES, "Max number of vertices is %s", MAX_VERTICES);

        // Calculate the render quad size.
        // Normalise vertices to fit into the -1 to +1 range 
        // (or close to this depending on the ratio of x and y)
        float2 maximum = float2(-float.max);
        float2 minimum = float2(float.max);

        foreach(v; vertices) {
            maximum = maximum.max(v);
            minimum = minimum.min(v);
            //this.log("v = %s", v);
        }
        float2 size = maximum - minimum;
        float2 divisor = (maximum - minimum);
        //this.log("divisor = %s", divisor);

        // Write the vertices to the static buffer
        float2* ptr = staticVertices.map() + (numShapes*VERTICES_PER_SHAPE);

        // Write numVertices and radius into ptr[0]
        ptr[0] = float2(vertices.length.as!float, radius);
        //this.log("ptr[first] = %s", ptr[0]);

        // Write the vertices
        foreach(i; 0..MAX_VERTICES) {
            float2 v = i < vertices.length ? vertices[i] : float2(1);
            // Swap y to convert from Box2D coordinates to Vulkan
            v = float2(v.x, -v.y);

            // Write normalised vertex 
            ptr[i+1] = v / divisor;
            //this.log("ptr[%s] = %s", i, v);
        }
        staticVertices.setDirtyRange(numShapes*VERTICES_PER_SHAPE, numShapes*VERTICES_PER_SHAPE+1);
        
        return addShape(ShapeType.POLYGON, pos, size, rotationACW, innerColour);
    }
    auto moveShape(uint id, float2 newPos, Angle!float newRotation, bool isAwake) {
        throwIf(id >= numShapes);

        float2 pos = float2(newPos.x, context.vk.windowSize().to!float.y - newPos.y);
        float radians = newRotation.radians;

        Vertex* ptr = vertices.map() + (id*6);

        foreach(i; 0..6) {
            ptr[i].translation = pos;
            ptr[i].rotation = radians;
            ptr[i].isAwake = isAwake ? 1 : 0;
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
