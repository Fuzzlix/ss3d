-- Super Simple 3D Engine v1.2
-- groverburger 2019

local cpml   = require "cpml"

local mat4          = cpml.mat4;
local mat4new       = mat4.new;
local mat4transpose = mat4.transpose;
local mat4invert    = mat4.invert;
local mat4identity  = cpml.mat4.identity;
local mat4from_perspective = mat4.from_perspective;

local vec3 = cpml.vec3;

local random = love.math.random;
local abs    = math.abs;
local min    = math.min;
local max    = math.max;
local floor  = math.floor;
local rad    = math.rad;
local atan2  = math.atan2;
local sin    = math.sin;
local cos    = math.cos;
local pi     = math.pi;

local insert = table.insert;

local ipairs = ipairs;
local unpack = unpack;

local getWidth  = love.graphics.getWidth;
local getHeight = love.graphics.getHeight;
local newCanvas = love.graphics.newCanvas;
local setCanvas = love.graphics.setCanvas;
local newMesh   = love.graphics.newMesh;
local setColor  = love.graphics.setColor;
local setShader = love.graphics.setShader;
local clear     = love.graphics.clear;
local draw      = love.graphics.draw;
local setWireframe = love.graphics.setWireframe
local setMeshCullMode = love.graphics.setMeshCullMode;

local function TransposeMatrix(mat)
	return mat4transpose(mat4new(), mat)
end

local function InvertMatrix(mat)
	return mat4invert(mat4new(), mat)
end

local function CrossProduct(v1,v2)
    local ax,ay,az = v1[1], v1[2], v1[3] or 0
    local bx,by,bz = v2[1], v2[2], v2[3] or 0
    return {
      ay * bz - az * by,
      az * bx - ax * bz,
      ax * by - ay * bx
    }
end

local function VectorLength(x2,y2,z2)
    return (x2^2+y2^2+z2^2)^0.5
end

local function UnitVectorOf(vector)
    local max = VectorLength(abs(vector[1]), abs(vector[2]), abs(vector[3]))
    if max == 0 then max = 1 end
    return {vector[1]/max, vector[2]/max, vector[3]/max}
end

local function ScaleVerts(verts, sx,sy,sz)
    if sy == nil then
        sy = sx
        sz = sx
    end
    for _, this in ipairs(verts) do
        this[1] = this[1]*sx
        this[2] = this[2]*sy
        this[3] = this[3]*sz
    end

    return verts
end

local function MoveVerts(verts, sx,sy,sz)
    if sy == nil then
        sy = sx
        sz = sx
    end
    for _, this in ipairs(verts) do
        this[1] = this[1]+sx
        this[2] = this[2]+sy
        this[3] = this[3]+sz
    end

    return verts
end

-- define the shaders used in rendering the scene
local threeShader = love.graphics.newShader[[
    uniform mat4 view;
    uniform mat4 model_matrix;
    uniform mat4 model_matrix_inverse;
    uniform float ambientLight;
    uniform vec3 ambientVector;

    varying mat4 modelView;
    varying mat4 modelViewProjection;
    varying vec3 normal;
    varying vec3 vposition;

    #ifdef VERTEX
        attribute vec4 VertexNormal;

        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            modelView = view * model_matrix;
            modelViewProjection = view * model_matrix * transform_projection;

            normal = vec3(model_matrix_inverse * vec4(VertexNormal));
            vposition = vec3(model_matrix * vertex_position);

            return view * model_matrix * vertex_position;
        }
    #endif

    #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 texturecolor = Texel(texture, texture_coords);

            // if the alpha here is zero just don't draw anything here
            // otherwise alpha values of zero will render as black pixels
            if (texturecolor.a == 0.0)
            {
                discard;
            }

            float light = max(dot(normalize(ambientVector), normal), 0);
            texturecolor.rgb *= max(light, ambientLight);

            return color*texturecolor;
        }
    #endif
]]

local engine = {
  ScaleVerts = ScaleVerts,
  MoveVerts = MoveVerts,
}
--
-- create a new camera object
function engine.newCamera(fov, width, height, nearClip, farClip)
  fov      = fov or 60;
  width    = width or getWidth();
  height   = height or getHeight();
  nearClip = nearClip or 0.1;
  farClip  = farClip or 1000;
  --
  local pos   = vec3(0,0,0);
  local angle = vec3(0,0,0);
  local speed = 0.1
  local perspective = TransposeMatrix(mat4from_perspective(fov, width/height, nearClip, farClip))
  local view;
  --
  local function calcView()
    local camTransform = mat4()
    camTransform:rotate(camTransform, angle.y, vec3.unit_x);
    camTransform:rotate(camTransform, angle.x, vec3.unit_y);
    camTransform:rotate(camTransform, angle.z, vec3.unit_z);
    camTransform:translate(camTransform, pos * -1);
    view = perspective * TransposeMatrix(camTransform);
  end;
  calcView();
  --
  return {
    view   = function()
      return view;
    end,
    rotate = function(dx, dy)
      angle.x = angle.x + rad(dx * 0.5)
      angle.y = max(min(angle.y + rad(dy * 0.5), pi/2), -1*pi/2)
      calcView();
    end,
    setPos = function(x, y, z)
      pos.x = x or pos.x;
      pos.y = y or pos.y;
      pos.z = z or pos.z;
      calcView()
    end,
    move   = function(dx, dy, dz) --TODO: pos.y calculation
      local atn = atan2(dz, dx)
      pos.x = pos.x + cos(angle.x + atn) * speed
      pos.z = pos.z + sin(angle.x + atn) * speed
      calcView()
    end,
  };
end;
--
-- create a new Model object
-- given a table of verts for example: { {0,0,0}, {0,1,0}, {0,0,1} }
-- each vert is its own table that contains three coordinate numbers, and may contain 2 extra numbers as uv coordinates
-- another example, this with uvs: { {0,0,0, 0,0}, {0,1,0, 1,0}, {0,0,1, 0,1} }
-- polygons are automatically created with three consecutive verts
function engine.newModel(verts, texture, coords, color, format)
    local m = {}

    -- default values if no arguments are given
    if coords == nil then
        coords = {0,0,0}
    end
    if color == nil then
        color = {1,1,1}
    end
    if format == nil then
        format = {
            {"VertexPosition", "float", 3},
            {"VertexTexCoord", "float", 2},
            {"VertexNormal", "float", 3},
        }
    end
    if texture == nil then
        texture = newCanvas(1,1)
        setCanvas(texture)
        clear(0,0,0)
        setCanvas()
    end
    if verts == nil then
        verts = {}
    end

    -- translate verts by given coords
    for i, vert in ipairs(verts) do
        vert[1] = vert[1] + coords[1]
        vert[2] = vert[2] + coords[2]
        vert[3] = vert[3] + coords[3]

        -- if not given uv coordinates, put in random ones
        if #vert < 5 then
            vert[4] = random()
            vert[5] = random()
        end

        -- if not given normals, figure it out
        if #vert < 8 then
            local polyindex  = floor((i-1)/3)*3
            local polyfirst  = polyindex +1
            local polysecond = polyindex +2
            local polythird  = polyindex +3

            local sn1 = {
              verts[polythird][1] - verts[polysecond][1],
              verts[polythird][2] - verts[polysecond][2],
              verts[polythird][3] - verts[polysecond][3]
            }
            local sn2 = {
              verts[polysecond][1] - verts[polyfirst][1],
              verts[polysecond][2] - verts[polyfirst][2],
              verts[polysecond][3] - verts[polyfirst][3]
            }
            local cross = UnitVectorOf(CrossProduct(sn1,sn2))

            vert[6] = cross[1]
            vert[7] = cross[2]
            vert[8] = cross[3]
        end
    end

    -- define the Model object's properties
    m.mesh = nil
    if #verts > 0 then
        m.mesh = newMesh(format, verts, "triangles")
        m.mesh:setTexture(texture)
    end
    m.texture = texture
    m.format = format
    m.verts = verts
    m.transform = TransposeMatrix(mat4identity())
    m.color = color
    m.visible = true
    m.wireframe = false
    m.culling = false

    m.setVerts = function (self, verts)
        if #verts > 0 then
            self.mesh = newMesh(self.format, verts, "triangles")
            self.mesh:setTexture(self.texture)
        end
        self.verts = verts
    end

    -- translate and rotate the Model
    m.setTransform = function (self, coords, rotations)
        --if angle == nil then
        --    angle = 0
        --    axis = cpml.vec3.unit_y
        --end
        local tr = mat4identity()
        tr:translate(tr, vec3(unpack(coords)))
        if rotations ~= nil then
            for i=1, #rotations, 2 do
                tr:rotate(tr, rotations[i],rotations[i+1])
            end
        end
        self.transform = TransposeMatrix(tr)
    end

    -- returns a list of the verts this Model contains
    m.getVerts = function (self)
        local ret = {}
        for _, vert in ipairs(self.verts) do
            insert(ret, {vert[1], vert[2], vert[3]})
        end

        return ret
    end

    -- prints a list of the verts this Model contains
    m.printVerts = function (self)
        local verts = self:getVerts()
        for i, vert in ipairs(verts) do
            print(vert[1], vert[2], vert[3])
            if i%3 == 0 then
                print("---")
            end
        end
    end

    -- set a texture to this Model
    m.setTexture = function (self, tex)
        self.mesh:setTexture(tex)
    end

    return m
end

-- create a new Scene object with given canvas output size
function engine.newScene(renderWidth, renderHeight, useCanvases)
    --useCanvases = useCanvases ~= false; -- default = true
	  love.graphics.setDepthMode("lequal", true)
    --private vars
    local threeCanvas, twoCanvas
    local wfModelList   = {} -- a list of all wire frame models in the scene
    local clngModelList = {} -- a list of all culling models in the scene
    local ModelList     = {} -- a list of all other models in the scene

    local scene = {}

    if useCanvases then
      -- create a canvas that will store the rendered 3d scene
      threeCanvas = newCanvas(renderWidth, renderHeight)
      -- create a canvas that will store a 2d layer that can be drawn on top of the 3d scene
      -- useful for creating HUDs
      twoCanvas = newCanvas(renderWidth, renderHeight)
    end

    scene.fov = 90
    scene.nearClip = 0.001
    scene.farClip = 10000
    scene.camera = engine.newCamera(
      scene.fov,
      renderWidth, renderHeight,
      scene.nearClip, scene.farClip
    )

    scene.ambientLight = 0.25
    scene.ambientVector = {0,1,0}

    -- returns a reference to the model
    function scene:addModel(model)
        if     model.wireframe then wfModelList[model]   = model
        elseif model.culling   then clngModelList[model] = model
        else                        ModelList[model]     = model
        end
        return model
    end

    -- finds and removes model, returns boolean if successful
    function scene:removeModel(model)
        -- brute force ...
        wfModelList[model]   = nil
        clngModelList[model] = nil
        ModelList[model]     = nil
    end

    -- resize output canvas to given dimensions
    function scene:resize(Width, Height)
        renderWidth = Width
        renderHeight = Height
        if useCanvases then
          threeCanvas = newCanvas(renderWidth, renderHeight)
          twoCanvas = newCanvas(renderWidth, renderHeight)
        end
        self.camera.perspective = TransposeMatrix(mat4from_perspective(self.fov, renderWidth/renderHeight, self.nearClip, self.farClip))
    end

    -- renders the models in the scene to the threeCanvas
    -- will draw threeCanvas if drawArg is not given or is true (use if you want to scale the game canvas to window)
    function scene:render(drawArg)
        setColor(1,1,1)
        if useCanvases then
          setCanvas({threeCanvas, depth=true})
        end
        love.graphics.clear(scene.ambientLight,scene.ambientLight,scene.ambientLight)
        setShader(threeShader)

        -- compile camera data into usable view to send to threeShader
        local Camera = self.camera
        threeShader:send("view", Camera.view())
        threeShader:send("ambientLight", self.ambientLight)
        threeShader:send("ambientVector", self.ambientVector)

        local px, py = -renderWidth/2, -renderHeight/2
        -- go through all models and draw them
        setWireframe(false)
        for model in pairs(ModelList) do
          if model ~= nil and model.visible and #model.verts > 0 then
            threeShader:send("model_matrix", model.transform)
            threeShader:send("model_matrix_inverse", TransposeMatrix(InvertMatrix(model.transform)))
            draw(model.mesh, px, py)
          end
        end
        -- go through all culling models and draw them
        setMeshCullMode("back")
        for model in pairs(clngModelList) do
          if model ~= nil and model.visible and #model.verts > 0 then
            threeShader:send("model_matrix", model.transform)
            threeShader:send("model_matrix_inverse", TransposeMatrix(InvertMatrix(model.transform)))
            draw(model.mesh, px, py)
          end
        end
        setMeshCullMode("none")
        -- go through all wireframe models and draw them
        setWireframe(true)
        for model in pairs(wfModelList) do
          if model ~= nil and model.visible and #model.verts > 0 then
            threeShader:send("model_matrix", model.transform)
            threeShader:send("model_matrix_inverse", TransposeMatrix(InvertMatrix(model.transform)))
            draw(model.mesh, px, py)
          end
        end
        setWireframe(false)

        setShader()
        setCanvas()

        setColor(1,1,1)
        if useCanvases and drawArg ~= false then
            love.graphics.draw(threeCanvas, renderWidth/2,renderHeight/2, 0, 1,-1, renderWidth/2, renderHeight/2)
        end
    end

    -- renders the given func to the twoCanvas
    -- this is useful for drawing 2d HUDS and information on the screen in front of the 3d scene
    -- will draw threeCanvas if drawArg is not given or is true (use if you want to scale the game canvas to window)
    function scene:renderFunction(func, drawArg)
        setColor(1,1,1)
        if useCanvases then
          setCanvas(twoCanvas)
          clear(0,0,0,0)
        end
        func()
        setCanvas()

        if useCanvases and drawArg ~= false then
          draw(twoCanvas, renderWidth/2,renderHeight/2, 0, 1,1, renderWidth/2, renderHeight/2)
        end
    end

    -- useful if mouse relativeMode is enabled
    -- useful to call from love.mousemoved
    -- a simple first person mouse look function
    function scene:mouseLook(x, y, dx, dy)
      scene.camera.rotate(dx,dy);
    end

    return scene
end

-- useful functions

return engine

