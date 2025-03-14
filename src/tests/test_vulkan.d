module tests.test_vulkan;

import vulkan;
import logging;

import core.sys.windows.windows;
import core.runtime;
import std.string : toStringz;
import std.format : format;
import std.datetime.stopwatch : StopWatch;
import std.random : uniform;
import std.datetime.stopwatch : StopWatch, AutoStart;

import box2d3;
import tests.ShapeRenderer;

extern(Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int iCmdShow) {
	int result = 0;
	VulkanApplication app;
	try{
        Runtime.initialize(); 
        setEagerFlushing(true);

        app = new Box2d3Demo();

		app.run();

    }catch(Throwable e) {
		log("exception: %s", e.msg);
		MessageBoxA(null, e.toString().toStringz(), "Error", MB_OK | MB_ICONEXCLAMATION);
		result = -1;
    }finally{
		flushLog();
		if(app) app.destroy();
		Runtime.terminate();
	}
	flushLog();
    return result;
}

//──────────────────────────────────────────────────────────────────────────────────────────────────

final class Box2d3Demo : VulkanApplication {
public:
    enum { 
        WIDTH            = 1800,
        HEIGHT           = 1200,
        SIMULATION_SPEED = 1.0 * 0.15,
        SIMULATION_STEPS = 4
    }

    this() {
        enum NAME = "Box3D 3 Demo";

        WindowProperties wprops = {
            width:          WIDTH,
            height:         HEIGHT,
            fullscreen:     false,
            vsync:          false,
            title:          NAME,
            icon:           "resources/images/logo.png",
            showWindow:     false,
            frameBuffers:   3,
            titleBarFps:    true,
        };
        VulkanProperties vprops = {
            appName: NAME,
            shaderSrcDirectories: ["shaders/", "/pvmoore/d/libs/vulkan/shaders/"],
            shaderDestDirectory:  "resources/shaders/",
            apiVersion: vulkanVersion(1,3,0),
            shaderSpirvVersion:   "1.6"
        };

        vprops.enableShaderPrintf = false;
        vprops.enableGpuValidation = false;

        physicsTimer = StopWatch(AutoStart.no);

        this.vk = new Vulkan(this, wprops, vprops);
        vk.initialise();
        vk.showWindow();
    }
    override void destroy() {
	    if(!vk) return;
	    if(device) {
	        vkDeviceWaitIdle(device);

            b2DestroyWorld(worldId);

            if(context) context.dumpMemory();
            if(shapeRenderer) shapeRenderer.destroy();
            if(sampler) device.destroySampler(sampler);
            if(renderPass) device.destroyRenderPass(renderPass);
            if(context) context.destroy();
	    }
		vk.destroy();
    }
    override void run() {
        vk.mainLoop();
    }
    override VkRenderPass getRenderPass(VkDevice device) {
        createRenderPass(device);
        return renderPass;
    }
    override void deviceReady(VkDevice device, PerFrameResource[] frameResources) {
        this.device = device;
        initScene();
    }
    override void selectFeatures(DeviceFeatures deviceFeatures) {
        super.selectFeatures(deviceFeatures);
    }
    void update(Frame frame) {
        updatePhysics(frame);
        updateRenderer(frame);
    }
    override void render(Frame frame) {
        auto res = frame.resource;
	    auto b = res.adhocCB;
	    b.beginOneTimeSubmit();

        update(frame);

        // begin the render pass
        b.beginRenderPass(
            renderPass,
            res.frameBuffer,
            toVkRect2D(0,0, vk.windowSize.toVkExtent2D),
            [ bgColour ],
            VK_SUBPASS_CONTENTS_INLINE
            //VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS
        );

        shapeRenderer.insideRenderPass(frame);
        
        b.endRenderPass();
        b.end();

        /// Submit our render buffer
        vk.getGraphicsQueue().submit(
            [b],
            [res.imageAvailable],
            [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT],
            [res.renderFinished],  // signal semaphores
            res.fence              // fence
        );
    }
private:
    Vulkan vk;
	VkDevice device;
    VulkanContext context;
    VkRenderPass renderPass;

    Camera2D camera;
    VkClearValue bgColour;
    VkSampler sampler;

    ShapeRenderer shapeRenderer;

    enum ShapeType { RECTANGLE, CIRCLE, CAPSULE }

    static struct Entity {
        string name;
        // Body properties
        ShapeType type;
        b2BodyId bodyId;
        bool dynamic = false;
        float2 pos;
        float2 size;
        Angle!float rotationACW = 0.degrees;
        // Shape properties
        float density = 1.0;
        float friction = 0.6f;
        // Render properties
        uint renderId;
        RGBA innerColour;
        RGBA outerColour;

        string toString() {
            return format("'%s': pos=%s, size=%s, rot=%s", name, pos, size, rotationACW);
        }
    }

    Entity[] entities;
    
    StopWatch physicsTimer;
    b2WorldId worldId;

    Entity ground = {
            name: "Ground",
            type: ShapeType.RECTANGLE,
            dynamic: false,
            pos: float2(WIDTH / 2, 70),
            size: float2(650.0f, 10.0f),
            rotationACW: 0.degrees,
            innerColour: RGBA(1,1,0,1),
            outerColour: RGBA(1,1,1,1),
        };
    Entity fallingBox = {
            name: "Falling box",
            type: ShapeType.RECTANGLE,
            dynamic: true,
            pos: float2(WIDTH / 2, 500.0f),
            size: float2(40, 40),   // half width, half height
            rotationACW: 25.degrees,
            innerColour: RGBA(0,1,0,1),
            outerColour: RGBA(1,1,1,1),
        };
    Entity fallingCircle = {
            name: "Falling circle",
            type: ShapeType.CIRCLE,
            dynamic: true,
            pos: float2(WIDTH / 2 + 200, 600.0f),
            size: float2(40, 40),   // radius, unused
            rotationACW: 0.degrees,
            innerColour: RGBA(0,1,1,1),
            outerColour: RGBA(1,1,1,1),
        };
    Entity fallingCapsule = {
            name: "Falling capsule",
            type: ShapeType.CAPSULE,
            dynamic: true,
            pos: float2(WIDTH / 2 - 300, 600.0f),
            size: float2(50, 100),  // radius, half height
            rotationACW: 20.degrees,
            innerColour: RGBA(0,1,1,1),
            outerColour: RGBA(1,1,1,1),
        };    

    void initScene() {
        this.camera = Camera2D.forVulkan(vk.windowSize);

        auto mem = new MemoryAllocator(vk);

        auto maxLocal =
            mem.builder(0)
                .withAll(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
                .withoutAll(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)
                .maxHeapSize();

        this.log("Max local memory = %s MBs", maxLocal / 1.MB);

        this.context = new VulkanContext(vk)
            .withMemory(MemID.LOCAL, mem.allocStdDeviceLocal("G2D_Local", 256.MB))
          //.withMemory(MemID.SHARED, mem.allocStdShared("G2D_Shared", 128.MB))
            .withMemory(MemID.STAGING, mem.allocStdStagingUpload("G2D_Staging", 32.MB));

        context.withBuffer(MemID.LOCAL, BufID.VERTEX, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 32.MB)
               .withBuffer(MemID.LOCAL, BufID.INDEX, VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 32.MB)
               .withBuffer(MemID.LOCAL, BufID.UNIFORM, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 1.MB)
               .withBuffer(MemID.STAGING, BufID.STAGING, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, 32.MB);

        context.withFonts("resources/fonts/")
               .withImages("resources/images/")
               .withRenderPass(renderPass);

        this.log("shared mem available = %s", context.hasMemory(MemID.SHARED));

        this.log("%s", context);

        createSampler();

        this.shapeRenderer = new ShapeRenderer(context, 1000)
            .camera(camera);

        static if(false) {
            float2 pos = float2(200, 200);
            float height = 150;
            float radius = 100;

            shapeRenderer.addCapsule(pos, height*2, radius*2, 0.degrees, RGBA(0,1,1,1), RGBA(1,1,1,1));    
        }

        static if(false) {   
            foreach(i; 0..25) {
                float size = uniform(0, (i+1)*20) + 3;
                float2 pos = float2(
                    uniform(0, vk.windowSize.width()), 
                    uniform(0, vk.windowSize.height()));
                RGBA inner = RGBA(uniform(0,1f), uniform(0,1f), uniform(0,1f), 1);
                RGBA outer = RGBA(1,1,1,1);
                auto rotation = uniform(0,360).degrees;

                this.shapeRenderer.addRectangle(
                    pos, 
                    float2(size, size), 
                    rotation, 
                    inner, 
                    outer);
            }

            foreach(i; 0..25) {
                float size = uniform(0, (i+1)*20) + 3;
                float2 pos = float2(
                    uniform(0, vk.windowSize.width()), 
                    uniform(0, vk.windowSize.height()));
                RGBA inner = RGBA(uniform(0,1f), uniform(0,1f), uniform(0,1f), 1);
                RGBA outer = RGBA(1,1,1,1);
                auto rotation = uniform(0,360).degrees;

                this.shapeRenderer.addCircle(
                    pos, 
                    size, 
                    rotation, 
                    inner, 
                    outer);
            }

        }
        this.bgColour = clearColour(0.0f, 0, 0, 1);

        createPhysicsScene();
    }
    void createSampler() {
        this.log("Creating sampler");
        sampler = device.createSampler(samplerCreateInfo());
    }
    void createRenderPass(VkDevice device) {
        this.log("Creating render pass");
        auto colorAttachment    = attachmentDescription(vk.swapchain.colorFormat);
        auto colorAttachmentRef = attachmentReference(0);

        auto subpass = subpassDescription((info) {
            info.colorAttachmentCount = 1;
            info.pColorAttachments    = &colorAttachmentRef;
        });

        auto dependency = subpassDependency();

        renderPass = .createRenderPass(
            device,
            [colorAttachment],
            [subpass],
            subpassDependency2()//[dependency]
        );
    }
    /** Create the Box2D scene */
    void createPhysicsScene() {
        this.worldId = createWorld((def) {
            def.gravity = b2Vec2(0.0f, -10.0f);
        });
        this.log("Created world %s", worldId.toString());

        addShape(ground);
        addShape(fallingBox);
        addShape(fallingCircle);
        addShape(fallingCapsule);
    }

    /** Add a shape to the scene */
    void addShape(ref Entity e) {
        
        auto screen = vk.windowSize().to!float;
        
        // Make the Box2D body
        b2BodyDef def = b2DefaultBodyDef();
        def.type = e.dynamic ? b2BodyType.b2_dynamicBody : b2BodyType.b2_staticBody;
        def.position = e.pos.as!b2Vec2;
        def.rotation = b2ComputeCosSin(e.rotationACW.radians).as!b2Rot;
        def.userData = &e;

        e.bodyId = b2CreateBody(worldId, &def);

        // Make the Box2D shape
        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = e.density;
        shapeDef.friction = e.friction;


        if(e.type == ShapeType.CIRCLE) {

            b2Circle circle = { { 0.0f, 0.0f }, e.size.x };

            b2CreateCircleShape(e.bodyId, &shapeDef, &circle);
            
            // Make the render shape
            e.renderId = this.shapeRenderer.addCircle(float2(e.pos.x, screen.y - e.pos.y), 
                                                  e.size.x * 2, 
                                                  e.rotationACW, 
                                                  e.innerColour, 
                                                  e.outerColour);
        } else if(e.type == ShapeType.RECTANGLE) {
            b2Polygon box = b2MakeBox(e.size.x, e.size.y);

            b2CreatePolygonShape(e.bodyId, &shapeDef, &box);

            // Make the render shape
            e.renderId = this.shapeRenderer.addRectangle(float2(e.pos.x, screen.y - e.pos.y),  
                                                     e.size * 2, 
                                                     e.rotationACW, 
                                                     e.innerColour, 
                                                     e.outerColour);
        } else {
            float radius = e.size.x;
            float height = e.size.y;
            float h = height / 2;
            float2 p1 = float2(0, -h);
            float2 p2 = float2(0, h);

            b2Polygon poly = b2MakeCapsule(p1.as!b2Vec2, p2.as!b2Vec2, radius);
            b2CreatePolygonShape(e.bodyId, &shapeDef, &poly);

            // Make the render shape
            e.renderId = this.shapeRenderer.addCapsule(float2(e.pos.x, screen.y - e.pos.y), 
                                                    height * 2, 
                                                    radius * 2, 
                                                    e.rotationACW, 
                                                    e.innerColour, 
                                                    e.outerColour);
        }
    }
    /** Update Box2D physics simulation */
    void updatePhysics(Frame frame) {
        float dt = (frame.perSecond * 60) * SIMULATION_SPEED;
        physicsTimer.start();
        b2World_Step(worldId, minOf(dt, 1/30f), SIMULATION_STEPS);
        physicsTimer.stop();
    }
    /** Update shapes in ShapeRenderer */
    void updateRenderer(Frame frame) {
        b2BodyEvents bodyEvents = b2World_GetBodyEvents(worldId);
        foreach(i; 0..bodyEvents.moveCount) {
            b2BodyMoveEvent evt = bodyEvents.moveEvents[i];
            if(evt.fellAsleep) {
                //log("body %s fell asleep", evt.bodyId);
            }      
            Entity* entity = evt.userData.as!(Entity*);
            entity.pos = evt.transform.p.as!float2;
            entity.rotationACW = b2Rot_GetAngle(evt.transform.q).radians;

            shapeRenderer.moveShape(entity.renderId, entity.pos, entity.rotationACW);
        }

        if((frame.number.value & 1023) == 0 && frame.number.value > 0) {
            double totalPhysicsTime = physicsTimer.peek().total!"nsecs" / 1_000_000.0f;
            log("physics time = %.3f ms", totalPhysicsTime / frame.number.value);
        }

        shapeRenderer.beforeRenderPass(frame);
    }
}
