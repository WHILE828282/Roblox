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
local TweenService = game:GetService("TweenService")

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
		tint = a.tint:Lerp(b.tint, alpha),
	}
end

local function ensure(className: string): any
	local found = Lighting:FindFirstChildOfClass(className)
	if not found then
		found = Instance.new(className)
		found.Parent = Lighting
	end
	return found
end

-- Soft sun, no blinding glare, gentle bloom (values in Config.Look).
local function applyLook()
	Lighting.ExposureCompensation = Config.Look.Exposure
	local bloom = ensure("BloomEffect")
	bloom.Intensity = Config.Look.BloomIntensity
	bloom.Threshold = Config.Look.BloomThreshold
	bloom.Size = Config.Look.BloomSize
	local atmosphere = ensure("Atmosphere")
	atmosphere.Glare = 0
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = 0.03
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.SunAngularSize = 8
	end
end

-- Bubbles drifting up around the camera while you are under water.
local function makeBubbles(): ParticleEmitter
	local holder = Instance.new("Part")
	holder.Name = "BubbleHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(60, 1, 60)
	holder.Parent = workspace.CurrentCamera
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	bubbles.LightEmission = 0.3
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.45) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(3, 5)
	bubbles.Speed = NumberRange.new(3, 6)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(15, 15)
	bubbles.Rate = 0
	bubbles.Parent = holder
	return bubbles
end

local function startDepth()
	applyLook()
	local atmosphere = ensure("Atmosphere")
	local tint = ensure("ColorCorrectionEffect")
	local bubbles = makeBubbles()
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
		tint.TintColor = look.tint
		local holder = bubbles.Parent :: BasePart
		holder.CFrame = CFrame.new(camera.CFrame.Position - Vector3.new(0, 18, 0))
		bubbles.Rate = if current > 0.3 then 12 + current * 6 else 0
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

local function onTagged(tag: string, added: (Model) -> (() -> ())?)
	local cleanups: { [Instance]: () -> () } = {}
	local function add(instance: Instance)
		if instance:IsA("Model") and instance.PrimaryPart and not cleanups[instance] then
			cleanups[instance] = added(instance) or function() end
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		task.defer(add, instance) -- wait until the server finished placing it
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		local cleanup = cleanups[instance]
		cleanups[instance] = nil
		if cleanup then
			cleanup()
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
end

-- A sleeping guardian breathes (slowly grows and shrinks) and its "Z z z" floats.
local function breathe(model: Model)
	local scale = model:GetScale()
	local value = Instance.new("NumberValue")
	value.Value = 1
	local connection = value.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(scale * v)
		end
	end)
	local tween = TweenService:Create(value, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Value = 1.05 })
	tween:Play()
	local gui = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Mood")
	local floatTween
	if gui and gui:IsA("BillboardGui") then
		local base = gui.StudsOffset
		local offset = Instance.new("Vector3Value")
		offset.Value = base
		offset.Changed:Connect(function(v)
			gui.StudsOffset = v
		end)
		floatTween = TweenService:Create(offset, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Value = base + Vector3.new(0, 1.5, 0) })
		floatTween:Play()
		floatTween.Destroying:Connect(function()
			gui.StudsOffset = base
		end)
	end
	return function()
		tween:Cancel()
		connection:Disconnect()
		value:Destroy()
		if floatTween then
			floatTween:Cancel()
			floatTween:Destroy()
		end
		if model.Parent then
			model:ScaleTo(scale)
		end
	end
end

-- An awake guardian glows red.
local function watchGuard(model: Model)
	local function update()
		local awake = model:GetAttribute("State") == "wake" or model:GetAttribute("State") == "chase"
		local glow = model:FindFirstChild("AngryGlow")
		if awake and not glow then
			local highlight = Instance.new("Highlight")
			highlight.Name = "AngryGlow"
			highlight.FillColor = Color3.fromRGB(255, 40, 50)
			highlight.FillTransparency = 0.75
			highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = model
		elseif not awake and glow then
			glow:Destroy()
		end
	end
	local connection = model:GetAttributeChangedSignal("State"):Connect(update)
	update()
	return function()
		connection:Disconnect()
	end
end

-- Aquarium creatures swim from point to point around their spot.
local function swim(model: Model)
	local home = model:GetPivot()
	local value = Instance.new("CFrameValue")
	value.Value = home
	local connection = value.Changed:Connect(function(v)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local alive = true
	task.spawn(function()
		local random = Random.new()
		local position = home.Position
		while alive and model.Parent do
			local goal = home.Position + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-1.2, 1.2), random:NextNumber(-1.5, 1.5))
			local direction = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
			local target = if direction.Magnitude > 0.2 then CFrame.lookAt(goal, goal + direction) else CFrame.new(goal) * home.Rotation
			local time = (goal - position).Magnitude / random:NextNumber(1.2, 2.2) + 0.4
			local tween = TweenService:Create(value, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = target })
			tween:Play()
			tween.Completed:Wait()
			position = goal
			task.wait(random:NextNumber(0.2, 1.2))
		end
	end)
	return function()
		alive = false
		connection:Disconnect()
		value:Destroy()
	end
end

-- Treadmill belts scroll while someone trains on them.
local function startBelts()
	local belts: { [BasePart]: Texture } = {}
	local function add(belt: Instance)
		local texture = belt:FindFirstChildOfClass("Texture")
		if belt:IsA("BasePart") and texture then
			belts[belt] = texture
		end
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Treadmill):Connect(add)
	for _, belt in CollectionService:GetTagged(Config.Tags.Treadmill) do
		add(belt)
	end
	RunService.RenderStepped:Connect(function(dt)
		for belt, texture in belts do
			if not belt.Parent then
				belts[belt] = nil
			elseif belt:GetAttribute("Active") then
				texture.OffsetStudsV = (texture.OffsetStudsV - dt * 9) % texture.StudsPerTileV
			end
		end
	end)
end

local function startLife()
	onTagged(Config.Tags.Sleeper, breathe)
	onTagged(Config.Tags.Guard, watchGuard)
	onTagged(Config.Tags.Creature, swim)
	startBelts()
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
		-- Jumping is the only way off the treadmill.
		humanoid.Jumping:Connect(function(active)
			if active and character:GetAttribute("Training") then
				Effects.leaveTreadmill()
			end
		end)
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

local lastLeave = 0
function Effects.leaveTreadmill()
	if os.clock() - lastLeave > 0.4 then
		lastLeave = os.clock()
		ReplicatedStorage.Remotes.LeaveTreadmill:FireServer()
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
