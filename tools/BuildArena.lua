-- 在编辑模式下运行一次：搭一个测试场地（平台、弹簧板、出生点）
local CollectionService = game:GetService("CollectionService")

workspace.StreamingEnabled = false

local old = workspace:FindFirstChild("Arena")
if old then
	old:Destroy()
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

-- 地面
block("Floor", Vector3.new(280, 2, 280), CFrame.new(0, 0, 0), GRASS)

-- 中央高台：柱子加平台
block("CenterPillar", Vector3.new(10, 30, 10), CFrame.new(0, 16, 0), STONE)
block("CenterTop", Vector3.new(28, 2, 28), CFrame.new(0, 31, 0), ORANGE)

-- 四个中层平台（斜对角），带坡道
for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
	local x, z = s[1] * 62, s[2] * 62
	block("MidPlatform", Vector3.new(30, 2, 30), CFrame.new(x, 15, z), BLUE)
	block("MidLeg", Vector3.new(6, 14, 6), CFrame.new(x, 7, z), STONE)
	-- 坡道朝场地中心外侧，方便走上去
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Size = Vector3.new(10, 15, 30)
	ramp.Anchored = true
	ramp.Color = STONE
	ramp.Material = Enum.Material.SmoothPlastic
	-- WedgePart 的斜面朝 -Z，高的一边在 +Z
	local dir = Vector3.new(s[1], 0, 0)
	local rampPos = Vector3.new(x + s[1] * 30, 8.5, z)
	ramp.CFrame = CFrame.lookAt(rampPos, rampPos + dir)
	ramp.Parent = arena
end

-- 四个矮箱子（普通跳跃能上去）
for _, p in { Vector3.new(95, 0, 0), Vector3.new(-95, 0, 0), Vector3.new(0, 0, 95), Vector3.new(0, 0, -95) } do
	block("LowBox", Vector3.new(18, 5, 18), CFrame.new(p + Vector3.new(0, 3.5, 0)), ORANGE)
end

-- 几根柱子
for _, p in { Vector3.new(35, 0, -100), Vector3.new(-35, 0, 100), Vector3.new(100, 0, 40), Vector3.new(-100, 0, -40) } do
	block("Pillar", Vector3.new(6, 24, 6), CFrame.new(p + Vector3.new(0, 13, 0)), STONE)
end

-- 弹簧板：踩上去弹到高处
for _, p in { Vector3.new(26, 0, 0), Vector3.new(-26, 0, 0), Vector3.new(0, 0, 26), Vector3.new(0, 0, -26) } do
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

-- 出生点：四个角，复活后 2 秒无敌（D-020）
for _, s in workspace:GetChildren() do
	if s:IsA("SpawnLocation") then
		s:Destroy()
	end
end
for _, p in { Vector3.new(120, 0, 120), Vector3.new(-120, 0, 120), Vector3.new(120, 0, -120), Vector3.new(-120, 0, -120) } do
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
