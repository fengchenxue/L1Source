-- 基础行为原型的参数。只改数字就能调手感，改完重新开始试玩即可。
local Config = {}

Config.DefaultMode = 5

-- 多人测试：主持人能统一切换所有人的模式、跳法、辅助和 NPC，还能开新一轮（清零计分）；其他人只能看到这一轮的设置。
-- 体验的所有者自动是主持人（群组体验是群主），在 Studio 里测时人人都是。要让别人也当主持人，把他的 UserId 填进来
Config.TestHostUserIds = {}

-- 移动
Config.WalkSpeed = 16
Config.JumpPower = 50

-- 蓄力（模式 1、3、4）
Config.ChargeTime = 0.8 -- 蓄满要几秒
Config.ChargeWalkSpeed = 6 -- 蓄力时的移动速度

-- 发射
Config.LaunchSpeedMin = 45 -- 轻按就松开的发射速度
Config.LaunchSpeedMax = 120 -- 蓄满的发射速度
Config.LaunchPitchDeg = 35 -- 发射仰角；镜头往上看会飞得更高
Config.AirSteer = 35 -- 空中用方向键改变飞行方向的力度
Config.AirMaxSpeed = 130 -- 空中水平速度上限

-- 锁定
Config.LockRange = 70 -- 飞踢能锁定多远的目标
Config.LockConeDot = 0.35 -- 目标要在镜头前方多宽的范围内，越小越宽

-- 飞踢冲刺（模式 3 空中再按，模式 4 松开）
Config.KickSpeed = 110
Config.KickDuration = 0.7 -- 冲刺最长几秒
Config.HomingTurnDeg = 200 -- 冲刺中每秒最多转向几度；越大越难躲
Config.KickLeanDeg = 45 -- 飞踢时身体后仰角度
Config.KickBounce = 45 -- 踢中后自己弹起的速度

-- 地面踢（模式 2）
Config.GroundKickRange = 18
Config.GroundKickSpeed = 70
Config.GroundKickDuration = 0.25
Config.GroundKickLeanDeg = 25

-- 命中
Config.HitRadius = 5.5 -- 判定半径，越大越容易踢中
Config.HitLagTolerance = 12 -- 服务器允许的延迟误差
Config.KnockbackMin = 90 -- 被踢飞的速度（轻踢）
Config.KnockbackMax = 170 -- 被踢飞的速度（蓄满）
Config.KnockbackUp = 50
Config.HitstopTime = 0.07 -- 命中瞬间的停顿
Config.ShakeIntensity = 1.2 -- 震屏强度

-- 踩头（模式 5）的跳法。主持人用屏幕上的按钮在几种之间切换
Config.JumpStyle = "Boost" -- "Boost" 按住加高，"Mario3D" 3D马里奥式，"Mario" 马里奥式，"Cut" 松手截断

-- 松手截断：按住正常跳，上升途中松手就把上升速度砍掉
Config.StompJumpPower = 62 -- 一直按住时的起跳速度，约 10 格高；普通跳是 50，约 6 格
Config.JumpCutFactor = 0.45 -- 上升途中松手时，剩下的上升速度保留多少；越小，点一下跳得越矮

-- 按住加高和马里奥式：都是按下立刻起跳，靠“按住、没按住、下落”三套重力控制高低
-- 重力倍数：1 是 Roblox 默认，小于 1 往上托（跳得高），大于 1 往下压（跳得矮、落得快）
Config.JumpStyles = {
	Boost = {
		Name = "按住加高",
		Power = 50, -- 起跳速度，和 Roblox 普通跳一样；点一下约 6 格
		HoldStart = 0.08, -- 按住超过这么久才开始加高，所以点一下就是标准跳
		HoldEnd = 0.3, -- 起跳后多少秒之内按住才有效
		RiseHeld = 0.4, -- 按住时上升的重力倍数，越小按住跳得越高（约 10 格）
		RiseReleased = 1, -- 没按住时上升的重力倍数
		Fall = 1.4, -- 下落的重力倍数，比 Roblox 默认稍快
		ApexHang = false, -- 最高点附近还按着时，会不会在顶上飘一下
		AutoRepeat = true, -- 按住不放，落地自动再跳（只跳标准高度，想跳高要重新按）
	},
	-- 3D马里奥式：和按住加高的跳高、按法、空中操控都一样，只是上升和下落用同样轻的重力（参考 64 和奥德赛的普通跳），
	-- 整跳慢约三分之一，多出的时间平均分在上升和下落里
	Mario3D = {
		Name = "3D马里奥式",
		Power = 40, -- 重力变轻后，点一下仍和按住加高一样高
		HoldStart = 0.08,
		HoldEnd = 0.3,
		RiseHeld = 0.19, -- 按住也和按住加高一样高
		RiseReleased = 0.63,
		Fall = 0.63, -- 和上升一样，下落不加速
		ApexHang = false,
		AutoRepeat = true,
		Bounce = 43, -- 踩中后弹起的速度，配合这套重力弹的高度和按住加高一样；不写就用 Config.StompBounce
	},
	Mario = {
		Name = "马里奥式",
		Power = 50,
		HoldStart = 0,
		HoldEnd = 0.3,
		RiseHeld = 0.6, -- 按住约 10 格
		RiseReleased = 1.7, -- 点一下约 5 格
		Fall = 1.8,
		ApexHang = true,
		AutoRepeat = false,
	},
}
Config.ApexSpeed = 6 -- 竖直速度小于这个值，算“最高点附近”
Config.ApexGravity = 0.5 -- 最高点附近还按着时的重力倍数，让人在顶上飘一下，方便对准
Config.MaxFallSpeed = 120 -- 最大下落速度
Config.JumpBufferTime = 0.1 -- 落地前多少秒按跳也算数
Config.CoyoteTime = 0.1 -- 走出平台边缘后多少秒内还能起跳
-- 踩头判定宽度：落点和对方头部中心的水平距离多近算踩中。按被踩的人区分，不管是谁来踩
Config.StompRadiusVsPlayer = 2.0 -- 踩真人：保守一点，踩得准才算
Config.StompRadiusVsNPC = 2.6 -- 踩 NPC：更宽，方便新手拿到第一次击杀
Config.StompSnap = true -- 踩中的瞬间把踩人的一方对齐到对方头顶正上方，看起来踩得很正

-- 踩头辅助（模式 5，屏幕上的按钮可以切换）："Early" 前段辅助接近，"Late" 末段吸附，"Off" 不辅助
Config.AssistMode = "Early"

-- 前段辅助接近：起跳时按移动方向选一个近处的目标，之后修正水平速度，让你朝他头顶落下；
-- 离踩到还剩 AssistCutoffTime 秒就停，这段时间留给对方躲闪。站着不动起跳不辅助
Config.AssistRange = 10 -- 起跳时多远内的人可以被选为目标
Config.AssistConeDot = 0.5 -- 目标要在移动方向前方多大角度内，0.5 约等于左右各 60 度
Config.AssistCancelDot = 0 -- 空中往别处按（和目标方向夹角超过 90 度）就取消辅助，把方向还给玩家
Config.AssistMaxHeight = 6 -- 目标头顶最多比自己脚高多少格，跳不上去的不选
Config.AssistCutoffTime = 0.2 -- 离踩到还剩几秒时停止辅助；短按长按都一样，越大对方越容易躲
Config.AssistMaxSpeed = 22 -- 辅助期间的水平速度上限（格/秒），走路是 16
Config.AssistAccelVsPlayer = 50 -- 辅助改变水平速度有多快（格/秒²），对真人
Config.AssistAccelVsNPC = 80 -- 对 NPC
Config.AssistBrakeAccel = 250 -- 辅助需要减速时（比如目标就在跟前）用的减速度，免得贴着别人起跳时撞上他的身体
Config.AssistHoldAfterCutoff = true -- 辅助停下后保持当时的水平速度，不再追对方；免得一直按着前进键被空中操控推过头
Config.AssistHoldDot = 0.8 -- 保持期间方向键偏离起跳时的方向超过约 37 度，就把操控还给玩家（键盘斜按是 45 度）

-- 末段吸附：目标和前段辅助用同一套规则（起跳或反弹时按移动方向选），
-- 只在下落、离对方头部够近时把自己往他头顶挪一点。按被踩的人区分
Config.MagnetRadiusVsPlayer = 3 -- 离真人头部多近开始吸
Config.MagnetRadiusVsNPC = 4 -- 离 NPC 头部多近开始吸
Config.MagnetSpeedVsPlayer = 3 -- 往真人头顶挪的速度（格/秒），越大越容易踩中
Config.MagnetSpeedVsNPC = 6 -- 往 NPC 头顶挪的速度（格/秒）
Config.MagnetOnlyInChain = false -- true 时只在连踩过程中吸附

-- 连踩：不落地连续踩中，反馈一次比一次强；胜负仍按每次踩中算 1 次击杀
Config.ChainHitstopBonus = 0.015 -- 每多连一次，命中停顿多几秒（最多加 3 次）
Config.ChainShakeBonus = 0.25 -- 每多连一次，震屏强多少倍
Config.ChainPitchStep = 0.12 -- 每多连一次，提示音升高多少
Config.StompBounce = 55 -- 踩中后自己弹起的速度，固定高度，不受按键影响；可以连踩。跳法里写了 Bounce 的用跳法自己的
Config.StompPower = 0.5 -- 被踩的人飞多远（0 到 1）

-- NPC 踩头 AI（主持人用屏幕上的按钮随时切换：进攻、只闲逛、不出现）
Config.NPCAttack = true -- 开局时 NPC 会不会主动踩人；false 就只闲逛
Config.NPCSightRange = 50 -- 多远内的人会被 NPC 盯上
Config.NPCTargetPlayerChance = 0.5 -- 挑目标时选中玩家的概率，其余时候踩别的 NPC
Config.NPCApproachTime = 4 -- 最多追几秒，追不上就放弃
Config.NPCJumpRange = 12 -- 离目标多近开始蓄力起跳；NPC 跳得和玩家蓄满一样高
Config.NPCChargeTime = 0.6 -- 起跳前蹲多久，这是给对手躲开的提示
Config.NPCAimError = 3 -- 瞄准误差（格），越大越容易踩空
Config.NPCAttackCooldown = 3 -- 两次进攻之间平均隔几秒

-- 场地和节奏
Config.BouncePadSpeed = 140
Config.NPCCount = 8
Config.NPCWalkSpeed = 12
Config.NPCJumpChance = 0.35
Config.NPCWanderRadius = 50 -- NPC 在离中央多远内走动和出生；场地半宽 60，要比它小
Config.NPCRespawnDelay = 2
-- 木头假人：不动、不还手，位置和数量看场地里的 DummySpot（tools/BuildArena.lua）
Config.DummyRespawnDelay = 2 -- 被踩后几秒在原位复活
Config.RespawnDelay = 1.5 -- 被踢飞后几秒复活
Config.RagdollLifetime = 4

-- 声音。rbxasset 开头的是 Studio 自带的，可以换成自己的音效 ID
Config.Sounds = {
	Launch = "rbxasset://sounds/swordlunge.wav",
	Kick = "rbxasset://sounds/swordlunge.wav",
	Hit = "rbxasset://sounds/hit.wav",
	Stomp = "rbxasset://sounds/splat.wav",
	Ouch = "rbxasset://sounds/uuhhh.mp3",
	Bounce = "rbxasset://sounds/action_jump.mp3",
	Combo = "rbxasset://sounds/electronicpingshort.wav",
}

Config.Modes = {
	{ id = 1, name = "飞", hint = "按住蓄力，松开往镜头方向飞出去。不能踢人" },
	{ id = 2, name = "踢", hint = "靠近了按一下，冲过去踢锁定的人。不能远飞" },
	{ id = 3, name = "飞+踢", hint = "按住蓄力起飞，空中再按一下，飞踢锁定的人" },
	{ id = 4, name = "一键飞踢", hint = "按住蓄力，松开直接飞踢锁定的人" },
	{ id = 5, name = "踩头", hint = "按下就跳，按住跳更高。落到别人头上踩扁，看地上的影子对准" },
}

return Config
