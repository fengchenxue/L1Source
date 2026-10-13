-- 基础行为原型（服务器）：命中结算、被踢飞的布娃娃、NPC 和 NPC 踩头 AI、复活、计分

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ProtoConfig"))

Players.CharacterAutoLoads = false
workspace:SetAttribute("NPCAttack", Config.NPCAttack)
-- 多人测试的当前版本：主持人改，所有人跟着变（见下方 TestSetting）
workspace:SetAttribute("NPCMode", if Config.NPCAttack then "attack" else "wander")
workspace:SetAttribute("TestMode", Config.DefaultMode)
workspace:SetAttribute("TestJumpStyle", Config.JumpStyle)
workspace:SetAttribute("TestAssist", Config.AssistMode)

local remotes = Instance.new("Folder")
remotes.Name = "ProtoRemotes"
local function newRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end
local HitRemote = newRemote("Hit") -- 客户端 -> 服务器：踢中或踩中了谁
local PoseRemote = newRemote("Pose") -- 客户端 -> 服务器：当前姿势，给其他人看
local FXRemote = newRemote("FX") -- 服务器 -> 所有人：命中特效
local KickedRemote = newRemote("Kicked") -- 服务器 -> 被踢的人
local ScoredRemote = newRemote("Scored") -- 服务器 -> 踢中的人
local TestSettingRemote = newRemote("TestSetting") -- 客户端 -> 服务器：主持人改测试设置
remotes.Parent = ReplicatedStorage

-- 主持人：体验的所有者（群组体验是群主）和 Config.TestHostUserIds 里的人；在 Studio 里测时人人都是
local function isHost(plr)
	if RunService:IsStudio() or table.find(Config.TestHostUserIds, plr.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return plr.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return plr:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

local function statValue(plr, name)
	local stats = plr:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(name)
end

local ASSIST_NAMES = { Early = "前段辅助", Late = "末段吸附", Off = "不辅助" }
local NPC_MODE_NAMES = { attack = "NPC 进攻", wander = "NPC 闲逛", off = "NPC 不出现" }

-- 当前版本的设置，写进日志用
local function describeSettings()
	local modeId = workspace:GetAttribute("TestMode")
	local modeName = tostring(modeId)
	for _, m in Config.Modes do
		if m.id == modeId then
			modeName = m.name
		end
	end
	local parts = { modeName }
	if modeId == 5 then
		local style = workspace:GetAttribute("TestJumpStyle")
		table.insert(parts, if style == "Cut" then "松手截断" else Config.JumpStyles[style].Name)
		table.insert(parts, ASSIST_NAMES[workspace:GetAttribute("TestAssist")])
	end
	table.insert(parts, NPC_MODE_NAMES[workspace:GetAttribute("NPCMode")])
	return table.concat(parts, "，")
end

PhysicsService:RegisterCollisionGroup("Characters")
PhysicsService:RegisterCollisionGroup("Ragdolls")
PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Characters", false)
PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Ragdolls", false)

local ragdollFolder = Instance.new("Folder")
ragdollFolder.Name = "Ragdolls"
ragdollFolder.Parent = workspace

local npcFolder = Instance.new("Folder")
npcFolder.Name = "NPCs"
npcFolder.Parent = workspace

local function setCollisionGroup(model, group)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function isKickable(model)
	if not model or not model.Parent then
		return false
	end
	if not CollectionService:HasTag(model, "KickTarget") or model:GetAttribute("Down") then
		return false
	end
	if model:FindFirstChildOfClass("ForceField") then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and getRoot(model) ~= nil
end

-- 复制一个布娃娃身体，让它飞出去。真身直接删掉，这样不用处理网络所有权。
local function makeFlyingBody(model, velocity)
	local wasArchivable = model.Archivable
	model.Archivable = true
	local body = model:Clone()
	model.Archivable = wasArchivable
	if not body then
		return nil
	end
	body.Name = model.Name .. "_Flying"
	CollectionService:RemoveTag(body, "KickTarget")

	for _, d in body:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ForceField") or d:IsA("Sound") or d:IsA("AlignOrientation") then
			d:Destroy()
		end
	end

	local hum = body:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		hum.PlatformStand = true
		hum.EvaluateStateMachine = false
	end

	-- 新版角色用 AnimationConstraint 当关节：关掉它，身上自带的 BallSocket 就成了布娃娃关节
	for _, joint in body:GetDescendants() do
		if joint:IsA("AnimationConstraint") and joint.Name ~= "Root" then
			joint.Enabled = false
			local p0 = joint.Attachment0 and joint.Attachment0.Parent
			local p1 = joint.Attachment1 and joint.Attachment1.Parent
			if p0 and p1 then
				local noCollide = Instance.new("NoCollisionConstraint")
				noCollide.Part0 = p0
				noCollide.Part1 = p1
				noCollide.Parent = p1
			end
		end
	end

	-- 旧版角色用 Motor6D：换成 BallSocket
	for _, motor in body:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -60
			socket.TwistUpperAngle = 60
			socket.Parent = motor.Part1
			local noCollide = Instance.new("NoCollisionConstraint")
			noCollide.Part0 = motor.Part0
			noCollide.Part1 = motor.Part1
			noCollide.Parent = motor.Part1
			motor:Destroy()
		end
	end

	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CollisionGroup = "Ragdolls"
			p.CanTouch = false
			p.CanQuery = false
			if p.Parent == body then
				p.CanCollide = p.Name ~= "HumanoidRootPart"
			end
			if p.Name == "HumanoidRootPart" then
				p.Massless = true
				p.Transparency = 1
			end
		end
	end

	body.Parent = ragdollFolder

	local spin = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			pcall(function()
				p:SetNetworkOwner(nil)
			end)
			p.AssemblyLinearVelocity = velocity
			p.AssemblyAngularVelocity = spin
		end
	end

	local torso = body:FindFirstChild("UpperTorso") or body:FindFirstChild("Torso") or getRoot(body)
	if torso then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.8, 0)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.8, 0)
		a1.Parent = torso
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.6
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 90, 60))
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.LightEmission = 0.5
		trail.Parent = torso
	end

	Debris:AddItem(body, Config.RagdollLifetime)
	return torso
end

local pendingRespawn = {}
local function respawnPlayer(plr, delay)
	if pendingRespawn[plr] then
		return
	end
	pendingRespawn[plr] = true
	task.delay(delay, function()
		pendingRespawn[plr] = nil
		if plr.Parent then
			plr:LoadCharacter()
		end
	end)
end

local spawnNPC, spawnDummy
local dummySpots = {} -- 木头假人 -> 它站的位置

local function knockOut(target, velocity, attackerName, kind)
	target:SetAttribute("Down", true)
	local root = getRoot(target)
	local pos = root and root.Position or target:GetPivot().Position
	local torso = makeFlyingBody(target, velocity)
	FXRemote:FireAllClients(pos, kind, velocity.Magnitude)

	local victim = Players:GetPlayerFromCharacter(target)
	local spot = dummySpots[target]
	dummySpots[target] = nil
	if victim then
		local downs = statValue(victim, "被踩")
		if downs then
			downs.Value += 1
		end
		KickedRemote:FireClient(victim, torso, attackerName, kind)
		target:Destroy()
		respawnPlayer(victim, Config.RespawnDelay)
	elseif spot then
		target:Destroy()
		task.delay(Config.DummyRespawnDelay, spawnDummy, spot)
	else
		target:Destroy()
		task.delay(Config.NPCRespawnDelay, spawnNPC)
	end
end

local lastHit = {}
HitRemote.OnServerEvent:Connect(function(plr, target, kind, power, dir)
	local char = plr.Character
	local root = getRoot(char)
	if not root or char:GetAttribute("Down") then
		return
	end
	if kind ~= "kick" and kind ~= "stomp" then
		return
	end
	if typeof(target) ~= "Instance" or target == char or not isKickable(target) then
		return
	end
	local now = os.clock()
	if lastHit[plr] and now - lastHit[plr] < 0.12 then
		return
	end
	local targetRoot = getRoot(target)
	if (targetRoot.Position - root.Position).Magnitude > Config.HitRadius + Config.HitLagTolerance then
		return
	end
	lastHit[plr] = now

	power = math.clamp(tonumber(power) or 0, 0, 1)
	local flat
	if typeof(dir) == "Vector3" then
		flat = Vector3.new(dir.X, 0, dir.Z)
	end
	if not flat or flat.Magnitude < 0.05 then
		flat = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	end
	flat = flat.Unit

	local speed = Config.KnockbackMin + (Config.KnockbackMax - Config.KnockbackMin) * power
	local velocity = flat * speed + Vector3.new(0, Config.KnockbackUp + speed * 0.2, 0)
	local victim = Players:GetPlayerFromCharacter(target)
	local victimIsPlayer = victim ~= nil
	local victimName = if victim then victim.DisplayName else target.Name
	knockOut(target, velocity, plr.DisplayName, kind)

	local total = statValue(plr, "踢飞")
	local real = statValue(plr, "踢真人")
	if total then
		total.Value += 1
	end
	if real and victimIsPlayer then
		real.Value += 1
	end
	ScoredRemote:FireClient(plr, kind, victimIsPlayer)
	-- 测试日志：主持人在开发者控制台（F9）的服务器日志里能看到
	print(string.format("[测试] %s %s %s（%s）", plr.DisplayName, if kind == "stomp" then "踩中" else "踢中", victimName,
		describeSettings()))
end)

local validPoses = { [""] = true, charge = true, fly = true, kick = true }
PoseRemote.OnServerEvent:Connect(function(plr, pose)
	local char = plr.Character
	if char and validPoses[pose] then
		char:SetAttribute("Pose", pose)
	end
end)

-- 移动 NPC 三档：进攻、只闲逛、不出现（木头假人不受影响）
local function countNPCs()
	local n = 0
	for _, npc in npcFolder:GetChildren() do
		if npc.Name == "NPC" then
			n += 1
		end
	end
	return n
end

local function setNPCMode(npcMode)
	workspace:SetAttribute("NPCMode", npcMode)
	workspace:SetAttribute("NPCAttack", npcMode == "attack")
	if npcMode == "off" then
		for _, npc in npcFolder:GetChildren() do
			if npc.Name == "NPC" then
				npc:Destroy()
			end
		end
	else
		for _ = countNPCs() + 1, Config.NPCCount do
			task.spawn(spawnNPC)
		end
	end
end

-- 主持人换版本（模式、跳法、辅助）时结算上一个版本：每个人的计分写进日志、发给所有人看，然后清零。
-- 这个版本里没人击倒过、也没人被击倒过（比如主持人连点按钮跳过中间的跳法），就不显示
local resultSeq = 0
local function settleVersion()
	local lines, anyScore = {}, false
	for _, p in Players:GetPlayers() do
		local kills, real, downs = statValue(p, "踢飞"), statValue(p, "踢真人"), statValue(p, "被踩")
		local k, r, d = kills and kills.Value or 0, real and real.Value or 0, downs and downs.Value or 0
		if k + d > 0 then
			anyScore = true
		end
		table.insert(lines, string.format("%s：击倒 %d（真人 %d），被击倒 %d", p.DisplayName, k, r, d))
		for _, v in { kills, real, downs } do
			v.Value = 0
		end
	end
	if not anyScore then
		return
	end
	local title = "上一个版本（" .. describeSettings() .. "）"
	print("[测试] " .. title .. "结束")
	for _, line in lines do
		print("[测试]   " .. line)
	end
	resultSeq += 1
	workspace:SetAttribute("LastResult", title .. "\n" .. table.concat(lines, "\n"))
	workspace:SetAttribute("LastResultSeq", resultSeq)
end

local MODE_IDS = {}
for _, m in Config.Modes do
	MODE_IDS[m.id] = true
end

-- 换版本的设置：改之前先结算上一个版本
local VERSION_KEYS = {
	Mode = { attribute = "TestMode", valid = function(v) return MODE_IDS[v] ~= nil end },
	JumpStyle = { attribute = "TestJumpStyle", valid = function(v) return v == "Cut" or Config.JumpStyles[v] ~= nil end },
	Assist = { attribute = "TestAssist", valid = function(v) return ASSIST_NAMES[v] ~= nil end },
}

TestSettingRemote.OnServerEvent:Connect(function(plr, key, value)
	if not isHost(plr) then
		return
	end
	local versionKey = VERSION_KEYS[key]
	if versionKey and versionKey.valid(value) then
		if workspace:GetAttribute(versionKey.attribute) == value then
			return
		end
		settleVersion()
		workspace:SetAttribute(versionKey.attribute, value)
	elseif key == "NPCMode" and NPC_MODE_NAMES[value] then
		setNPCMode(value)
	else
		return
	end
	print(string.format("[测试] %s 切换到：%s", plr.DisplayName, describeSettings()))
end)

-- NPC：平时随机走动和跳；打开“NPC 进攻”后会挑人，蹲下蓄力，再跳过去踩头
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { ragdollFolder, npcFolder }

local function groundPoint()
	local r = Config.NPCWanderRadius
	local origin = Vector3.new(math.random(-r, r), 150, math.random(-r, r))
	local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), groundParams)
	return hit and hit.Position or Vector3.new(origin.X, 1, origin.Z)
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function headTop(model)
	local head = model:FindFirstChild("Head")
	if head then
		return head.Position.Y + head.Size.Y / 2
	end
	return getRoot(model).Position.Y + 3
end

-- 挑目标：视野内最近的三个人里随机挑一个，玩家按概率挑；木头假人留给玩家，不挑
local function pickTarget(npc)
	local root = getRoot(npc)
	local candidates = {}
	for _, m in CollectionService:GetTagged("KickTarget") do
		if m ~= npc and isKickable(m) and not dummySpots[m] then
			local dist = flatDistance(getRoot(m).Position, root.Position)
			local isPlayer = Players:GetPlayerFromCharacter(m) ~= nil
			if dist <= Config.NPCSightRange and (not isPlayer or math.random() < Config.NPCTargetPlayerChance) then
				table.insert(candidates, { model = m, dist = dist })
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	return candidates[math.random(1, math.min(3, #candidates))].model
end

local npcFlights = {}

local function npcStompAttempt(npc, hum, target)
	local root = getRoot(npc)
	local function stillValid()
		return npc.Parent ~= nil and not npc:GetAttribute("Down") and isKickable(target)
	end

	-- 走近
	local started = os.clock()
	while os.clock() - started < Config.NPCApproachTime do
		if not stillValid() then
			return
		end
		if flatDistance(getRoot(target).Position, root.Position) <= Config.NPCJumpRange then
			break
		end
		hum:MoveTo(getRoot(target).Position)
		task.wait(0.25)
	end
	if not stillValid() or flatDistance(getRoot(target).Position, root.Position) > Config.NPCJumpRange then
		return
	end

	-- 蓄力：停下来蹲一下，给对手躲开的机会
	hum:MoveTo(root.Position)
	npc:SetAttribute("Pose", "charge")
	task.wait(Config.NPCChargeTime)
	npc:SetAttribute("Pose", "")
	if not stillValid() then
		return
	end

	-- 起跳：和玩家蓄满一样高；瞄准对手现在的位置（不预判），加随机误差，下落时经过对方头顶
	local err = Config.NPCAimError
	local aim = getRoot(target).Position
		+ Vector3.new((math.random() * 2 - 1) * err, 0, (math.random() * 2 - 1) * err)
	local from = root.Position
	local rootAboveFeet = root.Size.Y / 2 + hum.HipHeight
	local dy = headTop(target) + rootAboveFeet - from.Y
	local vy = Config.StompJumpPower
	local g = workspace.Gravity
	local disc = vy * vy - 2 * g * dy
	if disc <= 0 then
		return -- 对方站得太高，跳不上去
	end
	local flightTime = (vy + math.sqrt(disc)) / g
	local horizontal = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z) / flightTime
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = horizontal + Vector3.new(0, vy, 0)
	npc:SetAttribute("Pose", "fly")
	npcFlights[npc] = { vel = horizontal, start = os.clock() }

	local jumped = os.clock()
	while npcFlights[npc] and os.clock() - jumped < 3 do
		task.wait(0.1)
	end
	if npc.Parent then
		npc:SetAttribute("Pose", "")
	end
end

-- NPC 在空中：保持水平速度，检查有没有踩到别人头上
RunService.PreSimulation:Connect(function()
	for npc, flight in npcFlights do
		local root = getRoot(npc)
		local hum = npc:FindFirstChildOfClass("Humanoid")
		if not root or not hum or not npc.Parent or npc:GetAttribute("Down") then
			npcFlights[npc] = nil
			continue
		end
		local cur = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(flight.vel.X, cur.Y, flight.vel.Z)
		if cur.Y < -4 then
			local feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
			for _, m in CollectionService:GetTagged("KickTarget") do
				if m ~= npc and isKickable(m) then
					local top = headTop(m)
					local tp = getRoot(m).Position
					local dx, dz = tp.X - root.Position.X, tp.Z - root.Position.Z
					local radius = if Players:GetPlayerFromCharacter(m)
						then Config.StompRadiusVsPlayer
						else Config.StompRadiusVsNPC
					if dx * dx + dz * dz <= radius * radius and feetY <= top + 1.5 and feetY >= top - 2 then
						local flat = Vector3.new(dx, 0, dz)
						flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.xAxis
						local speed = Config.KnockbackMin + (Config.KnockbackMax - Config.KnockbackMin) * Config.StompPower
						knockOut(m, flat * speed + Vector3.new(0, Config.KnockbackUp + speed * 0.2, 0), "NPC", "stomp")
						if Config.StompSnap then
							root.CFrame = CFrame.new(tp.X, top + root.Size.Y / 2 + hum.HipHeight, tp.Z) * root.CFrame.Rotation
						end
						root.AssemblyLinearVelocity = Vector3.new(cur.X * 0.3, Config.StompBounce, cur.Z * 0.3)
						flight.vel *= 0.3
						break
					end
				end
			end
		end
		local elapsed = os.clock() - flight.start
		if (elapsed > 0.25 and hum.FloorMaterial ~= Enum.Material.Air) or elapsed > 3 then
			npcFlights[npc] = nil
		end
	end
end)

local function npcBrain(npc, hum)
	local nextAttack = os.clock() + 1 + math.random() * 3
	while npc.Parent and hum.Health > 0 and not npc:GetAttribute("Down") do
		if workspace:GetAttribute("NPCAttack") and os.clock() >= nextAttack then
			local target = pickTarget(npc)
			if target then
				npcStompAttempt(npc, hum, target)
			end
			nextAttack = os.clock() + Config.NPCAttackCooldown * (0.6 + math.random() * 0.8)
		else
			hum:MoveTo(groundPoint())
			if math.random() < Config.NPCJumpChance then
				hum.Jump = true
			end
			task.wait(0.8 + math.random() * 1.5)
		end
	end
end

local WALK_ANIM = "rbxassetid://507777826"

-- 生成一个 R15 小人：头、身体和手臂、腿各一种颜色；去掉自带脚本，标成可以被踢、被踩的目标
local function newNPCModel(name, headColor, bodyColor, legColor)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = headColor
	desc.TorsoColor = bodyColor
	desc.LeftArmColor = bodyColor
	desc.RightArmColor = bodyColor
	desc.LeftLegColor = legColor
	desc.RightLegColor = legColor

	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("NPC 生成失败：", npc)
		return nil
	end
	npc.Name = name
	for _, d in npc:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end

	local hum = npc:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	setCollisionGroup(npc, "Characters")
	CollectionService:AddTag(npc, "KickTarget")
	return npc, hum
end

-- 木头假人：站在场地标好的位置（Arena 里的 DummySpot）不动、不还手，给玩家练手；被踩后在原位复活
local DUMMY_WOOD = Color3.fromRGB(205, 160, 110)
local DUMMY_LEGS = Color3.fromRGB(150, 110, 70)

spawnDummy = function(spot)
	if not spot.Parent then
		return
	end
	local npc, hum = newNPCModel("Dummy", DUMMY_WOOD, DUMMY_WOOD, DUMMY_LEGS)
	if not npc then
		return
	end
	local root = getRoot(npc)
	local groundY = spot.Position.Y - spot.Size.X / 2 -- 圆盘平放在地上，厚度是 Size.X
	local standY = groundY + hum.HipHeight + root.Size.Y / 2
	npc:PivotTo(CFrame.new(spot.Position.X, standY, spot.Position.Z) * CFrame.Angles(0, math.random() * 2 * math.pi, 0))
	root.Anchored = true -- 钉在原地，被人撞也不动
	dummySpots[npc] = spot
	npc.Parent = npcFolder
end

spawnNPC = function()
	if workspace:GetAttribute("NPCMode") == "off" then
		return
	end
	local npc, hum = newNPCModel(
		"NPC",
		Color3.fromRGB(255, 220, 170),
		Color3.fromHSV(math.random(), 0.65, 1),
		Color3.fromRGB(60, 60, 90)
	)
	if not npc then
		return
	end
	-- 生成要等一会儿：等完再看一次，主持人可能刚关掉 NPC，或者补齐时已经够数
	if workspace:GetAttribute("NPCMode") == "off" or countNPCs() >= Config.NPCCount then
		npc:Destroy()
		return
	end
	hum.WalkSpeed = Config.NPCWalkSpeed
	npc:PivotTo(CFrame.new(groundPoint() + Vector3.new(0, 4, 0)))
	npc.Parent = npcFolder
	pcall(function()
		getRoot(npc):SetNetworkOwner(nil)
	end)

	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = WALK_ANIM
	local okTrack, walkTrack = pcall(function()
		return animator:LoadAnimation(walkAnim)
	end)
	if okTrack and walkTrack then
		hum.Running:Connect(function(speed)
			if speed > 1 then
				if not walkTrack.IsPlaying then
					walkTrack:Play()
				end
			elseif walkTrack.IsPlaying then
				walkTrack:Stop()
			end
		end)
	end

	hum.Died:Connect(function()
		if not npc:GetAttribute("Down") then
			npc:SetAttribute("Down", true)
			task.delay(Config.NPCRespawnDelay, function()
				npc:Destroy()
				spawnNPC()
			end)
		end
	end)

	task.spawn(npcBrain, npc, hum)
end

-- 玩家
local function onCharacterAdded(plr, char)
	char:SetAttribute("Pose", "")
	CollectionService:AddTag(char, "KickTarget")
	setCollisionGroup(char, "Characters")
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		if not char:GetAttribute("Down") then
			respawnPlayer(plr, Config.RespawnDelay)
		end
	end)
end

local function onPlayerAdded(plr)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local total = Instance.new("IntValue")
	total.Name = "踢飞"
	total.Parent = stats
	local real = Instance.new("IntValue")
	real.Name = "踢真人"
	real.Parent = stats
	local downs = Instance.new("IntValue")
	downs.Name = "被踩"
	downs.Parent = stats
	stats.Parent = plr
	plr:SetAttribute("TestHost", isHost(plr))

	plr.CharacterAdded:Connect(function(char)
		onCharacterAdded(plr, char)
	end)
	plr:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end
Players.PlayerRemoving:Connect(function(plr)
	lastHit[plr] = nil
	pendingRespawn[plr] = nil
end)

for _ = 1, Config.NPCCount do
	task.spawn(spawnNPC)
end
for _, spot in CollectionService:GetTagged("DummySpot") do
	spot.Transparency = 1
	task.spawn(spawnDummy, spot)
end
