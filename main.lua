
-- ZerobraneStudio debug interface [https://studio.zerobrane.com/]
if arg[#arg] == "-debug" then
  io.stdout:setvbuf("no"); --luacheck: ignore
  require("mobdebug").start();
  _DEBUG = true; --global var to signal debugging session to all modules
end;

-- store global reference to the Engine for use in calling functions
local cpml   = require "cpml"
local Engine = require "engine"
local ScaleVerts = Engine.ScaleVerts;

local Scene
local AlakazamModel
local Pyramids
local Timer
local Paused

function love.load()
    -- make the mouse cursor locked to the screen
    love.mouse.setRelativeMode(true)
    love.window.setTitle("ss3d 1.3 demo")
    love.window.setMode(1024, 1024*9/16, {})
    love.graphics.setBackgroundColor(0.52,0.57,0.69)
    Paused = false

    -- create a Scene object which stores and renders Models
    -- arguments refer to the Scene's camera's canvas output size in pixels
    Scene = Engine.newScene(love.graphics.getWidth(), love.graphics.getHeight())
    local DefaultTexture = love.graphics.newImage("texture.png")
    Timer = 0

    Scene.camera.setPos(0,0,5)

    -- define vertices for a simple square floor
    local floorVerts = {
      {-1,-1,-1, 0, 0},
      { 1,-1,-1, 1, 0},
      {-1,-1, 1, 0, 1},
      { 1,-1, 1, 1, 1},
      {-1,-1, 1, 0, 1},
      { 1,-1,-1, 1, 0}
    }

    -- scale the vertices, then turn the vertices into a Model with a texture
    local FloorModel = Engine.newModel(ScaleVerts(floorVerts, 20,4,20), DefaultTexture)
    Scene:addModel(FloorModel)

    -- turn the vertices into a Model with a texture
    AlakazamModel = Engine.newModel(Engine.loadObj("alakazam.obj"), DefaultTexture)
    Scene:addModel(AlakazamModel)

    local pyramidVerts = {
      {-1,-1,-1},
      {-1, 1, 1},
      { 1, 1,-1},

      {-1, 1, 1},
      { 1, 1,-1},
      { 1,-1, 1},

      {-1,-1,-1},
      { 1, 1,-1},
      { 1,-1, 1},

      {-1,-1,-1},
      {-1, 1, 1},
      { 1,-1, 1},
    }

    Pyramids = {}
    for i=1, 4 do
        Pyramids[#Pyramids+1] = Engine.newModel(pyramidVerts)
        Pyramids[i].wireframe = true
        Scene:addModel(Pyramids[i])
    end
end

function love.update(dt)
    love.mouse.setRelativeMode(not Paused)
    if Paused then
        return
    end

    -- make the AlakazamModel go in circles and rotate
    Timer = Timer + dt/4
    AlakazamModel:setTransform({0,-1.5,0}, {Timer, cpml.vec3.unit_y, Timer, cpml.vec3.unit_z, Timer, cpml.vec3.unit_x})

    for i=1, #Pyramids do
        Pyramids[i]:setTransform({math.cos(Timer +i*math.pi*0.5)*12, math.sin(Timer +i)*0.75 +1, math.sin(Timer +i*math.pi*0.5)*12}, {Timer, cpml.vec3.unit_y, Timer, cpml.vec3.unit_z, Timer, cpml.vec3.unit_x})
    end

    -- simple first-person camera movement
    local mx, mz = 0, 0
    if love.keyboard.isDown("w") then
        mz = mz - 1
    end
    if love.keyboard.isDown("a") then
        mx = mx - 1
    end
    if love.keyboard.isDown("s") then
        mz = mz + 1
    end
    if love.keyboard.isDown("d") then
        mx = mx + 1
    end

    if mx ~= 0 or mz ~= 0 then
      Scene.camera.move(mx, 0, mz)
    end
end

function love.mousemoved(x,y, dx,dy)
    -- basic first person mouselook, built into Scene object
    if not Paused then
        Scene:mouseLook(x,y, dx,dy)
    end
end

function love.keypressed(k)
    if k == "space" then
        Paused = not Paused
    end
end

function love.draw()
    -- render all Models in the Scene
    love.graphics.setColor(1,1,1)
    Scene:render()

    -- render a HUD
    Scene:renderFunction(
        function ()
            love.graphics.setColor(0,0,0)
            love.graphics.print("groverburger's super simple 3d engine v1.3")
            love.graphics.print("FPS: "..love.timer.getFPS(),0,16)

            if Paused then
                love.graphics.print("PAUSED",0,32)
            end
        end
    )
end
