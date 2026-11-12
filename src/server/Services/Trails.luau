-- Trails.luau
-- The Trail Shop: glowing trails behind your character, bought with coins.
-- The equipped trail multiplies how fast the treadmill trains your Speed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Trails = {}

local actionLimiter = RateLimiter.new(Config.ActionCooldown)

local PARTICLES = {
	bubbles = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 14, size = 0.5, rise = 3 },
	stars = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 10, size = 0.9, rise = 0 },
	sparks = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 26, size = 0.6, rise = 0 },
	fire = { texture = "rbxasset://textures/particles/fire_main.dds", rate = 22, size = 1.4, rise = 2 },
}

-- Puts the player's equipped trail on their character (or removes it).
local function apply(player: Player)
	local data = PlayerData.get(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not rootPart then
		return
	end
	local old = rootPart:FindFirstChild("TrailFx")
	if old then
		old:Destroy()
	end
	local info = data.Trail and Sea.TrailById[data.Trail]
	if not info then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "TrailFx"
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.6, 0.5)
	top.Parent = rootPart
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -2.2, 0.5)
	bottom.Parent = rootPart
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(info.colors[1], info.colors[2])
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Lifetime = 0.5 + info.multiplier * 0.06
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = holder
	local particle = info.particle and PARTICLES[info.particle]
	if particle then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = particle.texture
		emitter.Color = ColorSequence.new(info.colors[1], info.colors[2])
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, particle.size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, particle.rise, 0)
		emitter.Rate = particle.rate
		emitter.Parent = bottom
	end
	-- Remove the attachments together with the effect.
	holder.Destroying:Connect(function()
		top:Destroy()
		bottom:Destroy()
	end)
	holder.Parent = rootPart
end

local function onBuy(player: Player, trailId: any)
	local info = type(trailId) == "string" and Sea.TrailById[trailId]
	local data = PlayerData.get(player)
	if not info or not data or not actionLimiter:check(player) or table.find(data.Trails, trailId) then
		return
	end
	if data.Money < info.price then
		PlayerData.notify(player, "Not enough money! You need " .. Format.money(info.price), "error")
		return
	end
	data.Money -= info.price
	table.insert(data.Trails, trailId)
	data.Trail = trailId
	apply(player)
	PlayerData.notify(player, info.name .. " trail unlocked! Treadmill x" .. info.multiplier, "success")
	PlayerData.changed(player)
end

local function onEquip(player: Player, trailId: any)
	local data = PlayerData.get(player)
	if not data or not actionLimiter:check(player) then
		return
	end
	if trailId == nil or trailId == data.Trail then
		data.Trail = nil -- tap the equipped trail again to take it off
	elseif type(trailId) == "string" and table.find(data.Trails, trailId) then
		data.Trail = trailId
	else
		return
	end
	apply(player)
	PlayerData.changed(player)
end

function Trails.start()
	Remotes.get("BuyTrail").OnServerEvent:Connect(onBuy)
	Remotes.get("EquipTrail").OnServerEvent:Connect(onEquip)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			apply(player)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	PlayerData.ProfileLoaded:Connect(apply)

	-- The stand on the pier opens the Trails window.
	local openPanel = Remotes.get("OpenPanel")
	for _, stand in CollectionService:GetTagged(Config.Tags.TrailShop) do
		if stand:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Open"
			prompt.ObjectText = "Trail Shop"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.Parent = stand
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(300, 70)
			gui.StudsOffset = Vector3.new(0, 14, 0)
			gui.MaxDistance = 200
			gui.Parent = stand
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.fromRGB(255, 230, 90)
			label.TextStrokeTransparency = 0
			label.Text = "TRAIL SHOP"
			label.Parent = gui
			prompt.Triggered:Connect(function(player)
				openPanel:FireClient(player, "Trails")
			end)
		end
	end
end

return Trails
