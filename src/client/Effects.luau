-- Effects.luau
-- Purely visual client effects (no gameplay decisions):
--   * the water gets deeper, darker and more mysterious as you dive
--   * a glowing guide beam to your base while you carry an egg
--   * sleeping guardians breathe, aquarium creatures swim
--   * hatch timers, treadmill running animation, knockback, shake, sounds

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Format = require(ReplicatedStorage.Shared.Format)

local Effects = {}

local player = Players.LocalPlayer

---------------------------------------------------------------------------
-- Depth: lighting changes smoothly from the sunny pier to the black abyss
---------------------------------------------------------------------------

local SURFACE = {
	water = Color3.fromRGB(190, 225, 255),
	ambient = Color3.fromRGB(150, 150, 160),
	brightness = 2.6,
	density = 0.26,
	haze = 0.6,
	bloom = 0.35,
	tint = Color3.new(1, 1, 1),
}

local function depthLook(depth: number)
	-- depth: 0 on the pier, 1..5 in the middle of each zone.
	if depth <= 0 then
		return SURFACE
	end
	local lower = math.clamp(math.floor(depth), 0, 5)
	local upper = math.clamp(lower + 1, 1, 5)
	local alpha = depth - lower
	local function look(index: number)
		if index == 0 then
			return SURFACE
		end
		local zone = Sea.Zones[index]
		local k = index / 5
		return {
			water = zone.water,
			ambient = zone.water:Lerp(Color3.new(0, 0, 0), 0.25 + k * 0.35),
			brightness = 2 - k * 1.7,
			density = 0.42 + k * 0.22,
			haze = 1.4 + k * 1.2,
			bloom = 0.5 + k * 0.6,
			tint = zone.water:Lerp(Color3.new(1, 1, 1), 0.72 - k * 0.2),
		}
	end
	local a, b = look(lower), look(upper)
	return {
		water = a.water:Lerp(b.water, alpha),
		ambient = a.ambient:Lerp(b.ambient, alpha),
		brightness = a.brightness + (b.brightness - a.brightness) * alpha,
		density = a.density + (b.density - a.density) * alpha,
		haze = a.haze + (b.haze - a.haze) * alpha,
		bloom = a.bloom + (b.bloom - a.bloom) * alpha,
		tint = a.tint:Lerp(b.tint, alpha),
	}
end

local function startDepth()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
	local tint = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect", Lighting)
	local current = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local z = camera.Focus.Position.Z
		local target = math.clamp((z - Config.OceanStartZ) / Config.ZoneLength + 0.5, 0, 5)
		if z < Config.OceanStartZ then
			target = 0
		end
		current += (target - current) * math.min(1, dt * 2.5) -- smooth, never a hard cut
		local look = depthLook(current)
		atmosphere.Color = look.water
		atmosphere.Decay = look.water:Lerp(Color3.new(0, 0, 0), 0.5)
		atmosphere.Density = look.density
		atmosphere.Haze = look.haze
		Lighting.Ambient = look.ambient
		Lighting.OutdoorAmbient = look.ambient
		Lighting.Brightness = look.brightness
		bloom.Intensity = look.bloom
		tint.TintColor = look.tint
	end)
end

---------------------------------------------------------------------------
-- Guide beam from you to the entrance of your base while carrying an egg
---------------------------------------------------------------------------

local guide = nil

local function clearGuide()
	if guide then
		for _, instance in guide do
			instance:Destroy()
		end
		guide = nil
	end
end

function Effects.setGuide(entrance: Vector3?)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(entrance) ~= "Vector3" or not rootPart then
		clearGuide()
		return
	end
	if guide and guide[1].Parent == rootPart then
		guide[2].WorldPosition = entrance
		return
	end
	clearGuide()
	local from = Instance.new("Attachment")
	from.Name = "GuideFrom"
	from.Position = Vector3.new(0, -2.6, 0)
	from.Parent = rootPart
	local to = Instance.new("Attachment")
	to.Name = "GuideTo"
	to.Parent = workspace.Terrain
	to.WorldPosition = entrance
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Width0 = 2.4
	beam.Width1 = 2.4
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureLength = 6
	beam.TextureSpeed = 2.5
	beam.Color = ColorSequence.new(Color3.fromRGB(120, 255, 200), Color3.fromRGB(90, 200, 255))
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = rootPart
	guide = { from, to, beam }
end

---------------------------------------------------------------------------
-- Living things: sleeping guardians breathe, aquarium creatures swim
---------------------------------------------------------------------------

local function animateTagged(tag: string, motion: (number, number) -> CFrame)
	local homes: { [Model]: { home: CFrame, seed: number } } = {}
	local function add(model: Instance)
		if model:IsA("Model") and model.PrimaryPart then
			homes[model] = { home = model:GetPivot(), seed = math.random() * 100 }
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		task.defer(add, model) -- wait until the server finished placing it
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
		homes[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(tag) do
		add(model)
	end
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local now = os.clock()
		for model, info in homes do
			if not model.Parent then
				homes[model] = nil
			elseif camera and (info.home.Position - camera.CFrame.Position).Magnitude < 220 then
				model:PivotTo(info.home * motion(now + info.seed, info.seed))
			end
		end
	end)
end

local function startLife()
	-- Slow deep breathing.
	animateTagged(Config.Tags.Sleeper, function(t)
		return CFrame.new(0, math.sin(t * 1.1) * 0.5, 0) * CFrame.Angles(math.sin(t * 1.1) * 0.04, 0, math.sin(t * 0.55) * 0.03)
	end)
	-- Lazy laps inside the tank.
	animateTagged(Config.Tags.Creature, function(t, seed)
		local speed = 0.5 + (seed % 7) * 0.05
		local x, z = math.sin(t * speed) * 2.2, math.sin(t * speed * 2) * 0.9
		local heading = math.atan2(-math.cos(t * speed) * 2.2, -math.cos(t * speed * 2) * 1.8)
		return CFrame.new(x, math.sin(t * 1.3) * 0.5, z) * CFrame.Angles(0, heading, math.sin(t * 6) * 0.08)
	end)
end

local function startNestTimers()
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for _, model in CollectionService:GetTagged(Config.Tags.NestEgg) do
				local primary = model:IsA("Model") and model.PrimaryPart
				local timer = primary and primary:FindFirstChild("Timer")
				local label = timer and timer:FindFirstChild("Text")
				local hatchAt = model:GetAttribute("HatchAt")
				if label and hatchAt then
					local left = hatchAt - now
					label.Text = if left > 0 then Format.duration(left) else "Hatching!"
				end
				-- You cannot steal your own eggs: hide the prompt.
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
-- Treadmill: run on the spot while the server says you are training
---------------------------------------------------------------------------

local RUN_ANIMATION = "rbxassetid://913376220" -- Roblox's standard R15 run

local function startTreadmill()
	local track: AnimationTrack? = nil
	local function watch(character: Model)
		track = nil
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		local animator = humanoid and humanoid:WaitForChild("Animator", 10) :: Animator?
		if not animator then
			return
		end
		local function update()
			local training = character:GetAttribute("Training") == true
			if training and not track then
				local animation = Instance.new("Animation")
				animation.AnimationId = RUN_ANIMATION
				local ok, loaded = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and loaded then
					loaded.Priority = Enum.AnimationPriority.Action
					loaded.Looped = true
					track = loaded
				end
			end
			if track then
				if training and not track.IsPlaying then
					track:Play(0.2, 1, 1.4)
					Effects.sound("train")
				elseif not training and track.IsPlaying then
					track:Stop(0.2)
				end
			end
		end
		character:GetAttributeChangedSignal("Training"):Connect(update)
		update()
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

---------------------------------------------------------------------------
-- Knockback, camera shake, sounds
---------------------------------------------------------------------------

-- The server cannot move a character it does not simulate, so it asks us.
-- For a quarter of a second a LinearVelocity carries the character, then it
-- lands on its feet.
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
	task.delay(0.25, function()
		if attachment.Parent == nil then
			return
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
	Effects.shake(0.6, 0.4)
	Effects.sound("hurt")
end

local shakeUntil, shakePower = 0, 0

function Effects.shake(power: number, seconds: number)
	shakePower = math.max(power, if os.clock() < shakeUntil then shakePower else 0)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

-- Sounds from Roblox's built-in folder, so they always load.
local SOUNDS = {
	grab = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.3 },
	hatch = { id = "rbxasset://sounds/victory.wav", volume = 0.5, speed = 1.15 },
	coin = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.8 },
	error = { id = "rbxasset://sounds/bass.wav", volume = 0.5, speed = 0.8 },
	hurt = { id = "rbxasset://sounds/collide.wav", volume = 0.8, speed = 0.9 },
	dash = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.5, speed = 1.2 },
	alert = { id = "rbxasset://sounds/bass.wav", volume = 0.9, speed = 0.5 },
	success = { id = "rbxasset://sounds/switch.wav", volume = 0.5, speed = 1.2 },
	train = { id = "rbxasset://sounds/switch.wav", volume = 0.4, speed = 0.8 },
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
	if string.find(message, "Hatched", 1, true) then
		Effects.sound("hatch")
	elseif string.find(message, "Got a", 1, true) or string.find(message, "incubator!", 1, true) then
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
	startDepth()
	startLife()
	startNestTimers()
	startTreadmill()
	RunService:BindToRenderStep("SeaCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		local camera = workspace.CurrentCamera
		if left > 0 and camera then
			local strength = shakePower * math.min(left, 1)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
		end
	end)
end

return Effects
