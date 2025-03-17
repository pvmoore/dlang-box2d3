module tests.test_vulkan;

import vulkan;
import logging;

import core.sys.windows.windows;
import core.runtime;
import std.string             : toStringz;
import std.format             : format;
import std.datetime.stopwatch : StopWatch;
import std.random             : uniform;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.math               : abs;

import box2d3;
import tests.ShapeRenderer;
import tests.TestScene;

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
        WIDTH  = 1800,
        HEIGHT = 1200
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

    StopWatch physicsTimer;
    b2WorldId worldId;   
    Entity[] entities;

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
               .withBuffer(MemID.LOCAL, BufID.STORAGE, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 1.MB)
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

            shapeRenderer.addCapsule(pos, height*2, radius*2, 0.degrees, RGBA(0,1,1,1));    
        }

        static if(false) {
            float2[] points = [
                float2( 0.5, 0.7),    // 0.5, 1 
                float2(-0.5, 1),
                float2(-1, 0), 
                float2(-0.5, -1),
                float2(0.5, -1),
                float2(1, 0)
            ];

            float2 pos = float2(200, 200);
            float2 size = float2(100, 100);
            float radius = 0;
            shapeRenderer.addPolygon(pos, size, radius, points, 0.degrees, RGBA(0,1,0,1));
            
            
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

        this.entities = createScene(worldId, WIDTH, HEIGHT);

        foreach(ref e; entities) {
            createRenderShape(e);
        }
    }

    void createRenderShape(ref Entity e) {
        
        b2Body_SetUserData(e.bodyId, &e);

        auto screen = vk.windowSize().to!float;

        foreach(ref s; e.shapes) {
            if(s.type == ShapeType.CIRCLE) {

                CircleData circle = s.data.circle;
                
                s.renderId = this.shapeRenderer.addCircle(float2(e.pos.x, screen.y - e.pos.y), 
                                                    circle.radius, 
                                                    e.rotationACW, 
                                                    e.innerColour);
            } else if(s.type == ShapeType.RECTANGLE) {

                RectangleData rect = s.data.rectangle;

                s.renderId = this.shapeRenderer.addRectangle(float2(e.pos.x, screen.y - e.pos.y),  
                                                        rect.size, 
                                                        e.rotationACW, 
                                                        e.innerColour);
            } else if(s.type == ShapeType.CAPSULE) {

                CapsuleData capsule = s.data.capsule;

                float radius = capsule.radius;
                float height = abs(capsule.p2.y - capsule.p1.y);

                s.renderId = this.shapeRenderer.addCapsule(float2(e.pos.x, screen.y - e.pos.y), 
                                                        height, 
                                                        radius, 
                                                        e.rotationACW, 
                                                        e.innerColour);
            } else if(s.type == ShapeType.POLYGON) {

                PolygonData poly = s.data.polygon;

                s.renderId = this.shapeRenderer.addPolygon(float2(e.pos.x, screen.y - e.pos.y), 
                                                        poly.radius, 
                                                        poly.vertices, 
                                                        e.rotationACW, 
                                                        e.innerColour);

            } else throwIf(true, "Unknown shape type %s", s.type);
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

        // Body events (move/rotation events)
        b2BodyEvents bodyEvents = b2World_GetBodyEvents(worldId);
        foreach(i; 0..bodyEvents.moveCount) {
            b2BodyMoveEvent evt = bodyEvents.moveEvents[i];
            throwIf(evt.userData is null, "Userdata is null");
            Entity* entity = evt.userData.as!(Entity*);
            throwIf(entity is null, "Entity 0x%x not found", evt.userData);
            
            if(evt.fellAsleep) {
                //log("body %s fell asleep", evt.bodyId);
                entity.isAwake = false;
            }      

            entity.pos = evt.transform.p.as!float2;
            entity.rotationACW = b2Rot_GetAngle(evt.transform.q).radians;
            
            foreach(s; entity.shapes) {
                shapeRenderer.moveShape(s.renderId, entity.pos, entity.rotationACW, entity.isAwake);
            }
        }

        // Contact events (touch events)
        b2ContactEvents contactEvents = b2World_GetContactEvents(worldId);
        foreach(i; 0..contactEvents.hitCount) {
            b2ContactHitEvent evt = contactEvents.hitEvents[i];
        }
        foreach(i; 0..contactEvents.beginCount) {
            b2ContactBeginTouchEvent beginEvent = contactEvents.beginEvents[i];
        }
        foreach(i; 0..contactEvents.endCount) {
            b2ContactEndTouchEvent endEvent = contactEvents.endEvents[i];
        }

        // Sensor events
        b2SensorEvents sensorEvents = b2World_GetSensorEvents(worldId);
        foreach(i; 0..sensorEvents.beginCount) {
            b2SensorBeginTouchEvent evt = sensorEvents.beginEvents[i];
        }
        foreach(i; 0..sensorEvents.endCount) {
            b2SensorEndTouchEvent evt = sensorEvents.endEvents[i];
        }

        if((frame.number.value & 1023) == 0 && frame.number.value > 0) {
            double totalPhysicsTime = physicsTimer.peek().total!"nsecs" / 1_000_000.0f;
            log("physics time = %.3f ms", totalPhysicsTime / frame.number.value);
        }

        shapeRenderer.beforeRenderPass(frame);
    }
}
