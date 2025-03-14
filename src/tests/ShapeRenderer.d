module tests.ShapeRenderer;

import vulkan.all;

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
        if(pipeline) pipeline.destroy();
        if(descriptors) descriptors.destroy();
    }
    auto camera(Camera2D camera) {
        ubo.write((u) {
            u.viewProj = camera.VP();
        });
        return this;
    }
    uint addRectangle(float2 pos, float2 size, Angle!float rotationACW, RGBA innerColour, RGBA outerColour) {
        return addShape(0, pos, size, rotationACW, innerColour, outerColour);
    }
    uint addCircle(float2 pos, float radius, Angle!float rotationACW, RGBA innerColour, RGBA outerColour) {
        return addShape(1, pos, float2(radius), rotationACW, innerColour, outerColour);
    }
    uint addCapsule(float2 pos, float height, float radius, Angle!float rotationACW, RGBA innerColour, RGBA outerColour) {
        throwIf(height < radius, "Height must be greater than radius");
        return addShape(2, pos, float2(radius, height), rotationACW, innerColour, outerColour);
    }
    auto moveShape(uint id, float2 newPos, Angle!float newRotation) {
        throwIf(id >= numShapes);

        float2 pos = float2(newPos.x, context.vk.windowSize().to!float.y - newPos.y);
        float radians = newRotation.radians;

        Vertex* ptr = vertices.map() + (id*6);

        foreach(i; 0..6) {
            ptr[i].translation = pos;
            ptr[i].rotation = radians;
        }

        vertices.setDirtyRange(id, id+1);

        return this;
    }
        
    void beforeRenderPass(Frame frame) {
        auto res = frame.resource;

        ubo.upload(res.adhocCB);
        vertices.upload(res.adhocCB);
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
        float4 outerColour;
    }

    void initialise() {
        this.ubo = new GPUData!UBO(context, BufID.UNIFORM, true)
            .withUploadStrategy(GPUDataUploadStrategy.RANGE)
            .initialise();
        this.vertices = new GPUData!Vertex(context, BufID.VERTEX, true, maxShapes*6)
            .withUploadStrategy(GPUDataUploadStrategy.RANGE)
            .initialise();

        this.descriptors = new Descriptors(context)
            .createLayout()
                .uniformBuffer(VK_SHADER_STAGE_VERTEX_BIT)
                .sets(1)
            .build();

        descriptors.createSetFromLayout(0)
                   .add(ubo)
                   .write();   

        this.pipeline = new GraphicsPipeline(context)
            .withVertexInputState!Vertex(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
            .withDSLayouts(descriptors.getAllLayouts())
            .withVertexShader(context.shaders().getModule("rects.slang"), null, "vsmain")
            .withFragmentShader(context.shaders().getModule("rects.slang"), null, "fsmain")
            .withStdColorBlendState()
            .build();            
    }
    uint addShape(uint shapeType, float2 pos, float2 size, Angle!float rotationACW, RGBA innerColour, RGBA outerColour) {
        throwIf(numShapes >= maxShapes, "Max number of shapes reached");
        
        auto i = numShapes * 6;

        const V = [
            float2(-0.5, -0.5),
            float2( 0.5, -0.5),
            float2( 0.5,  0.5),
            float2(-0.5,  0.5),
        ];

        // 0-1  (013), (123)
        // |/|
        // 3-2
        vertices
            .write((v) { *v = Vertex(shapeType, V[0], pos, size, rotationACW.radians, innerColour, outerColour); }, i)
            .write((v) { *v = Vertex(shapeType, V[1], pos, size, rotationACW.radians, innerColour, outerColour); }, i+1)
            .write((v) { *v = Vertex(shapeType, V[3], pos, size, rotationACW.radians, innerColour, outerColour); }, i+2)
            .write((v) { *v = Vertex(shapeType, V[1], pos, size, rotationACW.radians, innerColour, outerColour); }, i+3)
            .write((v) { *v = Vertex(shapeType, V[2], pos, size, rotationACW.radians, innerColour, outerColour); }, i+4)
            .write((v) { *v = Vertex(shapeType, V[3], pos, size, rotationACW.radians, innerColour, outerColour); }, i+5);

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
