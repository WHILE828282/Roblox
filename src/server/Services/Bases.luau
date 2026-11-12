-- Bases.luau
-- Every player owns a base on the pier with:
--   * 4 incubators where stolen eggs hatch
--   * a glass aquarium where hatched creatures live and earn money
--   * a green plate that collects the earned money when you step on it
--   * a treadmill that trains your Speed (and a button to upgrade it)
--   * a water shield (Lock Base) that keeps thieves out for a while
-- The base furniture is built here from the BasePlot marker of the map.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Format = require(ReplicatedStorage.Shared.Format)
local CreatureModel = require(ReplicatedStorage.Shared.CreatureModel)
local PlayerData = require(script.Parent.PlayerData)
local Movement = require(script.Parent.Parent.Lib.Movement)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Bases = {}

-- onSteal(thief, creatureId) -> boolean: give a stolen egg to the thief (set by Eggs).
Bases.hooks = {}

local bases = {}
local playerBase: { [Player]: any } = {}
local knockbackRemote = Remotes.get("Knockback")
local actionLimiter = RateLimiter.new(Config.ActionCooldown)

local root = Instance.new("Folder")
root.Name = "Bases"
root.Parent = workspace

-- Where things stand inside a base (local to the base frame; -Z is the entrance).
local TREADMILL = { center = Vector3.new(13, 0, 6), half = Vector3.new(3.5, 0, 6) }
local PLATE = { center = Vector3.new(0, 0, -11), half = Vector3.new(4.5, 0, 4.5) }
local AQUARIUM = { center = Vector3.new(-6, 5.2, 12), size = Vector3.new(24, 9, 9) }

local function now(): number
	return os.time()
end

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	local props = {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for key, value in extra or {} do
		props[key] = value
	end
	return make("Part", props, parent)
end

local function billboard(parent: Instance, size: UDim2, offset: number, color: Color3, maxDistance: number): TextLabel
	local gui = make("BillboardGui", { Name = "Label", Size = size, StudsOffset = Vector3.new(0, offset, 0), MaxDistance = maxDistance }, parent)
	return make("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		Text = "",
	}, gui)
end

---------------------------------------------------------------------------
-- Queries used by other services
---------------------------------------------------------------------------

function Bases.getBase(player: Player)
	return playerBase[player]
end

local function inBase(base, position: Vector3): boolean
	local localPosition = base.frame:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= Config.BaseHalfWidth and math.abs(localPosition.Z) <= Config.BaseHalfDepth
end

-- True if `position` is inside the player's own base.
function Bases.isHome(player: Player, position: Vector3): boolean
	local base = playerBase[player]
	return base ~= nil and inBase(base, position)
end

-- World position of the entrance of the player's base (for the guide beam).
function Bases.entrance(player: Player): Vector3?
	local base = playerBase[player]
	return base and (base.frame * CFrame.new(0, 0.3, -Config.BaseHalfDepth)).Position
end

function Bases.isLocked(player: Player): boolean
	local base = playerBase[player]
	return base ~= nil and (base.lockedUntil or 0) > now()
end

function Bases.income(player: Player): number
	local data = PlayerData.get(player)
	local total = 0
	for _, entry in (data and data.Creatures or {}) do
		total += Sea.Creatures[entry.c].income
	end
	return total
end

function Bases.freeIncubator(player: Player): number?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	for slot = 1, Config.Incubators do
		local used = false
		for _, egg in data.Eggs do
			if egg.slot == slot then
				used = true
			end
		end
		if not used then
			return slot
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function updateSign(base)
	local owner = base.owner
	if owner then
		local text = owner.DisplayName .. "\n" .. Format.money(Bases.income(owner)) .. "/s"
		if (base.lockedUntil or 0) > now() then
			text ..= "  [LOCKED]"
		end
		base.sign.Text = text
		local data = PlayerData.get(owner)
		base.plateLabel.Text = if data and data.Pending >= 1 then "COLLECT\n" .. Format.money(data.Pending) else "COLLECT"
		local cost = data and Config.treadmillCost(data.Treadmill)
		base.treadmillPrompt.ObjectText = if cost then "Level " .. (data.Treadmill + 1) .. " - " .. Format.money(cost) else "MAX LEVEL"
	else
		base.sign.Text = "Free Base"
		base.plateLabel.Text = ""
	end
end

local function onStealTriggered(owner: Player, eggId: number, thief: Player, startedAt: { [Player]: number })
	local started = startedAt[thief]
	if thief == owner or not started or os.clock() - started < Config.StealHoldTime - 0.3 then
		return
	end
	if Bases.isLocked(owner) then
		PlayerData.notify(thief, "This base is locked!", "error")
		return
	end
	local data = PlayerData.get(owner)
	local thiefRoot = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	local base = playerBase[owner]
	if not data or not thiefRoot or not base or not inBase(base, thiefRoot.Position) then
		return
	end
	for index, egg in data.Eggs do
		if egg.id == eggId then
			if Bases.hooks.onSteal and Bases.hooks.onSteal(thief, egg.c) then
				table.remove(data.Eggs, index)
				PlayerData.notify(owner, thief.DisplayName .. " stole your " .. Sea.Creatures[egg.c].name .. " egg!", "error")
				Bases.refresh(owner)
			end
			return
		end
	end
end

-- Shows the eggs and creatures of the owner. Models are only created or
-- removed when something really changed.
local function refreshDisplay(player: Player)
	local base = playerBase[player]
	local data = PlayerData.get(player)
	if not base or not data then
		return
	end
	local seen = {}
	for _, egg in data.Eggs do
		seen[egg.id] = true
		if not base.eggModels[egg.id] then
			local model = CreatureModel.buildEgg(egg.c)
			model.Name = "NestEgg"
			model:PivotTo(base.incubators[egg.slot] * CFrame.new(0, 3.2, 0))
			model:SetAttribute("HatchAt", egg.hatchAt)
			model:SetAttribute("OwnerId", player.UserId)
			local label = billboard(model.PrimaryPart, UDim2.fromOffset(150, 44), 3.2, Sea.rarityOf(egg.c).color, 70)
			label.Parent.Name = "Timer"
			local prompt = make("ProximityPrompt", {
				ActionText = "Steal",
				ObjectText = Sea.Creatures[egg.c].name .. " Egg",
				HoldDuration = Config.StealHoldTime,
				MaxActivationDistance = 9,
				RequiresLineOfSight = false,
			}, model.PrimaryPart)
			local startedAt = {}
			prompt.PromptButtonHoldBegan:Connect(function(thief)
				startedAt[thief] = os.clock()
			end)
			prompt.Triggered:Connect(function(thief)
				onStealTriggered(player, egg.id, thief, startedAt)
			end)
			CollectionService:AddTag(model, Config.Tags.NestEgg)
			model.Parent = base.folder
			base.eggModels[egg.id] = model
		end
	end
	for id, model in base.eggModels do
		if not seen[id] then
			model:Destroy()
			base.eggModels[id] = nil
		end
	end

	seen = {}
	for _, entry in data.Creatures do
		seen[entry.id] = true
		if not base.creatureModels[entry.id] then
			-- A random spot inside the aquarium; the client makes it swim around.
			local random = Random.new(entry.id * 7919)
			local half = AQUARIUM.size / 2 - Vector3.new(2.5, 2, 2.5)
			local spot = AQUARIUM.center + Vector3.new(random:NextNumber(-half.X, half.X), random:NextNumber(-half.Y, half.Y), random:NextNumber(-half.Z, half.Z))
			local model = CreatureModel.build(entry.c, 0.75)
			model:PivotTo(base.frame * CFrame.new(spot) * CFrame.Angles(0, math.rad(90), 0))
			CollectionService:AddTag(model, Config.Tags.Creature)
			model.Parent = base.folder
			base.creatureModels[entry.id] = model
		end
	end
	for id, model in base.creatureModels do
		if not seen[id] then
			model:Destroy()
			base.creatureModels[id] = nil
		end
	end
	updateSign(base)
end

function Bases.refresh(player: Player)
	refreshDisplay(player)
	PlayerData.changed(player)
end

---------------------------------------------------------------------------
-- Eggs and creatures
---------------------------------------------------------------------------

-- Puts a delivered egg into a free incubator. Returns false if all are busy.
function Bases.addEgg(player: Player, creatureId: string): boolean
	local data = PlayerData.get(player)
	local slot = Bases.freeIncubator(player)
	if not data or not slot then
		return false
	end
	table.insert(data.Eggs, { id = data.NextId, c = creatureId, hatchAt = now() + Sea.rarityOf(creatureId).hatch, slot = slot })
	data.NextId += 1
	Bases.refresh(player)
	return true
end

local function hatchReady(player: Player, data): boolean
	local hatched = false
	for index = #data.Eggs, 1, -1 do
		local egg = data.Eggs[index]
		if egg.hatchAt <= now() and #data.Creatures < Config.aquariumSize(data.Aquarium) then
			table.remove(data.Eggs, index)
			table.insert(data.Creatures, { id = data.NextId, c = egg.c })
			data.NextId += 1
			local creature = Sea.Creatures[egg.c]
			local isNew = not data.Index[egg.c]
			data.Index[egg.c] = true
			PlayerData.notify(player, (if isNew then "NEW! " else "") .. "Hatched: " .. creature.rarity .. " " .. creature.name .. "!", "success")
			hatched = true
		end
	end
	return hatched
end

local function onSell(player: Player, creatureEntryId: any)
	if not actionLimiter:check(player) or type(creatureEntryId) ~= "number" then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	for index, entry in data.Creatures do
		if entry.id == creatureEntryId then
			table.remove(data.Creatures, index)
			local price = Sea.Creatures[entry.c].income * Config.SellSeconds
			data.Money += price
			PlayerData.notify(player, "Sold " .. Sea.Creatures[entry.c].name .. " for " .. Format.money(price), "coin")
			Bases.refresh(player)
			return
		end
	end
end

local function buyUpgrade(player: Player, field: string, cost: number?, label: string)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	if not cost then
		PlayerData.notify(player, "Already at the maximum level!", "info")
	elseif data.Money < cost then
		PlayerData.notify(player, "Not enough money! You need " .. Format.money(cost), "error")
	else
		data.Money -= cost
		data[field] += 1
		PlayerData.notify(player, label .. " upgraded to level " .. data[field] .. "!", "success")
		Bases.refresh(player)
	end
end

local function onUpgradeTreadmill(player: Player)
	local data = PlayerData.get(player)
	if data and actionLimiter:check(player) then
		buyUpgrade(player, "Treadmill", Config.treadmillCost(data.Treadmill), "Treadmill")
	end
end

local function onUpgradeAquarium(player: Player)
	local data = PlayerData.get(player)
	if data and actionLimiter:check(player) then
		buyUpgrade(player, "Aquarium", Config.aquariumCost(data.Aquarium), "Aquarium")
	end
end

---------------------------------------------------------------------------
-- Lock (water shield)
---------------------------------------------------------------------------

local function onLock(player: Player)
	local base = playerBase[player]
	if not base or not actionLimiter:check(player) then
		return
	end
	local t = now()
	if (base.lockCooldownUntil or 0) > t then
		PlayerData.notify(player, "Shield is recharging: " .. Format.duration(base.lockCooldownUntil - t), "error")
		return
	end
	base.lockedUntil = t + Config.LockDuration
	base.lockCooldownUntil = t + Config.LockCooldown
	base.shield.Transparency = 0.45
	base.shieldFx.Enabled = true
	updateSign(base)
	PlayerData.notify(player, "Water shield is up for " .. Config.LockDuration .. " seconds!", "success")
	PlayerData.changed(player)
	task.delay(Config.LockDuration, function()
		if (base.lockedUntil or 0) <= now() then
			base.shield.Transparency = 1
			base.shieldFx.Enabled = false
			updateSign(base)
		end
	end)
end

-- While the shield is up, anyone else inside the base is pushed out through the entrance.
local function shieldTick()
	for _, base in bases do
		if base.owner and (base.lockedUntil or 0) > now() then
			for _, other in Players:GetPlayers() do
				local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if other ~= base.owner and otherRoot and inBase(base, otherRoot.Position) then
					knockbackRemote:FireClient(other, base.frame.LookVector * 70 + Vector3.new(0, 25, 0))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Building a base, assigning it, game loops
---------------------------------------------------------------------------

local function setupBase(marker: BasePart)
	local center = marker.Position
	local frame = CFrame.lookAt(center, Vector3.new(0, center.Y, center.Z)) -- -Z looks at the middle of the pier
	local index = marker:GetAttribute("BaseIndex") or (#bases + 1)
	local static = make("Folder", { Name = "Base" .. index .. "Static" }, root)
	local folder = make("Folder", { Name = "Base" .. index }, root)
	local sandstone = Color3.fromRGB(240, 226, 190)
	local teal = Color3.fromRGB(60, 190, 200)
	local w, d = Config.BaseHalfWidth, Config.BaseHalfDepth

	-- Low walls on three sides, with corner posts.
	block(static, "Wall", Vector3.new(w * 2, 4, 1.5), frame * CFrame.new(0, 2, d), sandstone, Enum.Material.Sandstone)
	for _, side in { -1, 1 } do
		block(static, "Wall", Vector3.new(1.5, 4, d * 2), frame * CFrame.new(side * w, 2, 0), sandstone, Enum.Material.Sandstone)
		for _, z in { -d, d } do
			local post = block(static, "Post", Vector3.new(3, 8, 3), frame * CFrame.new(side * w, 4, z), teal, Enum.Material.Marble)
			local lamp = block(static, "Lamp", Vector3.new(2, 2, 2), post.CFrame * CFrame.new(0, 5, 0), Color3.fromRGB(255, 240, 170), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
			make("PointLight", { Color = lamp.Color, Range = 18, Brightness = 1.2 }, lamp)
		end
	end

	-- Aquarium: a glass tank full of water on a stone stand.
	local tank = frame * CFrame.new(AQUARIUM.center)
	block(static, "AquariumStand", Vector3.new(AQUARIUM.size.X + 1.5, 0.9, AQUARIUM.size.Z + 1.5), frame * CFrame.new(AQUARIUM.center.X, 0.45, AQUARIUM.center.Z), teal, Enum.Material.Marble)
	block(static, "AquariumGlass", AQUARIUM.size, tank, Color3.fromRGB(190, 240, 255), Enum.Material.Glass, { Transparency = 0.72, CanCollide = true })
	local water = block(static, "AquariumWater", AQUARIUM.size - Vector3.new(0.4, 0.8, 0.4), tank * CFrame.new(0, -0.2, 0), Color3.fromRGB(70, 190, 230), Enum.Material.SmoothPlastic, { Transparency = 0.6, CanCollide = false, CanQuery = false, CastShadow = false })
	make("PointLight", { Color = Color3.fromRGB(120, 220, 255), Range = 26, Brightness = 1.4 }, water)
	local bubbles = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(230, 250, 255)),
		Size = NumberSequence.new(0.35),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(2, 3),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 8,
	}, water)
	bubbles.Name = "Bubbles"
	block(static, "AquariumLid", Vector3.new(AQUARIUM.size.X + 0.6, 0.6, AQUARIUM.size.Z + 0.6), tank * CFrame.new(0, AQUARIUM.size.Y / 2 + 0.3, 0), teal, Enum.Material.Marble)

	-- Incubators: glowing pedestals.
	local incubators = {}
	for slot = 1, Config.Incubators do
		local spot = frame * CFrame.new(-16 + (slot - 1) * 6.2, 0, 0)
		table.insert(incubators, spot)
		block(static, "Incubator", Vector3.new(1.6, 4, 4), spot * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 100, 140), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		local ring = block(static, "IncubatorGlow", Vector3.new(0.3, 4.4, 4.4), spot * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 255, 220), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		make("PointLight", { Color = ring.Color, Range = 10, Brightness = 0.8 }, ring)
	end

	-- Treadmill with its upgrade button.
	local belt = block(static, "Treadmill", Vector3.new(TREADMILL.half.X * 2, 0.8, TREADMILL.half.Z * 2), frame * CFrame.new(TREADMILL.center + Vector3.new(0, 0.4, 0)), Color3.fromRGB(40, 44, 60), Enum.Material.Rubber)
	for i = -2, 2 do
		block(static, "BeltStripe", Vector3.new(TREADMILL.half.X * 2 - 1, 0.1, 0.5), belt.CFrame * CFrame.new(0, 0.42, i * 2.3), Color3.fromRGB(255, 220, 70), Enum.Material.Neon, { CanCollide = false })
	end
	for _, side in { -1, 1 } do
		block(static, "TreadmillRail", Vector3.new(0.5, 3.6, 0.5), belt.CFrame * CFrame.new(side * TREADMILL.half.X, 2, TREADMILL.half.Z - 0.5), Color3.fromRGB(230, 60, 80), Enum.Material.Metal)
	end
	local console = block(static, "TreadmillConsole", Vector3.new(TREADMILL.half.X * 2 + 0.5, 1.4, 0.6), belt.CFrame * CFrame.new(0, 3.6, TREADMILL.half.Z - 0.5), Color3.fromRGB(230, 60, 80), Enum.Material.Metal)
	billboard(console, UDim2.fromOffset(170, 40), 1.6, Color3.fromRGB(255, 230, 90), 60).Text = "TREADMILL\nStand here to train Speed"
	local button = block(static, "UpgradeButton", Vector3.new(1, 3, 3), frame * CFrame.new(TREADMILL.center.X, 1.2, TREADMILL.center.Z - TREADMILL.half.Z - 3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 220, 100), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	local treadmillPrompt = make("ProximityPrompt", { ActionText = "Upgrade Treadmill", ObjectText = "", HoldDuration = 0.3, MaxActivationDistance = 9, RequiresLineOfSight = false }, button)

	-- Collect plate.
	local plate = block(static, "CollectPlate", Vector3.new(PLATE.half.X * 2, 0.4, PLATE.half.Z * 2), frame * CFrame.new(PLATE.center + Vector3.new(0, 0.2, 0)), Color3.fromRGB(70, 230, 110), Enum.Material.Neon)
	local plateLabel = billboard(plate, UDim2.fromOffset(170, 56), 3.2, Color3.fromRGB(150, 255, 170), 80)

	-- Water shield at the entrance (visible only while the base is locked).
	local shield = block(static, "Shield", Vector3.new(w * 2, 16, 1.2), frame * CFrame.new(0, 8, -d), Color3.fromRGB(70, 180, 255), Enum.Material.ForceField, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local shieldFx = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(160, 230, 255)),
		Size = NumberSequence.new(0.8, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(4, 8),
		Rate = 60,
		Enabled = false,
	}, shield)

	-- Owner sign above the entrance.
	local anchor = block(static, "Sign", Vector3.one, frame * CFrame.new(0, 13, -d), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	local sign = billboard(anchor, UDim2.fromOffset(260, 80), 0, Color3.new(1, 1, 1), 220)

	local base = {
		frame = frame,
		marker = marker,
		owner = nil,
		folder = folder,
		incubators = incubators,
		eggModels = {},
		creatureModels = {},
		sign = sign,
		plateLabel = plateLabel,
		treadmillPrompt = treadmillPrompt,
		shield = shield,
		shieldFx = shieldFx,
		index = index,
	}
	treadmillPrompt.Triggered:Connect(function(player)
		if base.owner == player then
			onUpgradeTreadmill(player)
		else
			PlayerData.notify(player, "This is not your treadmill.", "error")
		end
	end)
	table.insert(bases, base)
	table.sort(bases, function(a, b)
		return a.index < b.index
	end)
	updateSign(base)
end

local function spawnAtBase(player: Player, character: Model)
	local base = playerBase[player]
	local characterRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not base or not characterRoot then
		return
	end
	task.wait()
	character:PivotTo(base.frame * CFrame.new(0, 4, -Config.BaseHalfDepth + 4) * CFrame.Angles(0, math.rad(180), 0))
	Movement.apply(player)
end

local function assignBase(player: Player)
	for _, base in bases do
		if not base.owner then
			base.owner = player
			playerBase[player] = base
			base.marker:SetAttribute("OwnerId", player.UserId)
			refreshDisplay(player)
			if player.Character then
				task.spawn(spawnAtBase, player, player.Character)
			end
			return
		end
	end
	warn("[Bases] No free base for " .. player.Name .. ". Set the server size to " .. Config.MaxPlayers .. ".")
end

local function releaseBase(player: Player)
	local base = playerBase[player]
	playerBase[player] = nil
	if base then
		base.owner = nil
		base.folder:ClearAllChildren()
		base.eggModels, base.creatureModels = {}, {}
		base.marker:SetAttribute("OwnerId", nil)
		base.lockedUntil, base.lockCooldownUntil = nil, nil
		base.shield.Transparency = 1
		base.shieldFx.Enabled = false
		updateSign(base)
	end
end

-- Every second: income, hatching and the collect plate.
local function economyTick()
	for player, data in PlayerData.all() do
		local base = playerBase[player]
		if base then
			data.Pending += Bases.income(player)
			local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if characterRoot and data.Pending >= 1 then
				local at = base.frame:PointToObjectSpace(characterRoot.Position) - PLATE.center
				if math.abs(at.X) <= PLATE.half.X and math.abs(at.Z) <= PLATE.half.Z then
					local amount = math.floor(data.Pending)
					data.Money += amount
					data.Pending -= amount
					PlayerData.notify(player, "+" .. Format.money(amount), "coin")
				end
			end
			if hatchReady(player, data) then
				refreshDisplay(player)
			end
			updateSign(base)
			PlayerData.changed(player)
		end
	end
end

-- Twice a second: standing on your treadmill trains Speed.
local function treadmillTick(dt: number)
	for player, data in PlayerData.all() do
		local base = playerBase[player]
		local character = player.Character
		local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
		if base and characterRoot then
			local at = base.frame:PointToObjectSpace(characterRoot.Position) - TREADMILL.center
			local training = math.abs(at.X) <= TREADMILL.half.X and math.abs(at.Z) <= TREADMILL.half.Z and at.Y < 8
			if training and data.Speed < Config.MaxSpeed then
				local gain = Config.treadmillRate(data.Treadmill) * Sea.trailMultiplier(data.Trail) * dt
				data.Speed = math.min(Config.MaxSpeed, data.Speed + gain)
				Movement.apply(player)
			end
			if character:GetAttribute("Training") ~= training then
				character:SetAttribute("Training", training)
			end
		end
	end
end

function Bases.start()
	for _, marker in CollectionService:GetTagged(Config.Tags.BasePlot) do
		if marker:IsA("BasePart") then
			setupBase(marker)
		end
	end

	PlayerData.addStateProvider(function(player, state)
		local base = playerBase[player]
		state.income = Bases.income(player)
		state.aquariumSize = Config.aquariumSize(state.aquarium)
		state.lockedLeft = if base then math.max(0, (base.lockedUntil or 0) - now()) else 0
		state.lockCooldownLeft = if base then math.max(0, (base.lockCooldownUntil or 0) - now()) else 0
	end)

	PlayerData.ProfileLoaded:Connect(function(player)
		assignBase(player)
		Bases.refresh(player)
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawnAtBase(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(releaseBase)

	Remotes.get("SellCreature").OnServerEvent:Connect(onSell)
	Remotes.get("LockBase").OnServerEvent:Connect(onLock)
	Remotes.get("UpgradeTreadmill").OnServerEvent:Connect(onUpgradeTreadmill)
	Remotes.get("UpgradeAquarium").OnServerEvent:Connect(onUpgradeAquarium)

	task.spawn(function()
		while true do
			task.wait(1)
			economyTick()
		end
	end)
	task.spawn(function()
		while true do
			treadmillTick(task.wait(0.5))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1.5)
			shieldTick()
		end
	end)
end

return Bases
