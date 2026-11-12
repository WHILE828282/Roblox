-- Ocean.luau
-- The dive: glowing eggs in nests, the sleeping guardians and the chase.
--   * Every zone has nests with eggs; deeper zones hold rarer, heavier eggs.
--   * Grabbing an egg slows you down (rarer = heavier) and wakes the zone's
--     guardian, which chases you until you reach the pier.
--   * A sleeping guardian also wakes when an egg carrier comes close.
--   * If it catches you, the egg goes back to its nest, you are sent home
--     and guardians ignore you for a few seconds; the guardian goes back to sleep.
--   * Reaching your own base puts the egg into a free incubator.
-- Also: Dash and Drop Egg requests.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sea = require(ReplicatedStorage.Shared.Sea)
local AssetModels = require(ReplicatedStorage.Shared.AssetModels)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local Movement = require(script.Parent.Parent.Lib.Movement)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Ocean = {}

local random = Random.new()
local alertRemote = Remotes.get("Alert")
local actionLimiter = RateLimiter.new(Config.ActionCooldown)

-- nests[part] = { part, zone, model, creatureId }
local nests = {}
-- carried[player] = { creatureId, model, nest (nil for eggs stolen from players) }
local carried: { [Player]: any } = {}
-- guards[zone] = { model, home (CFrame), state = "sleep" | "wake" | "chase" | "return", target, label }
local guards = {}
local dashReadyAt: { [Player]: number } = {}
local fullWarned: { [Player]: number } = {}
local safeUntil: { [Player]: number } = {} -- guardians ignore a player who was just caught

local folder = Instance.new("Folder")
folder.Name = "Ocean"
folder.Parent = workspace

---------------------------------------------------------------------------
-- Guardians
---------------------------------------------------------------------------

local function setGuardState(guard, state: string, target: Player?)
	guard.state = state
	guard.target = target
	guard.model:SetAttribute("State", state)
	if state == "sleep" then
		guard.label.Text = "Z z z"
		guard.label.TextColor3 = Color3.fromRGB(200, 230, 255)
		CollectionService:AddTag(guard.model, Config.Tags.Sleeper)
	else
		guard.label.Text = if state == "return" then "..." else "!"
		guard.label.TextColor3 = Color3.fromRGB(255, 70, 70)
		CollectionService:RemoveTag(guard.model, Config.Tags.Sleeper)
	end
end

-- The top point of a part, also for rotated parts (nests are upright cylinders).
local function topOf(part: BasePart): Vector3
	local up = part.CFrame:VectorToObjectSpace(Vector3.yAxis)
	local size = part.Size
	local halfHeight = (math.abs(up.X) * size.X + math.abs(up.Y) * size.Y + math.abs(up.Z) * size.Z) / 2
	return part.Position + Vector3.new(0, halfHeight, 0)
end

local function isSafe(player: Player): boolean
	return (safeUntil[player] or 0) > os.clock()
end

local function guardSpeed(zone: number): number
	return Sea.Zones[zone].speed * Config.GuardSpeedFactor
end

local function wakeGuard(zone: number, thief: Player)
	local guard = guards[zone]
	if not guard or guard.state == "chase" or guard.state == "wake" or isSafe(thief) then
		return
	end
	setGuardState(guard, "wake", thief)
	alertRemote:FireClient(thief, "THE " .. string.upper(Sea.Zones[zone].guard) .. " WOKE UP! RUN TO YOUR BASE!")
	task.delay(Config.GuardWakeDelay, function()
		if guard.state == "wake" and guard.target == thief then
			setGuardState(guard, "chase", thief)
		end
	end)
end

local function calmGuards(player: Player)
	for _, guard in guards do
		if guard.target == player and guard.state ~= "sleep" then
			setGuardState(guard, "return", nil)
		end
	end
end

-- The ground under a point: the map is built by hand, so we ask it with a ray.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position: Vector3): number?
	local ignore = { folder, workspace:FindFirstChild("Bases") }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), groundParams)
	return result and result.Position.Y
end

-- Moves a guardian towards `goal` along the ground. Returns the distance left.
local function moveGuard(guard, goal: Vector3, speed: number, dt: number): number
	local position = guard.model:GetPivot().Position
	local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
	local distance = flat.Magnitude
	if distance > 0.05 then
		local step = math.min(distance, speed * dt)
		local nextPosition = position + flat.Unit * step
		-- Never leave the ocean: the pier is the safe zone.
		nextPosition = Vector3.new(nextPosition.X, nextPosition.Y, math.max(nextPosition.Z, Config.OceanStartZ + 4))
		local y = groundBelow(nextPosition) or position.Y
		local target = Vector3.new(nextPosition.X, y, nextPosition.Z)
		guard.model:PivotTo(CFrame.lookAt(target, target + flat.Unit))
	end
	return distance
end

-- The guardian caught the thief: no physics, just send them home safely.
local function caught(guard, target: Player)
	Ocean.drop(target) -- the egg goes back to its nest
	safeUntil[target] = os.clock() + Config.CaughtProtection
	local home = Bases.spawnCFrame(target)
	if home and target.Character then
		target.Character:PivotTo(home)
	end
	alertRemote:FireClient(target, "CAUGHT! The egg went back to its nest.")
	guard.model:PivotTo(guard.home)
	setGuardState(guard, "sleep", nil)
end

local function guardTick(dt: number)
	for zone, guard in guards do
		if guard.state == "sleep" then
			-- Wake up when an egg carrier comes close.
			local home = guard.home.Position
			for player in carried do
				local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if rootPart and not isSafe(player) and (rootPart.Position - home).Magnitude <= Config.GuardWakeRadius then
					wakeGuard(zone, player)
					break
				end
			end
		elseif guard.state == "chase" then
			local target: Player? = guard.target
			local targetRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if not target or not targetRoot or not carried[target] or targetRoot.Position.Z < Config.OceanStartZ then
				setGuardState(guard, "return", nil) -- the thief escaped to the pier (or lost the egg)
			else
				local distance = moveGuard(guard, targetRoot.Position, guardSpeed(zone), dt)
				if distance <= Config.GuardCatchDistance then
					caught(guard, target)
				end
			end
		elseif guard.state == "return" then
			local distance = moveGuard(guard, guard.home.Position, guardSpeed(zone) * 1.5, dt)
			if distance < 1 then
				guard.model:PivotTo(guard.home)
				setGuardState(guard, "sleep", nil)
			end
		end
	end
end

local function setupGuard(post: BasePart)
	local zone = post:GetAttribute("Zone")
	if type(zone) ~= "number" or not Sea.Zones[zone] or guards[zone] then
		return
	end
	local model = AssetModels.boss(zone)
	local height = model:GetExtentsSize().Y
	-- Sleep on the bed, facing the pier.
	local bed = topOf(post)
	local y = groundBelow(bed) or bed.Y
	local home = CFrame.lookAt(Vector3.new(bed.X, y, bed.Z), Vector3.new(bed.X, y, bed.Z - 30))
	model:PivotTo(home)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Mood"
	gui.Size = UDim2.fromOffset(200, 90)
	gui.StudsOffset = Vector3.new(0, height + 4, 0)
	gui.MaxDistance = 260
	gui.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0
	label.Parent = gui
	CollectionService:AddTag(model, Config.Tags.Guard)
	model.Parent = folder
	guards[zone] = { model = model, home = home, label = label, state = "sleep" }
	setGuardState(guards[zone], "sleep", nil)
end

---------------------------------------------------------------------------
-- Nests
---------------------------------------------------------------------------

local tryGrab

local function spawnEgg(nest, creatureId: string?)
	if nest.model then
		return
	end
	creatureId = creatureId or Sea.rollCreature(nest.zone, random)
	local creature = Sea.Creatures[creatureId]
	local rarity = Sea.rarityOf(creatureId)
	local model = AssetModels.egg(creatureId)
	local height = model:GetExtentsSize().Y
	model:PivotTo(CFrame.new(topOf(nest.part)))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(190, 54)
	gui.StudsOffset = Vector3.new(0, height + 2, 0)
	gui.MaxDistance = 110
	gui.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = rarity.color
	label.TextStrokeTransparency = 0
	label.Text = string.format("%s Egg\n$%d/s  -  %d%% speed", rarity.id, creature.income, math.floor(rarity.weight * 100 + 0.5))
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal"
	prompt.ObjectText = rarity.id .. " Egg"
	prompt.HoldDuration = Config.GrabHoldTime
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	local startedAt = {}
	prompt.PromptButtonHoldBegan:Connect(function(player)
		startedAt[player] = os.clock()
	end)
	prompt.Triggered:Connect(function(player)
		tryGrab(nest, player, startedAt[player])
	end)

	model.Parent = folder
	nest.model = model
	nest.creatureId = creatureId
end

-- Gives the player an egg to carry above their head.
local function carry(player: Player, creatureId: string, nest): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or carried[player] then
		return false
	end
	local model = AssetModels.egg(creatureId)
	AssetModels.makeCarryable(model)
	model:PivotTo(rootPart.CFrame * CFrame.new(0, 3.2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Name = "CarriedEgg"
	model.Parent = character
	carried[player] = { creatureId = creatureId, model = model, nest = nest }
	local rarity = Sea.rarityOf(creatureId)
	Movement.setWeight(player, rarity.weight)
	PlayerData.notify(player, "Got a " .. rarity.id .. " egg! It is heavy - run home!", "success")
	PlayerData.changed(player)
	return true
end

tryGrab = function(nest, player: Player, started: number?)
	if not nest.model or not started or os.clock() - started < Config.GrabHoldTime - 0.2 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or not PlayerData.get(player) then
		return
	end
	if (rootPart.Position - nest.part.Position).Magnitude > 18 then
		return
	end
	if carried[player] then
		PlayerData.notify(player, "You already carry an egg! Bring it home first.", "error")
		return
	end
	local creatureId = nest.creatureId
	nest.model:Destroy()
	nest.model = nil
	if carry(player, creatureId, nest) then
		wakeGuard(nest.zone, player) -- taking an egg always wakes the zone's guardian
	end
	task.delay(Config.NestRespawn, function()
		spawnEgg(nest)
	end)
end

-- Takes the carried egg away. An egg from a nest goes straight back to it.
function Ocean.drop(player: Player)
	local item = carried[player]
	if not item then
		return
	end
	carried[player] = nil
	if item.model then
		item.model:Destroy()
	end
	if item.nest and not item.nest.model then
		spawnEgg(item.nest, item.creatureId)
	end
	Movement.setWeight(player, nil)
	calmGuards(player)
	PlayerData.changed(player)
end

local function deliverTick()
	for player, item in carried do
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if rootPart and Bases.isHome(player, rootPart.Position) then
			if Bases.addEgg(player, item.creatureId) then
				carried[player] = nil
				item.model:Destroy()
				Movement.setWeight(player, nil)
				calmGuards(player)
				PlayerData.notify(player, "Egg is in the incubator!", "success")
				PlayerData.changed(player)
			elseif (fullWarned[player] or 0) < os.clock() then
				fullWarned[player] = os.clock() + 8
				PlayerData.notify(player, "All incubators are busy! Wait for an egg to hatch.", "error")
			end
		end
	end
end

local function onDash(player: Player)
	if (dashReadyAt[player] or 0) > os.clock() then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	dashReadyAt[player] = os.clock() + Config.DashCooldown
	Movement.dash(player)
	PlayerData.changed(player)
end

function Ocean.start()
	for _, post in CollectionService:GetTagged(Config.Tags.GuardPost) do
		if post:IsA("BasePart") then
			setupGuard(post)
		end
	end
	for _, part in CollectionService:GetTagged(Config.Tags.EggNest) do
		local zone = part:GetAttribute("Zone")
		if part:IsA("BasePart") and type(zone) == "number" and Sea.Zones[zone] then
			local nest = { part = part, zone = zone }
			nests[part] = nest
			spawnEgg(nest)
		end
	end

	-- Depth signs on the glowing arches.
	for _, bar in CollectionService:GetTagged(Config.Tags.DepthArch) do
		local zone = Sea.Zones[bar:GetAttribute("Zone")]
		if zone and bar:IsA("BasePart") then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(420, 110)
			gui.StudsOffset = Vector3.new(0, 7, 0)
			gui.MaxDistance = 320
			gui.Parent = bar
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.Text = string.format("-%dm  %s\nRecommended speed: %d+", zone.depth, string.upper(zone.name), zone.speed)
			label.Parent = gui
		end
	end

	Bases.hooks.onSteal = function(thief: Player, creatureId: string)
		if carried[thief] then
			PlayerData.notify(thief, "You already carry an egg!", "error")
			return false
		end
		return carry(thief, creatureId, nil)
	end

	PlayerData.addStateProvider(function(player, state)
		local item = carried[player]
		if item then
			local rarity = Sea.rarityOf(item.creatureId)
			state.carrying = { rarity = rarity.id, weight = rarity.weight }
		end
		state.dashLeft = math.max(0, (dashReadyAt[player] or 0) - os.clock())
		state.entrance = Bases.entrance(player)
		state.chased = false
		for _, guard in guards do
			if guard.target == player then
				state.chased = true
			end
		end
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					Ocean.drop(player)
				end)
			end
		end)
		player.CharacterRemoving:Connect(function()
			Ocean.drop(player)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		Ocean.drop(player)
		dashReadyAt[player] = nil
		fullWarned[player] = nil
		safeUntil[player] = nil
	end)

	Remotes.get("Dash").OnServerEvent:Connect(onDash)
	Remotes.get("DropEgg").OnServerEvent:Connect(function(player)
		if actionLimiter:check(player) and carried[player] then
			Ocean.drop(player)
			PlayerData.notify(player, "You dropped the egg.", "info")
		end
	end)

	-- Guardians move 20 times a second.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.05 then
			guardTick(elapsed)
			elapsed = 0
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			deliverTick()
		end
	end)
end

return Ocean
