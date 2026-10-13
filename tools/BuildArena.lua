-- 在编辑模式下运行一次：搭一个测试场地（平台、弹簧板、出生点、木头假人的位置）
local CollectionService = game:GetService("CollectionService")

workspace.StreamingEnabled = false

local old = workspace:FindFirstChild("Arena")
if old then
	old:Destroy()
end
-- 默认底板会让人走出场地；去掉后场地四周是围墙，越过围墙就掉下去复活
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end

local arena = Instance.new("Model")
arena.Name = "Arena"

local function block(name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = arena
	return p
end

local GRASS = Color3.fromRGB(110, 200, 120)
local STONE = Color3.fromRGB(235, 225, 200)
local ORANGE = Color3.fromRGB(255, 170, 70)
local BLUE = Color3.fromRGB(90, 170, 255)
local PINK = Color3.fromRGB(255, 80, 180)

local HALF = 60 -- 场地半宽：地面 120 x 120

-- 地面
block("Floor", Vector3.new(HALF * 2, 2, HALF * 2), CFrame.new(0, 0, 0), GRASS)

-- 围墙：半透明，镜头可以穿过去；高 20 格，普通跳和跳垫都出不去
for _, s in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
	local size = if s.X ~= 0 then Vector3.new(2, 20, HALF * 2 + 4) else Vector3.new(HALF * 2 + 4, 20, 2)
	local wall = block("Wall", size, CFrame.new(s * (HALF + 1) + Vector3.new(0, 11, 0)), BLUE)
	wall.Transparency = 0.75
	wall.CastShadow = false
end

-- 中央高台：柱子加平台，靠跳垫上去
block("CenterPillar", Vector3.new(8, 30, 8), CFrame.new(0, 16, 0), STONE)
block("CenterTop", Vector3.new(20, 2, 20), CFrame.new(0, 31, 0), ORANGE)

-- 四个中层平台（斜对角），坡道按风车方向排开，不朝围墙
for _, p in {
	{ pos = Vector3.new(34, 0, 34), dir = Vector3.new(0, 0, -1) },
	{ pos = Vector3.new(34, 0, -34), dir = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(-34, 0, -34), dir = Vector3.new(0, 0, 1) },
	{ pos = Vector3.new(-34, 0, 34), dir = Vector3.new(1, 0, 0) },
} do
	block("MidPlatform", Vector3.new(16, 2, 16), CFrame.new(p.pos + Vector3.new(0, 11, 0)), BLUE)
	block("MidLeg", Vector3.new(5, 10, 5), CFrame.new(p.pos + Vector3.new(0, 6, 0)), STONE)
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Size = Vector3.new(8, 11, 18)
	ramp.Anchored = true
	ramp.Color = STONE
	ramp.Material = Enum.Material.SmoothPlastic
	-- WedgePart 的斜面朝 -Z，高的一边在 +Z；让矮的一边朝 dir，高的一边贴着平台
	local rampPos = p.pos + p.dir * (8 + 9) + Vector3.new(0, 6.5, 0)
	ramp.CFrame = CFrame.lookAt(rampPos, rampPos + p.dir)
	ramp.Parent = arena
end

-- 四个矮箱子（普通跳跃能上去）
for _, p in { Vector3.new(48, 0, 0), Vector3.new(-48, 0, 0), Vector3.new(0, 0, 48), Vector3.new(0, 0, -48) } do
	block("LowBox", Vector3.new(14, 5, 14), CFrame.new(p + Vector3.new(0, 3.5, 0)), ORANGE)
end

-- 几根柱子
for _, p in { Vector3.new(15, 0, -43), Vector3.new(-15, 0, 43), Vector3.new(43, 0, 17), Vector3.new(-43, 0, -17) } do
	block("Pillar", Vector3.new(6, 24, 6), CFrame.new(p + Vector3.new(0, 13, 0)), STONE)
end

-- 弹簧板：踩上去弹到高处
for _, p in { Vector3.new(20, 0, 0), Vector3.new(-20, 0, 0), Vector3.new(0, 0, 20), Vector3.new(0, 0, -20) } do
	local pad = Instance.new("Part")
	pad.Name = "BouncePad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, 10, 10)
	pad.CFrame = CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.Color = PINK
	pad.Material = Enum.Material.Neon
	pad.Parent = arena
	CollectionService:AddTag(pad, "BouncePad")
end

-- 木头假人的位置：服务器在每个点放一个不动的假人，被踩后原地复活。
-- 编辑模式下是地上的红圈，可以拖动、复制、删除来改位置和数量；试玩时隐藏
for _, p in {
	-- 内圈，离中央约 32 格
	Vector3.new(30, 0, -10),
	Vector3.new(-10, 0, -30),
	Vector3.new(-30, 0, 10),
	Vector3.new(10, 0, 30),
	-- 外圈，离各出生点 20 格
	Vector3.new(30, 0, 50),
	Vector3.new(50, 0, -30),
	Vector3.new(-30, 0, -50),
	Vector3.new(-50, 0, 30),
} do
	local spot = Instance.new("Part")
	spot.Name = "DummySpot"
	spot.Shape = Enum.PartType.Cylinder
	spot.Size = Vector3.new(0.2, 4, 4)
	spot.CFrame = CFrame.new(p + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.CastShadow = false
	spot.Color = Color3.fromRGB(230, 60, 60)
	spot.Transparency = 0.4
	spot.Parent = arena
	CollectionService:AddTag(spot, "DummySpot")
end

-- 出生点：四个角，复活后 2 秒无敌（D-020）
for _, s in workspace:GetChildren() do
	if s:IsA("SpawnLocation") then
		s:Destroy()
	end
end
for _, p in { Vector3.new(50, 0, 50), Vector3.new(-50, 0, 50), Vector3.new(50, 0, -50), Vector3.new(-50, 0, -50) } do
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 1, 10)
	local pos = p + Vector3.new(0, 1.5, 0)
	spawn.CFrame = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)) -- 朝向场地中央
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 2
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Parent = arena
end

arena.Parent = workspace
return "Arena built"
