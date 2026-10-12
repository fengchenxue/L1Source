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
local NPCToggleRemote = newRemote("NPCToggle") -- 客户端 -> 服务器：开关 NPC 进攻
remotes.Parent = ReplicatedStorage

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

local spawnNPC

local function knockOut(target, velocity, attackerName, kind)
	target:SetAttribute("Down", true)
	local root = getRoot(target)
	local pos = root and root.Position or target:GetPivot().Position
	local torso = makeFlyingBody(target, velocity)
	FXRemote:FireAllClients(pos, kind, velocity.Magnitude)

	local victim = Players:GetPlayerFromCharacter(target)
	if victim then
		KickedRemote:FireClient(victim, torso, attackerName, kind)
		target:Destroy()
		respawnPlayer(victim, Config.RespawnDelay)
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
	local victimIsPlayer = Players:GetPlayerFromCharacter(target) ~= nil
	knockOut(target, velocity, plr.DisplayName, kind)

	local stats = plr:FindFirstChild("leaderstats")
	if stats then
		local total = stats:FindFirstChild("踢飞")
		local real = stats:FindFirstChild("踢真人")
		if total then
			total.Value += 1
		end
		if real and victimIsPlayer then
			real.Value += 1
		end
	end
	ScoredRemote:FireClient(plr, kind, victimIsPlayer)
end)

local validPoses = { [""] = true, charge = true, fly = true, kick = true }
PoseRemote.OnServerEvent:Connect(function(plr, pose)
	local char = plr.Character
	if char and validPoses[pose] then
		char:SetAttribute("Pose", pose)
	end
end)

NPCToggleRemote.OnServerEvent:Connect(function()
	workspace:SetAttribute("NPCAttack", not workspace:GetAttribute("NPCAttack"))
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

-- 挑目标：视野内最近的三个人里随机挑一个，玩家按概率挑
local function pickTarget(npc)
	local root = getRoot(npc)
	local candidates = {}
	for _, m in CollectionService:GetTagged("KickTarget") do
		if m ~= npc and isKickable(m) then
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

spawnNPC = function()
	local desc = Instance.new("HumanoidDescription")
	local shirt = Color3.fromHSV(math.random(), 0.65, 1)
	desc.HeadColor = Color3.fromRGB(255, 220, 170)
	desc.TorsoColor = shirt
	desc.LeftArmColor = shirt
	desc.RightArmColor = shirt
	desc.LeftLegColor = Color3.fromRGB(60, 60, 90)
	desc.RightLegColor = Color3.fromRGB(60, 60, 90)

	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("NPC 生成失败：", npc)
		return
	end
	npc.Name = "NPC"
	for _, d in npc:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end

	local hum = npc:FindFirstChildOfClass("Humanoid")
	hum.WalkSpeed = Config.NPCWalkSpeed
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	npc:PivotTo(CFrame.new(groundPoint() + Vector3.new(0, 4, 0)))
	setCollisionGroup(npc, "Characters")
	CollectionService:AddTag(npc, "KickTarget")
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
	stats.Parent = plr

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
