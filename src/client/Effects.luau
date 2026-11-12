-- Effects.luau
-- Purely visual client effects (no gameplay decisions):
--   * rainbow color cycling for Rainbow-mutation parts
--   * hatch timers above eggs in nests
--   * hiding the "Steal" prompt on your own nest eggs
--   * applying knockback sent by the server to your own character

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local Effects = {}

local player = Players.LocalPlayer

local function startRainbow()
	local hue = 0
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		hue = (hue + elapsed * 0.25) % 1
		elapsed = 0
		for _, part in CollectionService:GetTagged(Config.Tags.RainbowPart) do
			if part:IsA("BasePart") then
				part.Color = Color3.fromHSV(hue, 0.8, 1)
			end
		end
	end)
end

local function startNestTimers()
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for _, model in CollectionService:GetTagged(Config.Tags.NestEgg) do
				local hatchAt = model:GetAttribute("HatchAt")
				local primary = model:IsA("Model") and model.PrimaryPart
				local timer = primary and primary:FindFirstChild("Timer")
				local label = timer and timer:FindFirstChild("Text")
				if hatchAt and label then
					local left = hatchAt - now
					label.Text = (model:GetAttribute("Label") or "Egg")
						.. "\n"
						.. (if left > 0 then Format.duration(left) else "Hatching!")
				end
				-- Your own eggs can't be stolen by you: hide the prompt.
				if primary and model:GetAttribute("OwnerId") == player.UserId then
					local prompt = primary:FindFirstChildOfClass("ProximityPrompt")
					if prompt and prompt.Enabled then
						prompt.Enabled = false
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

---------------------------------------------------------------------------
-- Eggs flying out of the volcano
---------------------------------------------------------------------------
-- The server places every egg where it lands and tags it FlyingEgg. Each
-- client draws the arc itself, so the flight is smooth and costs no network.

local flying: { [Model]: { landing: CFrame, trail: Trail? } } = {}

local function landingBurst(model: Model)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 180, 150))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Speed = NumberRange.new(6, 12)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Rate = 0
	dust.Parent = primary
	dust:Emit(14)
	Debris:AddItem(dust, 1.5)
end

local function addFlyingEgg(model: Instance)
	if not model:IsA("Model") or not model.PrimaryPart or flying[model] then
		return
	end
	local primary = model.PrimaryPart
	-- A fiery trail behind the egg.
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.9, 0)
	top.Parent = primary
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.9, 0)
	bottom.Parent = primary
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 70, 20))
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = primary
	flying[model] = { landing = model:GetPivot(), trail = trail }
end

local function finishFlyingEgg(model: Instance)
	local info = flying[model :: Model]
	if not info then
		return
	end
	flying[model :: Model] = nil
	if model.Parent and model:IsA("Model") then
		model:PivotTo(info.landing)
		landingBurst(model)
		if info.trail then
			Debris:AddItem(info.trail, 0.6)
		end
	end
end

local function startEggFlights()
	CollectionService:GetInstanceAddedSignal(Config.Tags.FlyingEgg):Connect(addFlyingEgg)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.FlyingEgg):Connect(finishFlyingEgg)
	for _, model in CollectionService:GetTagged(Config.Tags.FlyingEgg) do
		addFlyingEgg(model)
	end
	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for model, info in flying do
			local from = model:GetAttribute("FlightFrom")
			local started = model:GetAttribute("FlightStart")
			local duration = model:GetAttribute("FlightTime")
			if not model.Parent or typeof(from) ~= "Vector3" or not started or not duration then
				flying[model] = nil
				continue
			end
			local alpha = math.clamp((now - started) / duration, 0, 1)
			if alpha >= 1 then
				finishFlyingEgg(model)
				continue
			end
			local to = info.landing.Position
			local arcHeight = 50 + (to - from).Magnitude * 0.3
			local position = from:Lerp(to, alpha) + Vector3.new(0, arcHeight * 4 * alpha * (1 - alpha), 0)
			model:PivotTo(CFrame.new(position) * CFrame.Angles(alpha * 14, 0, alpha * 9))
		end
	end)
end

---------------------------------------------------------------------------
-- Eruption: rumble, camera shake and a fire burst from the crater
---------------------------------------------------------------------------

local shakeUntil, shakePower = 0, 0

function Effects.shake(power: number, seconds: number)
	shakePower = math.max(power, if os.clock() < shakeUntil then shakePower else 0)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

local function startCameraShake()
	RunService:BindToRenderStep("DinoCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		local camera = workspace.CurrentCamera
		if left <= 0 or not camera then
			return
		end
		local strength = shakePower * math.min(left, 1)
		camera.CFrame *= CFrame.new(
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength,
			0
		) * CFrame.Angles(0, 0, (math.random() - 0.5) * strength * 0.02)
	end)
end

function Effects.eruption(big: boolean, volcanoTop: Vector3)
	if typeof(volcanoTop) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - volcanoTop).Magnitude else 1000
	-- Closer to the volcano = stronger shake.
	local closeness = math.clamp(1.15 - distance / 900, 0.2, 1)
	Effects.shake((if big then 1.4 else 0.6) * closeness, if big then 5 else 2)

	local rumble = Instance.new("Sound")
	rumble.SoundId = "rbxasset://sounds/Rocket shot.wav"
	rumble.PlaybackSpeed = if big then 0.35 else 0.5
	rumble.Volume = (if big then 1.2 else 0.7) * closeness
	rumble.Parent = SoundService
	rumble:Play()
	Debris:AddItem(rumble, 6)

	-- Fire and ash shooting out of the crater.
	local emitterPart = Instance.new("Part")
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(30, 1, 30)
	emitterPart.Position = volcanoTop
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 60, 10))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 30) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(1.5, 3)
	fire.Speed = NumberRange.new(60, if big then 170 else 110)
	fire.SpreadAngle = Vector2.new(22, 22)
	fire.Acceleration = Vector3.new(0, -40, 0)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Rate = if big then 90 else 45
	fire.Parent = emitterPart
	local ash = fire:Clone()
	ash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ash.LightEmission = 0
	ash.Color = ColorSequence.new(Color3.fromRGB(70, 62, 60))
	ash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 20), NumberSequenceKeypoint.new(1, 70) })
	ash.Lifetime = NumberRange.new(4, 7)
	ash.Speed = NumberRange.new(30, 70)
	ash.Acceleration = Vector3.new(0, 6, 0)
	ash.Rate = if big then 30 else 14
	ash.Parent = emitterPart
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 140, 50)
	flash.Range = 60
	flash.Brightness = if big then 12 else 6
	flash.Parent = emitterPart
	emitterPart.Parent = workspace
	task.delay(if big then 7 else 3.5, function()
		fire.Enabled = false
		ash.Enabled = false
		flash.Enabled = false
	end)
	Debris:AddItem(emitterPart, if big then 15 else 11)
end

-- The server can't move a character it doesn't simulate, so it asks us.
-- For a quarter of a second the character is carried by a LinearVelocity
-- (the Humanoid would otherwise brake instantly), then it lands on its feet.
local KNOCKBACK_TIME = 0.25

function Effects.knockback(velocity: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or typeof(velocity) ~= "Vector3" then
		return
	end
	if velocity.Magnitude > 200 then
		velocity = velocity.Unit * 200
	end
	local old = rootPart:FindFirstChild("KnockbackPush")
	if old then
		old:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackPush"
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	push.ForceLimitsEnabled = false
	push.Parent = attachment

	humanoid.PlatformStand = true
	attachment.Parent = rootPart
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, math.clamp(velocity.Y, 0, 40), velocity.Z)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	task.delay(KNOCKBACK_TIME, function()
		if attachment.Parent == nil then
			return -- replaced by a newer knockback
		end
		attachment:Destroy()
		if humanoid.Parent and rootPart.Parent then
			local current = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity = Vector3.new(current.X * 0.2, current.Y, current.Z * 0.2)
			rootPart.AssemblyAngularVelocity = Vector3.zero
			humanoid.PlatformStand = false
			if humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Living dinosaurs: breathing, looking around, babies wandering
---------------------------------------------------------------------------
-- Pen dinosaurs are anchored models placed by the server. Each client moves
-- the ones near its camera a little every frame; nothing is sent over the
-- network and the server's positions never change.

local penDinos: { [Model]: { home: CFrame, seed: number } } = {}
local ANIMATE_DISTANCE = 140

local function startPenDinos()
	local function add(model: Instance)
		if model:IsA("Model") and model.PrimaryPart and not penDinos[model] then
			penDinos[model] = { home = model:GetPivot(), seed = math.random() * 100 }
		end
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.PenDino):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.PenDino):Connect(function(model)
		penDinos[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Config.Tags.PenDino) do
		add(model)
	end

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local cameraPosition = camera.CFrame.Position
		local now = os.clock()
		for model, info in penDinos do
			if not model.Parent then
				penDinos[model] = nil
				continue
			end
			if (info.home.Position - cameraPosition).Magnitude > ANIMATE_DISTANCE then
				continue
			end
			local t = now + info.seed
			local stage = model:GetAttribute("Stage") or 3
			local offset
			if stage == 1 then
				-- Babies trot around their spot in a lazy figure of eight and hop.
				local x, z = math.sin(t * 0.7) * 2.6, math.sin(t * 1.4) * 1.3
				local heading = math.atan2(-math.cos(t * 0.7) * 0.7 * 2.6, -math.cos(t * 1.4) * 1.4 * 1.3)
				local hop = math.abs(math.sin(t * 5)) * 0.35
				offset = CFrame.new(x, hop, z) * CFrame.Angles(0, heading, 0)
			else
				-- Bigger ones breathe, sway and look around.
				local breathe = math.sin(t * 1.6) * 0.07
				offset = CFrame.new(0, breathe + 0.07, 0)
					* CFrame.Angles(math.sin(t * 1.6) * 0.025, math.sin(t * 0.45) * 0.35, math.sin(t * 0.9) * 0.02)
			end
			model:PivotTo(info.home * offset)
		end
	end)
end

---------------------------------------------------------------------------
-- Sounds (all from Roblox's built-in sound folder, so they always load)
---------------------------------------------------------------------------

local SOUNDS = {
	grab = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.3 },
	hatch = { id = "rbxasset://sounds/victory.wav", volume = 0.5, speed = 1.15 },
	coin = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.8 },
	error = { id = "rbxasset://sounds/bass.wav", volume = 0.5, speed = 0.8 },
	swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.5, speed = 1 },
	hurt = { id = "rbxasset://sounds/collide.wav", volume = 0.8, speed = 0.9 },
	ability = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.6, speed = 0.8 },
	success = { id = "rbxasset://sounds/switch.wav", volume = 0.5, speed = 1.2 },
}
local soundCache: { [string]: Sound } = {}

function Effects.sound(name: string)
	local info = SOUNDS[name]
	if not info then
		return
	end
	local sound = soundCache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Fx_" .. name
		sound.SoundId = info.id
		sound.Volume = info.volume
		sound.PlaybackSpeed = info.speed
		sound.Parent = SoundService
		soundCache[name] = sound
	end
	sound:Play()
end

-- Picks a sound for a server notification.
function Effects.notifySound(message: string, kind: string?)
	if string.find(message, "hatched", 1, true) then
		Effects.sound("hatch")
	elseif string.find(message, "Got a", 1, true) or string.find(message, "Egg placed", 1, true) then
		Effects.sound("grab")
	elseif kind == "coin" then
		Effects.sound("coin")
	elseif kind == "error" then
		Effects.sound("error")
	elseif kind == "success" then
		Effects.sound("success")
	end
end

function Effects.start()
	startPenDinos()
	startRainbow()
	startNestTimers()
	startEggFlights()
	startCameraShake()
end

return Effects
