-- 基础行为原型（客户端）：输入、蓄力、飞行、锁定、飞踢、踩头（按住跳更高）、落点影子、命中表现和界面

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("ProtoConfig"))
local remotes = ReplicatedStorage:WaitForChild("ProtoRemotes")
local HitRemote = remotes:WaitForChild("Hit")
local PoseRemote = remotes:WaitForChild("Pose")
local FXRemote = remotes:WaitForChild("FX")
local KickedRemote = remotes:WaitForChild("Kicked")
local ScoredRemote = remotes:WaitForChild("Scored")
local TestSettingRemote = remotes:WaitForChild("TestSetting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 模式、跳法、辅助都跟着服务器上这一轮的设置走（多人测试时主持人统一切换）
local mode = workspace:GetAttribute("TestMode") or Config.DefaultMode
local state = "idle" -- idle / charging / flying / kicking / hitstop / down
local character, humanoid, root, alignOri
local chargeStart = 0
local flightVel = Vector3.zero
local flightStart = 0
local kickPower = 0
local kickDir = Vector3.new(0, 0, -1)
local kickSpeed = 0
local kickEnd = 0
local kickLean = 0
local kickTarget = nil
local airKickUsed = false
local lastBounce = 0
local recentlyHit = {}
local localPose = ""
local actionHeld = false -- 动作键是否按着（模式 5 里动作键也能跳）
local jumpRising = false -- 模式 5：起跳后还在上升，松手就截短
local jumpStart = 0
local jumpStyle = workspace:GetAttribute("TestJumpStyle") or Config.JumpStyle -- 模式 5 的跳法："Boost"、"Mario3D"、"Mario" 或 "Cut"
local customJumpStart = -math.huge -- 按住加高和马里奥式：这一跳从什么时候开始
local customHold = "detect" -- 这一跳怎么算按住："detect" 看按键，"always" 一直算按住，"never" 不加高
local customOwnJump = false -- 这一跳是不是脚本自己发起的
local jumpQueuedAt = nil -- 起跳缓冲：最近一次按跳的时间
local lastGroundedAt = -math.huge -- 土狼时间：最近一次站在地上的时间
local lastFeetY = nil -- 上一帧脚的高度，踩头判定用来检查这一帧脚扫过了哪段高度
local chainCount = 0 -- 连踩：这次腾空里已经踩中几个
local assistMode = workspace:GetAttribute("TestAssist") or Config.AssistMode -- 模式 5 的踩头辅助："Early"、"Late" 或 "Off"
local assistTarget = nil -- 前段辅助接近：这一跳选中的目标
local assistStart = 0
local beginAssist -- 起跳时选目标，函数在后面定义
local assistIntent = nil -- 起跳时的移动方向，用来判断玩家后来有没有改主意
local assistVel = nil -- 辅助期间由脚本掌握的水平速度；Roblox 的空中操控会把速度往按键方向推，所以不能每帧重新读
local assistHold = nil -- 辅助停下后要保持的水平速度
local lastStompAt = -math.huge

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local rad = math.rad
local POSES = {
	charge = {
		RightHip = CFrame.Angles(rad(50), 0, 0),
		LeftHip = CFrame.Angles(rad(50), 0, 0),
		RightKnee = CFrame.Angles(rad(-90), 0, 0),
		LeftKnee = CFrame.Angles(rad(-90), 0, 0),
		Waist = CFrame.Angles(rad(-25), 0, 0),
		RightShoulder = CFrame.Angles(rad(-40), 0, 0),
		LeftShoulder = CFrame.Angles(rad(-40), 0, 0),
	},
	fly = {
		RightShoulder = CFrame.Angles(0, 0, rad(75)),
		LeftShoulder = CFrame.Angles(0, 0, rad(-75)),
		RightHip = CFrame.Angles(rad(-15), 0, 0),
		LeftHip = CFrame.Angles(rad(-25), 0, 0),
		LeftKnee = CFrame.Angles(rad(-40), 0, 0),
	},
	kick = {
		RightHip = CFrame.Angles(rad(45), 0, 0),
		RightKnee = CFrame.identity,
		LeftHip = CFrame.Angles(rad(20), 0, 0),
		LeftKnee = CFrame.Angles(rad(-110), 0, 0),
		Waist = CFrame.Angles(rad(-15), 0, 0),
		RightShoulder = CFrame.Angles(0, 0, rad(60)),
		LeftShoulder = CFrame.Angles(0, 0, rad(-60)),
	},
}

---------------------------------------------------------------- 界面

local gui = Instance.new("ScreenGui")
gui.Name = "ProtoUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local modeBar = Instance.new("Frame")
modeBar.BackgroundTransparency = 1
modeBar.Size = UDim2.new(0, 520, 0, 36)
modeBar.Position = UDim2.new(0.5, -260, 0, 6)
modeBar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = modeBar

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(0, 520, 0, 24)
hintLabel.Position = UDim2.new(0.5, -260, 0, 46)
hintLabel.BackgroundColor3 = Color3.new(0, 0, 0)
hintLabel.BackgroundTransparency = 0.5
hintLabel.TextColor3 = Color3.new(1, 1, 1)
hintLabel.Font = Enum.Font.GothamMedium
hintLabel.TextScaled = true
hintLabel.Parent = gui
corner(hintLabel, 6)

local scoreLabel = Instance.new("TextLabel")
scoreLabel.Size = UDim2.new(0, 160, 0, 40)
scoreLabel.Position = UDim2.new(1, -170, 0, 80)
scoreLabel.BackgroundTransparency = 1
scoreLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
scoreLabel.TextStrokeTransparency = 0
scoreLabel.Font = Enum.Font.GothamBlack
scoreLabel.TextScaled = true
scoreLabel.Text = "踢飞 0"
scoreLabel.Parent = gui

-- 多人测试的主持人才能改设置（服务器判定后写在自己身上）；其他人的按钮都藏起来，只看这一轮的设置
local function isHost()
	return player:GetAttribute("TestHost") == true
end

local NPC_MODE_ORDER = { "attack", "wander", "off" }
local NPC_MODE_NAMES = { attack = "NPC：进攻", wander = "NPC：闲逛", off = "NPC：不出现" }
local npcToggle = Instance.new("TextButton")
npcToggle.Name = "NPCToggle"
npcToggle.Size = UDim2.new(0, 150, 0, 32)
npcToggle.Position = UDim2.new(1, -170, 0, 126)
npcToggle.Font = Enum.Font.GothamBold
npcToggle.TextScaled = true
npcToggle.TextColor3 = Color3.new(1, 1, 1)
npcToggle.Parent = gui
corner(npcToggle, 8)
local function refreshNPCToggle()
	local npcMode = workspace:GetAttribute("NPCMode")
	npcToggle.Text = NPC_MODE_NAMES[npcMode] or tostring(npcMode)
	npcToggle.BackgroundColor3 = if npcMode == "attack" then Color3.fromRGB(220, 60, 60) else Color3.fromRGB(40, 40, 40)
	npcToggle.Visible = isHost()
end
workspace:GetAttributeChangedSignal("NPCMode"):Connect(refreshNPCToggle)
refreshNPCToggle()
npcToggle.Activated:Connect(function()
	local i = table.find(NPC_MODE_ORDER, workspace:GetAttribute("NPCMode")) or 0
	TestSettingRemote:FireServer("NPCMode", NPC_MODE_ORDER[i % #NPC_MODE_ORDER + 1])
end)

local function currentJumpPower()
	if mode ~= 5 then
		return Config.JumpPower
	end
	if jumpStyle == "Cut" then
		return Config.StompJumpPower
	end
	return Config.JumpStyles[jumpStyle].Power
end

-- 踩中后弹起的速度：跳法自己写了就用跳法的，免得重力不同的跳法弹的高度不一样
local function stompBounceSpeed()
	local style = Config.JumpStyles[jumpStyle]
	return if style and style.Bounce then style.Bounce else Config.StompBounce
end

local STYLE_ORDER = { "Boost", "Mario3D", "Mario", "Cut" }
local function styleName(style)
	return if style == "Cut" then "松手截断" else Config.JumpStyles[style].Name
end

local styleToggle = Instance.new("TextButton")
styleToggle.Name = "JumpStyleToggle"
styleToggle.Size = UDim2.new(0, 150, 0, 32)
styleToggle.Position = UDim2.new(1, -170, 0, 164)
styleToggle.Font = Enum.Font.GothamBold
styleToggle.TextScaled = true
styleToggle.TextColor3 = Color3.new(1, 1, 1)
styleToggle.BackgroundColor3 = Color3.fromRGB(60, 90, 200)
styleToggle.Parent = gui
corner(styleToggle, 8)
local function refreshStyleToggle()
	styleToggle.Text = "跳法：" .. styleName(jumpStyle)
	styleToggle.Visible = mode == 5 and isHost()
end
local ASSIST_ORDER = { "Early", "Late", "Off" }
local ASSIST_NAMES = { Early = "前段辅助", Late = "末段吸附", Off = "不辅助" }
local assistToggle = Instance.new("TextButton")
assistToggle.Name = "AssistToggle"
assistToggle.Size = UDim2.new(0, 150, 0, 32)
assistToggle.Position = UDim2.new(1, -170, 0, 202)
assistToggle.Font = Enum.Font.GothamBold
assistToggle.TextScaled = true
assistToggle.TextColor3 = Color3.new(1, 1, 1)
assistToggle.BackgroundColor3 = Color3.fromRGB(40, 140, 90)
assistToggle.Parent = gui
corner(assistToggle, 8)
local function refreshAssistToggle()
	assistToggle.Text = "辅助：" .. ASSIST_NAMES[assistMode]
	assistToggle.Visible = mode == 5 and isHost()
end

-- 这一轮的设置，所有人都能看到
local testInfo = Instance.new("TextLabel")
testInfo.Size = UDim2.new(0, 520, 0, 20)
testInfo.Position = UDim2.new(0.5, -260, 0, 74)
testInfo.BackgroundColor3 = Color3.new(0, 0, 0)
testInfo.BackgroundTransparency = 0.5
testInfo.TextColor3 = Color3.fromRGB(255, 230, 120)
testInfo.Font = Enum.Font.GothamMedium
testInfo.TextScaled = true
testInfo.Parent = gui
corner(testInfo, 6)
local function refreshTestInfo()
	local parts = { "第 " .. tostring(workspace:GetAttribute("TestRound") or 1) .. " 轮", Config.Modes[mode].name }
	if mode == 5 then
		table.insert(parts, styleName(jumpStyle))
		table.insert(parts, ASSIST_NAMES[assistMode])
	end
	table.insert(parts, NPC_MODE_NAMES[workspace:GetAttribute("NPCMode")] or "")
	testInfo.Text = table.concat(parts, "｜")
end

local roundButton = Instance.new("TextButton")
roundButton.Name = "NewRoundButton"
roundButton.Size = UDim2.new(0, 150, 0, 32)
roundButton.Position = UDim2.new(1, -170, 0, 240)
roundButton.Font = Enum.Font.GothamBold
roundButton.TextScaled = true
roundButton.TextColor3 = Color3.new(1, 1, 1)
roundButton.BackgroundColor3 = Color3.fromRGB(150, 80, 200)
roundButton.Text = "新一轮（计分清零）"
roundButton.Parent = gui
corner(roundButton, 8)
roundButton.Activated:Connect(function()
	TestSettingRemote:FireServer("NewRound")
end)

-- 上一轮结果：开新一轮时给所有人看一会儿
local summaryLabel = Instance.new("TextLabel")
summaryLabel.Size = UDim2.new(0, 360, 0, 200)
summaryLabel.Position = UDim2.new(0, 16, 0.5, -100)
summaryLabel.BackgroundColor3 = Color3.new(0, 0, 0)
summaryLabel.BackgroundTransparency = 0.35
summaryLabel.TextColor3 = Color3.new(1, 1, 1)
summaryLabel.Font = Enum.Font.GothamMedium
summaryLabel.TextSize = 16
summaryLabel.TextWrapped = true
summaryLabel.TextXAlignment = Enum.TextXAlignment.Left
summaryLabel.TextYAlignment = Enum.TextYAlignment.Top
summaryLabel.AutomaticSize = Enum.AutomaticSize.Y
summaryLabel.Visible = false
summaryLabel.Parent = gui
corner(summaryLabel, 8)
local summaryPadding = Instance.new("UIPadding")
summaryPadding.PaddingLeft = UDim.new(0, 10)
summaryPadding.PaddingRight = UDim.new(0, 10)
summaryPadding.PaddingTop = UDim.new(0, 8)
summaryPadding.PaddingBottom = UDim.new(0, 8)
summaryPadding.Parent = summaryLabel
local summaryToken = 0
workspace:GetAttributeChangedSignal("LastRoundSummary"):Connect(function()
	summaryToken += 1
	local token = summaryToken
	summaryLabel.Text = workspace:GetAttribute("LastRoundSummary") or ""
	summaryLabel.Visible = true
	task.delay(12, function()
		if token == summaryToken then
			summaryLabel.Visible = false
		end
	end)
end)

assistToggle.Activated:Connect(function()
	local i = table.find(ASSIST_ORDER, assistMode) or 0
	TestSettingRemote:FireServer("Assist", ASSIST_ORDER[i % #ASSIST_ORDER + 1])
end)

styleToggle.Activated:Connect(function()
	local i = table.find(STYLE_ORDER, jumpStyle) or 0
	TestSettingRemote:FireServer("JumpStyle", STYLE_ORDER[i % #STYLE_ORDER + 1])
end)

local chargeBar = Instance.new("Frame")
chargeBar.Size = UDim2.new(0, 220, 0, 16)
chargeBar.Position = UDim2.new(0.5, -110, 0.72, 0)
chargeBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
chargeBar.Visible = false
chargeBar.Parent = gui
corner(chargeBar, 8)
local chargeFill = Instance.new("Frame")
chargeFill.Size = UDim2.new(0, 0, 1, 0)
chargeFill.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
chargeFill.Parent = chargeBar
corner(chargeFill, 8)

local banner = Instance.new("TextLabel")
banner.Size = UDim2.new(0, 420, 0, 64)
banner.Position = UDim2.new(0.5, -210, 0.28, 0)
banner.BackgroundTransparency = 1
banner.TextStrokeTransparency = 0
banner.Font = Enum.Font.GothamBlack
banner.TextScaled = true
banner.Visible = false
banner.Parent = gui

local bannerToken = 0
local function showBanner(text, color, duration)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color
	banner.Visible = true
	banner.Size = UDim2.new(0, 520, 0, 80)
	banner.Position = UDim2.new(0.5, -260, 0.28, -8)
	TweenService:Create(banner, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 420, 0, 64),
		Position = UDim2.new(0.5, -210, 0.28, 0),
	}):Play()
	task.delay(duration, function()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end

local highlight = Instance.new("Highlight")
highlight.FillColor = Color3.fromRGB(255, 70, 70)
highlight.FillTransparency = 0.65
highlight.OutlineColor = Color3.fromRGB(255, 230, 60)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = camera

---------------------------------------------------------------- 工具函数

local function playSound(id, parent, volume, pitch)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.Parent = parent or workspace
	s:Play()
	Debris:AddItem(s, 3)
end

local function alive()
	return character ~= nil
		and character.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and root.Parent ~= nil
		and state ~= "down"
end

local function grounded()
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

-- 根部到脚底的距离：R15 看 HipHeight，R6 的 HipHeight 是 0，要看腿长
local function feetOffset()
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return root.Size.Y / 2 + humanoid.HipHeight
	end
	local leg = character:FindFirstChild("Right Leg") or character:FindFirstChild("Left Leg")
	return root.Size.Y / 2 + (if leg then leg.Size.Y else 2)
end

-- 跳跃键是否按着：空格、手柄 A 键，或屏幕上的动作键
local function jumpHeld()
	return actionHeld
		or UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
end

local function flatUnit(v, fallback)
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.05 then
		return fallback
	end
	return flat.Unit
end

local function targetRoot(m)
	return m:FindFirstChild("HumanoidRootPart")
end

local function validTarget(m)
	if m == character or m.Parent == nil or m:GetAttribute("Down") then
		return false
	end
	if m:FindFirstChildOfClass("ForceField") then
		return false
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and targetRoot(m) ~= nil
end

local function recently(m)
	return recentlyHit[m] ~= nil and os.clock() - recentlyHit[m] < 1
end

-- 选目标：距离近、离镜头中心近的优先
local function findTarget(range, coneDot)
	local best, bestScore = nil, math.huge
	local look = camera.CFrame.LookVector
	for _, m in CollectionService:GetTagged("KickTarget") do
		if validTarget(m) then
			local offset = targetRoot(m).Position - root.Position
			local dist = offset.Magnitude
			if dist > 0.5 and dist <= range then
				local dot = look:Dot(offset.Unit)
				if dot >= coneDot then
					local score = dist * (2 - dot)
					if score < bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	return best
end

local function rotateTowards(from, to, maxAngle)
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-4 then
		return to
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from).Unit
end

local function setPose(pose)
	if localPose == pose then
		return
	end
	localPose = pose
	PoseRemote:FireServer(pose)
end

local shakeUntil, shakeMag = 0, 0
local function shake(mag, duration)
	shakeMag = mag
	shakeUntil = os.clock() + duration
end

local function fovPunch(amount)
	camera.FieldOfView = 70 + amount
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 70,
	}):Play()
end

---------------------------------------------------------------- 动作

local function chargeAmount()
	return math.clamp((os.clock() - chargeStart) / Config.ChargeTime, 0, 1)
end

local function startCharge()
	state = "charging"
	chargeStart = os.clock()
	humanoid.WalkSpeed = Config.ChargeWalkSpeed
	chargeBar.Visible = true
	setPose("charge")
end

local function stopCharge()
	humanoid.WalkSpeed = Config.WalkSpeed
	chargeBar.Visible = false
	if state == "charging" then
		state = "idle"
	end
	setPose("")
end

local function beginFlight(velocity, jump)
	state = "flying"
	flightStart = os.clock()
	flightVel = Vector3.new(velocity.X, 0, velocity.Z)
	humanoid:ChangeState(jump and Enum.HumanoidStateType.Jumping or Enum.HumanoidStateType.Freefall)
	jumpRising = false
	root.AssemblyLinearVelocity = velocity
	setPose("fly")
end

local function launch(power)
	local look = camera.CFrame.LookVector
	local flat = flatUnit(look, flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1)))
	local pitch = rad(Config.LaunchPitchDeg) + math.max(math.asin(math.clamp(look.Y, -1, 1)), 0) * 0.6
	pitch = math.clamp(pitch, rad(10), rad(80))
	local speed = Config.LaunchSpeedMin + (Config.LaunchSpeedMax - Config.LaunchSpeedMin) * power
	kickPower = power
	airKickUsed = false
	beginFlight(flat * math.cos(pitch) * speed + Vector3.new(0, math.sin(pitch) * speed, 0), true)
	playSound(Config.Sounds.Launch, root, 0.7, 0.8 + power * 0.5)
end

local function startKick(target, power, speed, duration, lean)
	if state == "charging" then
		stopCharge()
	end
	state = "kicking"
	kickTarget = target
	kickPower = power
	kickSpeed = speed
	kickEnd = os.clock() + duration
	kickLean = lean
	local look = camera.CFrame.LookVector
	local fallback = flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	if target then
		local offset = targetRoot(target).Position - root.Position
		kickDir = offset.Magnitude > 0.1 and offset.Unit or fallback
	elseif mode == 2 then
		kickDir = flatUnit(look, fallback)
	else
		kickDir = look.Unit
	end
	humanoid.PlatformStand = true
	alignOri.Enabled = true
	setPose("kick")
	playSound(Config.Sounds.Kick, root, 0.8, 1.2)
end

local function finishKick()
	humanoid.PlatformStand = false
	alignOri.Enabled = false
	kickTarget = nil
end

local function hitstopThen(fn, duration)
	state = "hitstop"
	root.Anchored = true
	task.delay(duration or Config.HitstopTime, function()
		if root and root.Parent then
			root.Anchored = false
		end
		if alive() then
			fn()
		end
	end)
end

local function onLocalHit(target, kind)
	recentlyHit[target] = os.clock()
	assistTarget = nil -- 踩中或踢中就解除当前辅助目标，反弹时再重新选
	assistHold = nil
	local power = kind == "stomp" and Config.StompPower or kickPower
	HitRemote:FireServer(target, kind, power, kickDir)
	shake(Config.ShakeIntensity * (0.6 + power * 0.6), 0.25)
	fovPunch(6 + power * 6)
	if kind == "kick" then
		local back = -flatUnit(kickDir, Vector3.zero) * 18
		finishKick()
		airKickUsed = false
		hitstopThen(function()
			beginFlight(back + Vector3.new(0, Config.KickBounce, 0), false)
		end)
	else
		chainCount += 1
		lastStompAt = os.clock()
		local n = chainCount
		local before = root.AssemblyLinearVelocity
		local head = target:FindFirstChild("Head")
		if Config.StompSnap and head then
			-- 命中瞬间对齐到对方头顶正上方，判定比画面宽的那部分就看不出来了
			local top = head.Position.Y + head.Size.Y / 2
			root.CFrame = CFrame.new(head.Position.X, top + feetOffset(), head.Position.Z) * root.CFrame.Rotation
		end
		if n >= 2 then
			-- 连踩：提示音一次比一次高，震屏一次比一次强
			playSound(Config.Sounds.Combo, root, 0.9, 1 + Config.ChainPitchStep * (n - 1))
			shake(Config.ShakeIntensity * (1 + Config.ChainShakeBonus * (n - 1)), 0.3)
		end
		-- 踩中后弹起来：固定高度，不受按键影响
		hitstopThen(function()
			state = "idle"
			root.AssemblyLinearVelocity = Vector3.new(before.X, stompBounceSpeed(), before.Z)
			jumpRising = false
			customJumpStart = os.clock()
			customHold = "never"
			beginAssist()
		end, Config.HitstopTime + Config.ChainHitstopBonus * math.min(n - 1, 3))
	end
end

local function checkKickHit()
	local origin = root.Position + kickDir * 1.5
	for _, m in CollectionService:GetTagged("KickTarget") do
		if validTarget(m) and not recently(m) then
			if (targetRoot(m).Position - origin).Magnitude <= Config.HitRadius then
				onLocalHit(m, "kick")
				return
			end
		end
	end
end

local function headTop(m)
	local head = m:FindFirstChild("Head")
	return if head then head.Position.Y + head.Size.Y / 2 else targetRoot(m).Position.Y + 3
end

local function stompRadiusFor(m)
	return if Players:GetPlayerFromCharacter(m) then Config.StompRadiusVsPlayer else Config.StompRadiusVsNPC
end

-- 踩头：这一帧脚扫过的高度经过对方头顶附近，并且落点离对方头部中心的水平距离够近，就算踩中。
-- 往上跳的时候不算；站到别人头上也算。踩真人和踩 NPC 的宽度不同。R15 和 R6 都按实际脚的位置算。
local function checkStomp()
	local feetY = root.Position.Y - feetOffset()
	local prevFeetY = lastFeetY or feetY
	lastFeetY = feetY
	-- 往上跳的时候不算；但已经被别人的头托住（站在头上）时，就算还在微微上升也算
	if root.AssemblyLinearVelocity.Y > 2 and not grounded() then
		return
	end
	local low, high = math.min(feetY, prevFeetY), math.max(feetY, prevFeetY)
	local best, bestDist = nil, math.huge
	for _, m in CollectionService:GetTagged("KickTarget") do
		if validTarget(m) and not recently(m) then
			local top = headTop(m)
			if high >= top - 1 and low <= top + 1.2 then
				local head = m:FindFirstChild("Head")
				local center = if head then head.Position else targetRoot(m).Position
				local dist = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z).Magnitude
				if dist <= stompRadiusFor(m) and dist < bestDist then
					best, bestDist = m, dist
				end
			end
		end
	end
	if best then
		onLocalHit(best, "stomp")
	end
end

-- 起跳或反弹时按移动方向选一个近处的目标，前段辅助和末段吸附共用；站着不动起跳、往外跑都不选
beginAssist = function()
	assistTarget = nil
	assistVel = nil
	assistHold = nil
	if mode ~= 5 or assistMode == "Off" then
		return
	end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return
	end
	move = Vector3.new(move.X, 0, move.Z).Unit
	local feetY = root.Position.Y - feetOffset()
	local best, bestScore = nil, math.huge
	for _, m in CollectionService:GetTagged("KickTarget") do
		if validTarget(m) and not recently(m) then
			local head = m:FindFirstChild("Head")
			local center = if head then head.Position else targetRoot(m).Position
			local offset = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
			local dist = offset.Magnitude
			if dist > 0.5 and dist <= Config.AssistRange and headTop(m) - feetY <= Config.AssistMaxHeight then
				local dot = move:Dot(offset.Unit)
				if dot >= Config.AssistConeDot then
					local score = dist * (2 - dot)
					if score < bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	assistTarget = best
	assistStart = os.clock()
	assistIntent = move
end

-- 空中改主意时辅助立刻让位：按键方向既偏离起跳时的方向、又背离目标才算。
-- 越过对方后还按着前进不算改主意；不按方向键也不算
local function assistCancelledByInput(center)
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return false
	end
	local to = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
	if to.Magnitude < 1.5 then
		return false
	end
	local m = Vector3.new(move.X, 0, move.Z).Unit
	local turned = if assistIntent then m:Dot(assistIntent) < 0 else true
	return turned and m:Dot(to.Unit) < Config.AssistCancelDot
end

-- 上升到最高点要多久、能再升多高。phases 是按顺序的 {重力倍数, 持续秒数}，之后按 kLast
local function riseToApex(vy, phases, kLast)
	local g = workspace.Gravity
	local t, h = 0, 0
	for _, phase in phases do
		local k, duration = phase[1], phase[2]
		if duration > 0 then
			local tStop = vy / (g * k)
			if tStop <= duration then
				return t + tStop, h + vy * tStop - 0.5 * g * k * tStop * tStop
			end
			h += vy * duration - 0.5 * g * k * duration * duration
			vy -= g * k * duration
			t += duration
		end
	end
	local tStop = vy / (g * kLast)
	return t + tStop, h + vy * vy / (2 * g * kLast)
end

-- 预估还要多久，脚会在下落途中到达 top 这个高度。按当前跳法的重力算：按住加高和马里奥式
-- 按住时上升重力变小，下落重力变大
local function timeToHeadHeight(top)
	local g = workspace.Gravity
	local vy = root.AssemblyLinearVelocity.Y
	local feetY = root.Position.Y - feetOffset()
	local style = Config.JumpStyles[jumpStyle]
	local fallK = if style then style.Fall else 1
	local tUp, apexFeet = 0, feetY
	if vy > 0 then
		local phases, kLast = {}, 1
		if style then
			kLast = style.RiseReleased
			local sinceJump = os.clock() - customJumpStart
			local holding = sinceJump <= style.HoldEnd
				and (customHold == "always" or (customHold == "detect" and jumpHeld()))
			if holding then
				phases = {
					{ style.RiseReleased, math.max(style.HoldStart - sinceJump, 0) },
					{ style.RiseHeld, math.max(style.HoldEnd - math.max(sinceJump, style.HoldStart), 0) },
				}
			end
		end
		local gain
		tUp, gain = riseToApex(vy, phases, kLast)
		apexFeet = feetY + gain
		vy = 0
	end
	local drop = apexFeet - top
	if drop <= 0 then
		return tUp
	end
	local a = g * fallK
	return tUp + (vy + math.sqrt(vy * vy + 2 * a * drop)) / a
end

-- 前段辅助：修正水平速度，让你刚好在落到对方头顶时到达他上方；
-- 离踩到还剩 AssistCutoffTime 秒、目标失效、超时或玩家改主意就停
local function applyEarlyAssist(dt)
	if assistMode ~= "Early" or not assistTarget then
		return
	end
	local v = root.AssemblyLinearVelocity
	-- 起跳那一帧速度可能还没加上，先等一下
	if v.Y < 1 and os.clock() - assistStart < 0.1 then
		return
	end
	if not validTarget(assistTarget) or os.clock() - assistStart > 1.2 then
		assistTarget = nil
		assistVel = nil
		return
	end
	local head = assistTarget:FindFirstChild("Head")
	local center = if head then head.Position else targetRoot(assistTarget).Position
	if assistCancelledByInput(center) then
		assistTarget = nil
		assistVel = nil
		return
	end
	local t = timeToHeadHeight(headTop(assistTarget))
	if t <= Config.AssistCutoffTime then
		-- 辅助结束，之后对方怎么躲都不再跟。保持现在的水平速度，免得一直按着前进键被空中操控推过头
		assistTarget = nil
		assistHold = if Config.AssistHoldAfterCutoff then assistVel else nil
		assistVel = nil
		return
	end
	-- 刚好 t 秒后到达对方头顶上方所需的水平速度，不超过上限
	local want = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z) / t
	if want.Magnitude > Config.AssistMaxSpeed then
		want = want.Unit * Config.AssistMaxSpeed
	end
	if not assistVel then
		assistVel = Vector3.new(v.X, 0, v.Z)
	end
	local accel = if Players:GetPlayerFromCharacter(assistTarget)
		then Config.AssistAccelVsPlayer
		else Config.AssistAccelVsNPC
	if want.Magnitude < assistVel.Magnitude then
		accel = math.max(accel, Config.AssistBrakeAccel)
	end
	local diff = want - assistVel
	if diff.Magnitude > 1e-3 then
		assistVel += diff.Unit * math.min(diff.Magnitude, accel * dt)
	end
	root.AssemblyLinearVelocity = Vector3.new(assistVel.X, v.Y, assistVel.Z)
end

-- 辅助停下后保持速度，沿原路落下；方向键明显换了方向，就把操控还给玩家。不按方向键不算换方向
local function applyAssistHold()
	if not assistHold then
		return
	end
	local move = humanoid.MoveDirection
	if
		move.Magnitude >= 0.1
		and assistIntent
		and Vector3.new(move.X, 0, move.Z).Unit:Dot(assistIntent) < Config.AssistHoldDot
	then
		assistHold = nil
		return
	end
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(assistHold.X, v.Y, assistHold.Z)
end

-- 末段吸附：用起跳或反弹时选好的同一个目标，只在下落、离对方头部够近时把自己往他头顶挪一点
local function applyStompMagnet(dt)
	if assistMode ~= "Late" or not assistTarget then
		return
	end
	if Config.MagnetOnlyInChain and chainCount == 0 then
		return
	end
	if not validTarget(assistTarget) or os.clock() - assistStart > 1.5 then
		assistTarget = nil
		return
	end
	local head = assistTarget:FindFirstChild("Head")
	local center = if head then head.Position else targetRoot(assistTarget).Position
	if assistCancelledByInput(center) then
		assistTarget = nil
		return
	end
	if root.AssemblyLinearVelocity.Y > -1 then
		return
	end
	if root.Position.Y - feetOffset() < headTop(assistTarget) - 0.5 then
		return
	end
	local offset = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
	local dist = offset.Magnitude
	local isPlayer = Players:GetPlayerFromCharacter(assistTarget) ~= nil
	local radius = if isPlayer then Config.MagnetRadiusVsPlayer else Config.MagnetRadiusVsNPC
	if dist < 0.1 or dist > radius then
		return
	end
	local speed = if isPlayer then Config.MagnetSpeedVsPlayer else Config.MagnetSpeedVsNPC
	root.CFrame += offset.Unit * math.min(dist, speed * dt)
end

local function checkBouncePad()
	local reach = feetOffset() + 1.5
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit and CollectionService:HasTag(hit.Instance, "BouncePad") and os.clock() - lastBounce > 0.4 then
		lastBounce = os.clock()
		if state == "charging" then
			stopCharge()
		end
		local v = root.AssemblyLinearVelocity
		airKickUsed = false
		-- 跳垫起飞不带辅助：清掉上一跳留下的辅助目标和保持速度，免得整段跳垫飞行里方向键不起作用
		assistTarget = nil
		assistVel = nil
		assistHold = nil
		beginFlight(Vector3.new(v.X, Config.BouncePadSpeed, v.Z), true)
		playSound(Config.Sounds.Bounce, root, 0.8, 1.4)
	end
end

-- 按住加高、3D马里奥式和马里奥式：起跳缓冲、土狼时间、按住自动连跳，以及按住、没按住、下落三套重力
local function customJumpStep(dt)
	local style = Config.JumpStyles[jumpStyle]
	local now = os.clock()
	local onGround = grounded()
	if onGround then
		lastGroundedAt = now
	end
	if jumpQueuedAt and now - jumpQueuedAt > Config.JumpBufferTime then
		jumpQueuedAt = nil
	end
	local canJump = now - lastGroundedAt <= Config.CoyoteTime and now - customJumpStart > 0.2
	local autoRepeat = style.AutoRepeat and onGround and jumpHeld()
	if canJump and (jumpQueuedAt or autoRepeat) then
		-- 新按下的跳可以靠按住加高；按住不放的自动连跳只跳标准高度
		customHold = if jumpQueuedAt then "detect" else "never"
		jumpQueuedAt = nil
		lastGroundedAt = -math.huge
		customJumpStart = now
		customOwnJump = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		return
	end
	-- 刚起跳、刚踩中弹起的一小段时间里，Roblox 还会把人当成站在地上（或别人头上）。这几帧也要按这一跳的重力算，
	-- 不然上升重力不是 1 的跳法会少跳一截，而且少多少每次不一样
	local v = root.AssemblyLinearVelocity
	local launching = now - customJumpStart < 0.3 and v.Y > 0
	if onGround and not launching then
		return
	end

	-- Roblox 自带重力照常生效，这里只补上差值：重力倍数 k 小于 1 往上托，大于 1 往下压
	local held = jumpHeld()
	local t = now - customJumpStart
	local holding = t >= style.HoldStart
		and t <= style.HoldEnd
		and (customHold == "always" or (customHold == "detect" and held))
	local k
	if v.Y > Config.ApexSpeed then
		k = if holding then style.RiseHeld else style.RiseReleased
	elseif style.ApexHang and v.Y > -Config.ApexSpeed and held then
		k = Config.ApexGravity
	elseif v.Y > 0 then
		k = style.RiseReleased
	else
		k = style.Fall
	end
	local vy = math.max(v.Y + (1 - k) * workspace.Gravity * dt, -Config.MaxFallSpeed)
	root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
end

---------------------------------------------------------------- 输入

local function actionBegin()
	if not alive() then
		return
	end
	if mode == 2 then
		if state == "idle" then
			startKick(
				findTarget(Config.GroundKickRange, -0.2),
				0.6,
				Config.GroundKickSpeed,
				Config.GroundKickDuration,
				Config.GroundKickLeanDeg
			)
		end
	elseif mode == 3 then
		if state == "idle" and grounded() then
			startCharge()
		elseif state == "flying" and not airKickUsed then
			airKickUsed = true
			startKick(
				findTarget(Config.LockRange, Config.LockConeDot),
				math.max(kickPower, 0.5),
				Config.KickSpeed,
				Config.KickDuration,
				Config.KickLeanDeg
			)
		end
	elseif mode == 5 then
		if jumpStyle ~= "Cut" then
			jumpQueuedAt = os.clock()
		elseif state == "idle" and grounded() then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	elseif mode == 1 or mode == 4 then
		if state == "idle" and grounded() then
			startCharge()
		end
	end
end

local function actionEnd()
	if state ~= "charging" or not alive() then
		return
	end
	local power = chargeAmount()
	stopCharge()
	if mode == 4 then
		local target = findTarget(Config.LockRange, Config.LockConeDot)
		if target then
			startKick(target, power, Config.KickSpeed, Config.KickDuration, Config.KickLeanDeg)
			return
		end
	end
	launch(power)
end

ContextActionService:BindAction("ProtoAction", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		actionHeld = true
		actionBegin()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		actionHeld = false
		actionEnd()
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle("ProtoAction", "踢")
local touchButton = ContextActionService:GetButton("ProtoAction")
if touchButton then
	touchButton.Size = UDim2.fromOffset(90, 90)
end

-- 按住加高、3D马里奥式和马里奥式下接管空格和手柄 A 键：起跳、缓冲、自动连跳都由脚本处理
ContextActionService:BindActionAtPriority("ProtoJump", function(_, inputState)
	if mode ~= 5 or jumpStyle == "Cut" then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		jumpQueuedAt = os.clock()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

local modeButtons = {}
local function setMode(id)
	mode = id
	if state == "charging" then
		stopCharge()
	elseif state == "kicking" then
		finishKick()
		state = "idle"
	end
	setPose("")
	jumpRising = false
	jumpQueuedAt = nil
	lastFeetY = nil
	chainCount = 0
	assistTarget = nil
	assistHold = nil
	refreshStyleToggle()
	refreshAssistToggle()
	for mid, b in modeButtons do
		b.BackgroundColor3 = mid == id and Color3.fromRGB(255, 160, 0) or Color3.fromRGB(40, 40, 40)
	end
	hintLabel.Text = Config.Modes[id].hint
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = currentJumpPower()
	end
	ContextActionService:SetTitle("ProtoAction", if id == 5 then "跳" else "踢")
	refreshTestInfo()
end

local function applyJumpStyle(style)
	jumpStyle = style
	jumpRising = false
	jumpQueuedAt = nil
	if humanoid then
		humanoid.JumpPower = currentJumpPower()
	end
	refreshStyleToggle()
	refreshTestInfo()
end

local function applyAssist(newMode)
	assistMode = newMode
	assistTarget = nil
	assistHold = nil
	refreshAssistToggle()
	refreshTestInfo()
end

-- 主持人改了设置，所有人跟着变
workspace:GetAttributeChangedSignal("TestMode"):Connect(function()
	setMode(workspace:GetAttribute("TestMode"))
end)
workspace:GetAttributeChangedSignal("TestJumpStyle"):Connect(function()
	applyJumpStyle(workspace:GetAttribute("TestJumpStyle"))
end)
workspace:GetAttributeChangedSignal("TestAssist"):Connect(function()
	applyAssist(workspace:GetAttribute("TestAssist"))
end)
workspace:GetAttributeChangedSignal("NPCMode"):Connect(refreshTestInfo)
workspace:GetAttributeChangedSignal("TestRound"):Connect(function()
	refreshTestInfo()
	showBanner("第 " .. tostring(workspace:GetAttribute("TestRound")) .. " 轮开始", Color3.fromRGB(255, 230, 120), 1.6)
end)

local function refreshHostControls()
	local host = isHost()
	modeBar.Visible = host
	roundButton.Visible = host
	refreshNPCToggle()
	refreshStyleToggle()
	refreshAssistToggle()
end
player:GetAttributeChangedSignal("TestHost"):Connect(refreshHostControls)
refreshHostControls()
refreshTestInfo()

for _, m in Config.Modes do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 96, 1, 0)
	b.LayoutOrder = m.id
	b.Text = m.id .. " " .. m.name
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	b.Parent = modeBar
	corner(b, 8)
	modeButtons[m.id] = b
	b.Activated:Connect(function()
		TestSettingRemote:FireServer("Mode", m.id)
	end)
end

local keyModes = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and keyModes[input.KeyCode] and isHost() then
		TestSettingRemote:FireServer("Mode", keyModes[input.KeyCode])
	end
end)

---------------------------------------------------------------- 角色

local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	state = "idle"
	localPose = ""
	airKickUsed = false
	local att = Instance.new("Attachment")
	att.Name = "ProtoAlign"
	att.Parent = root
	alignOri = Instance.new("AlignOrientation")
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = att
	alignOri.RigidityEnabled = true
	alignOri.Enabled = false
	alignOri.Parent = root
	rayParams.FilterDescendantsInstances = { char }
	humanoid.WalkSpeed = Config.WalkSpeed
	jumpRising = false
	lastFeetY = nil
	chainCount = 0
	humanoid.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Jumping or mode ~= 5 or state ~= "idle" then
			return
		end
		if jumpStyle ~= "Cut" then
			-- 不是脚本自己发起的起跳（比如手机自带跳跃键），检测不到按住：
			-- 马里奥式按一直按住算（跳满高），按住加高和3D马里奥式按标准跳算
			if customOwnJump then
				customOwnJump = false
			else
				customJumpStart = os.clock()
				customHold = if jumpStyle == "Mario" then "always" else "never"
			end
		elseif jumpHeld() then
			-- 只有能检测到按住的键（空格、手柄 A、动作键）起跳才截短；手机自带跳跃键检测不到，按满高度跳
			jumpRising = true
			jumpStart = os.clock()
		end
		beginAssist()
	end)
	setMode(mode)
end
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

local function watchScore()
	local stats = player:WaitForChild("leaderstats")
	local total = stats:WaitForChild("踢飞")
	local function refresh()
		scoreLabel.Text = "踢飞 " .. total.Value
	end
	total.Changed:Connect(refresh)
	refresh()
end
task.spawn(watchScore)

---------------------------------------------------------------- 网络事件

KickedRemote.OnClientEvent:Connect(function(bodyPart, attackerName, kind)
	state = "down"
	chargeBar.Visible = false
	highlight.Enabled = false
	localPose = ""
	if bodyPart then
		camera.CameraSubject = bodyPart
	end
	local verb = if kind == "stomp" then "踩扁了" else "踢飞了"
	showBanner("被 " .. tostring(attackerName) .. " " .. verb .. "！", Color3.fromRGB(255, 120, 120), 1.4)
	playSound(Config.Sounds.Ouch, workspace, 0.8, 1)
end)

ScoredRemote.OnClientEvent:Connect(function(kind, victimIsPlayer)
	local text = kind == "stomp" and "踩扁！" or "踢飞！"
	local color = Color3.fromRGB(255, 220, 60)
	if kind == "stomp" and chainCount >= 2 then
		-- 连踩：字越来越红
		text = chainCount .. " 连踩！"
		color = Color3.fromHSV(math.max(0, 0.13 - 0.03 * (chainCount - 2)), 1, 1)
	end
	if victimIsPlayer then
		text = text .. " 真人 +1"
	end
	showBanner(text, color, 0.8)
end)

FXRemote.OnClientEvent:Connect(function(pos, kind, power)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	local att = Instance.new("Attachment")
	att.Parent = p
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 245, 140), Color3.fromRGB(255, 120, 40))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.3, 0.6)
	pe.Speed = NumberRange.new(30, 60)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 1
	pe.Rate = 0
	pe.Parent = att
	p.Parent = workspace
	pe:Emit(math.floor(20 + (power or 0) * 0.15))
	playSound(kind == "stomp" and Config.Sounds.Stomp or Config.Sounds.Hit, p, 1, 0.9 + math.random() * 0.2)
	Debris:AddItem(p, 2)
end)

---------------------------------------------------------------- 每帧

local motorCache = setmetatable({}, { __mode = "k" })
local trailCache = setmetatable({}, { __mode = "k" })

local function getMotors(char)
	local cache = motorCache[char]
	if not cache then
		cache = {}
		for _, d in char:GetDescendants() do
			if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
				cache[d.Name] = d
			end
		end
		motorCache[char] = cache
	end
	return cache
end

local function getTrail(char)
	local t = trailCache[char]
	if t and t.Parent then
		return t
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = hrp
	t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.35
	t.Transparency = NumberSequence.new(0.2, 1)
	t.LightEmission = 0.6
	t.Enabled = false
	t.Parent = hrp
	trailCache[char] = t
	return t
end

local FLY_TRAIL = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 200, 255))
local KICK_TRAIL = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 80, 40))

-- 姿势和拖尾：玩家和 NPC 都按 Pose 属性摆，自己用本地值，不等服务器
local function applyPoses()
	for _, c in CollectionService:GetTagged("KickTarget") do
		if c.Parent then
			local pose = if c == character then localPose else (c:GetAttribute("Pose") or "")
			local def = POSES[pose]
			if def then
				local motors = getMotors(c)
				for name, cf in def do
					local m = motors[name]
					if m then
						m.Transform = cf
					end
				end
			end
			local t = getTrail(c)
			if t then
				t.Enabled = pose == "fly" or pose == "kick"
				t.Color = pose == "kick" and KICK_TRAIL or FLY_TRAIL
			end
		end
	end
end

RunService.PreSimulation:Connect(function(dt)
	applyPoses()
	if not alive() then
		return
	end

	if state == "flying" then
		flightVel += humanoid.MoveDirection * Config.AirSteer * dt
		if flightVel.Magnitude > Config.AirMaxSpeed then
			flightVel = flightVel.Unit * Config.AirMaxSpeed
		end
		local cur = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(flightVel.X, cur.Y, flightVel.Z)
		if mode == 5 then
			applyEarlyAssist(dt)
			applyAssistHold()
			applyStompMagnet(dt)
			checkStomp()
		end
		if state == "flying" and os.clock() - flightStart > 0.15 and grounded() then
			state = "idle"
			setPose("")
		end
		if state == "flying" then
			checkBouncePad()
		end
	elseif state == "kicking" then
		if kickTarget and validTarget(kickTarget) then
			local to = targetRoot(kickTarget).Position - root.Position
			if to.Magnitude > 0.1 then
				kickDir = rotateTowards(kickDir, to.Unit, rad(Config.HomingTurnDeg) * dt)
			end
		end
		root.AssemblyLinearVelocity = kickDir * kickSpeed
		local up = math.abs(kickDir.Y) > 0.95 and Vector3.new(0, 0, 1) or Vector3.yAxis
		alignOri.CFrame = CFrame.lookAt(Vector3.zero, kickDir, up) * CFrame.Angles(rad(kickLean), 0, 0)
		checkKickHit()
		if state == "kicking" and os.clock() > kickEnd then
			finishKick()
			local v = root.AssemblyLinearVelocity
			beginFlight(Vector3.new(v.X * 0.35, math.min(v.Y, 0) * 0.3, v.Z * 0.35), false)
		end
	elseif state == "idle" or state == "charging" then
		if mode == 5 then
			-- 先判踩头：站到别人头上时，踩中优先于按住跳跃键的自动连跳
			checkStomp()
		end
		if mode == 5 and state ~= "hitstop" then
			-- 按住跳更高：按住加高和马里奥式靠重力；截断式在上升途中松开跳跃键（或动作键）就把上升速度截短
			if jumpStyle ~= "Cut" then
				customJumpStep(dt)
			elseif jumpRising then
				local v = root.AssemblyLinearVelocity
				if v.Y <= 0 then
					-- 起跳那一帧速度可能还没加上，等一下再判断是不是已经在下落
					if os.clock() - jumpStart > 0.1 then
						jumpRising = false
					end
				elseif not jumpHeld() then
					root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * Config.JumpCutFactor, v.Z)
					jumpRising = false
				end
			end
			applyEarlyAssist(dt)
			applyAssistHold()
			applyStompMagnet(dt)
			checkStomp()
			-- 落地就清零连踩；刚踩中时脚还贴着对方头顶，留一点时间
			if state == "idle" and grounded() and os.clock() - lastStompAt > 0.25 then
				chainCount = 0
			end
			-- 落地就解除辅助目标（末段吸附的目标会保留到落地）
			if state == "idle" and grounded() and os.clock() - assistStart > 0.2 then
				assistTarget = nil
				assistHold = nil
			end
		end
		if state ~= "hitstop" then
			checkBouncePad()
		end
	end
end)

-- 落点影子：人在空中时，地上显示一个黑圈，方便对准，也方便看见谁要踩下来
local shadowFolder = Instance.new("Folder")
shadowFolder.Name = "ProtoShadows"
shadowFolder.Parent = workspace
local shadowParams = RaycastParams.new()
shadowParams.FilterType = Enum.RaycastFilterType.Exclude
local shadows = {}

local function updateShadows()
	local ignore = { shadowFolder }
	for _, name in { "Ragdolls", "NPCs" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	shadowParams.FilterDescendantsInstances = ignore

	local seen = {}
	for _, m in CollectionService:GetTagged("KickTarget") do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r and m.Parent and not m:GetAttribute("Down") then
			local hit = workspace:Raycast(r.Position, Vector3.new(0, -200, 0), shadowParams)
			if hit and r.Position.Y - hit.Position.Y > 4.5 then
				local s = shadows[m]
				if not s then
					s = Instance.new("Part")
					s.Shape = Enum.PartType.Cylinder
					s.Size = Vector3.new(0.2, 4, 4)
					s.Color = Color3.new(0, 0, 0)
					s.Material = Enum.Material.SmoothPlastic
					s.Anchored = true
					s.CanCollide = false
					s.CanQuery = false
					s.CanTouch = false
					s.CastShadow = false
					s.Parent = shadowFolder
					shadows[m] = s
				end
				s.Transparency = 0.45
				s.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, rad(90))
				seen[m] = true
			end
		end
	end
	for m, s in shadows do
		if not seen[m] then
			if m.Parent == nil then
				s:Destroy()
				shadows[m] = nil
			else
				s.Transparency = 1
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	updateShadows()
	if humanoid and humanoid.Parent then
		if os.clock() < shakeUntil then
			local k = (shakeUntil - os.clock()) / 0.25
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				* shakeMag
				* k
				* 2
		else
			humanoid.CameraOffset = Vector3.zero
		end
	end

	if not alive() then
		highlight.Enabled = false
		return
	end

	if state == "charging" then
		local a = chargeAmount()
		chargeFill.Size = UDim2.new(a, 0, 1, 0)
		chargeFill.BackgroundColor3 = a >= 1 and Color3.fromRGB(255, 80, 40) or Color3.fromRGB(255, 200, 40)
	end

	local shown = nil
	if state == "kicking" then
		shown = kickTarget
	elseif mode == 2 then
		shown = findTarget(Config.GroundKickRange, -0.2)
	elseif mode == 3 and (state == "flying" or state == "charging") then
		shown = findTarget(Config.LockRange, Config.LockConeDot)
	elseif mode == 4 then
		shown = findTarget(Config.LockRange, Config.LockConeDot)
	elseif mode == 5 then
		-- 前段辅助正在追的目标标红；离踩到还剩 AssistCutoffTime 秒时停止追踪，标记也消失
		shown = assistTarget
	end
	highlight.Adornee = shown
	highlight.Enabled = shown ~= nil
end)
