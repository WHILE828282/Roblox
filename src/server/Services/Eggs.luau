-- Eggs.luau
-- The volcano and its eggs:
--   * Every Config.EruptionInterval the volcano shoots eggs across the field.
--     Eggs closer to the volcano (inner ring) are rarer.
--   * Every Config.BigEruptionInterval a BIG eruption fires many eggs plus one
--     guaranteed Legendary-or-better egg, announced to the whole server.
--   * Players grab eggs (hold prompt) and carry them home; carried eggs are
--     dropped when the carrier is hit, chased off by guards, or dies.
--   * Reaching your own base puts carried eggs into free nests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Format = require(ReplicatedStorage.Shared.Format)
local DinoModel = require(ReplicatedStorage.Shared.DinoModel)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local Mounts = require(script.Parent.Mounts)
local Tagged = require(script.Parent.Parent.Lib.Tagged)
local Ground = require(script.Parent.Parent.Lib.Ground)

local Eggs = {}

local random = Random.new()
local announceRemote = Remotes.get("Announce")

-- wild[model] = { egg = {s,t,m}, createdAt, landed, grabbableAt }
local wild: { [Model]: any } = {}
-- carried[player] = { { egg = {s,t,m}, model = Model }, ... }
local carried: { [Player]: { any } } = {}
local lastPosition: { [Player]: Vector3 } = {}
local nestsFullWarned: { [Player]: number } = {}

local volcanoTop = Vector3.new(0, 60, 0)
local serverLuckUntil = 0
local nextEruption = 0
local nextBigEruption = 0
local bigWarned = false

local wildFolder = Instance.new("Folder")
wildFolder.Name = "WildEggs"
wildFolder.Parent = workspace

local function luck(): number
	return if serverLuckUntil > os.time() then Config.ServerLuckMultiplier else 1
end

local function ringAt(position: Vector3): string
	local distance = Vector3.new(position.X, 0, position.Z).Magnitude
	if distance <= Config.RingRadii.Inner then
		return "Inner"
	elseif distance <= Config.RingRadii.Middle then
		return "Middle"
	end
	return "Outer"
end

local function groundAt(x: number, z: number): Vector3
	return Ground.at(x, z)
end

-- Random landing spot; `ring` forces a ring ("Inner" etc.) or nil for anywhere.
local function randomLanding(ring: string?): Vector3
	local minRadius, maxRadius = Config.FieldInnerRadius, Config.FieldOuterRadius
	if ring == "Inner" then
		maxRadius = Config.RingRadii.Inner
	end
	-- sqrt keeps eggs evenly spread over the area instead of crowding the center
	local t = random:NextNumber()
	local radius = math.sqrt(minRadius ^ 2 + t * (maxRadius ^ 2 - minRadius ^ 2))
	local angle = random:NextNumber() * math.pi * 2
	return groundAt(math.cos(angle) * radius, math.sin(angle) * radius)
end

local function tryGrab(model: Model, player: Player, startedAt: { [Player]: number })
	local info = wild[model]
	if not info or not info.landed or os.clock() < info.grabbableAt then
		return
	end
	local started = startedAt[player]
	if not started or os.clock() - started < Config.GrabHoldTime - 0.2 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or not PlayerData.get(player) then
		return
	end
	if (rootPart.Position - model:GetPivot().Position).Magnitude > 16 then
		return
	end
	local list = carried[player] or {}
	if #list >= Mounts.carryCapacity(player) then
		PlayerData.notify(player, "Your hands are full! Bring your eggs home first.", "error")
		return
	end
	wild[model] = nil
	model:Destroy()
	Eggs.carry(player, info.egg)
end

-- Creates a wild egg. With `from`, it flies in an arc from there to `to`.
local function spawnWildEgg(egg, to: Vector3, from: Vector3?)
	local model = DinoModel.buildEgg(egg.s, egg.t, egg.m)
	local tier = Dinos.TierById[egg.t]
	local height = model.PrimaryPart.Size.Y * 1.3
	local landing = to + Vector3.new(0, height / 2, 0)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 36)
	gui.StudsOffset = Vector3.new(0, height / 2 + 1.5, 0)
	gui.MaxDistance = if tier.index >= Config.RareEggAnnounceTier then 400 else 90
	gui.AlwaysOnTop = tier.index >= Config.RareEggAnnounceTier
	gui.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = tier.color
	label.TextStrokeTransparency = 0.2
	label.Text = (if egg.m ~= "Normal" then egg.m .. " " else "") .. tier.id .. " Egg"
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = Dinos.displayName(egg.s, egg.t, egg.m) .. " Egg"
	prompt.HoldDuration = Config.GrabHoldTime
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = from == nil
	prompt.Parent = model.PrimaryPart
	local startedAt = {}
	prompt.PromptButtonHoldBegan:Connect(function(player)
		startedAt[player] = os.clock()
	end)
	prompt.Triggered:Connect(function(player)
		tryGrab(model, player, startedAt)
	end)

	local info =
		{ egg = egg, createdAt = os.time(), landed = from == nil, grabbableAt = os.clock() + (if from then 0 else 1) }
	wild[model] = info

	if from then
		model:PivotTo(CFrame.new(from))
		model.Parent = wildFolder
		-- Fly in an arc; anchored parts moved by the server replicate to everyone.
		local arcHeight = 40 + (landing - from).Magnitude * 0.25
		local started = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if not model.Parent then
				connection:Disconnect()
				return
			end
			local alpha = math.min((os.clock() - started) / Config.EggFlightTime, 1)
			local position = from:Lerp(landing, alpha) + Vector3.new(0, arcHeight * 4 * alpha * (1 - alpha), 0)
			model:PivotTo(CFrame.new(position) * CFrame.Angles(alpha * 6, 0, alpha * 3))
			if alpha >= 1 then
				connection:Disconnect()
				model:PivotTo(CFrame.new(landing))
				info.landed = true
				prompt.Enabled = true
			end
		end)
	else
		model:PivotTo(CFrame.new(landing))
		model.Parent = wildFolder
	end
	return model
end

local function countWild(): number
	local count = 0
	for _ in wild do
		count += 1
	end
	return count
end

local function announceEgg(egg, prefix: string)
	local tier = Dinos.TierById[egg.t]
	if tier.index >= Config.RareEggAnnounceTier then
		announceRemote:FireAllClients(prefix .. string.upper(tier.id) .. " egg landed near the volcano!", tier.color)
	end
end

local function erupt(count: number, big: boolean)
	count = math.min(count, Config.MaxWildEggs - countWild() + (if big then 4 else 0))
	for i = 1, math.max(count, 0) do
		task.delay(i * 0.12, function()
			local landing = randomLanding(nil)
			local egg = Dinos.rollEgg(ringAt(landing), luck(), random)
			spawnWildEgg(egg, landing, volcanoTop)
			announceEgg(egg, "A ")
		end)
	end
	if big then
		task.delay(count * 0.12 + 0.5, function()
			local landing = randomLanding("Inner")
			local egg = Dinos.rollEgg("Big", luck(), random)
			spawnWildEgg(egg, landing, volcanoTop)
			announceEgg(egg, "BIG ERUPTION! A ")
		end)
	end
end

---------------------------------------------------------------------------
-- Carrying
---------------------------------------------------------------------------

-- Gives the player an egg to carry (shown stacked above their head).
function Eggs.carry(player: Player, egg)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	local list = carried[player] or {}
	carried[player] = list

	local model = DinoModel.buildEgg(egg.s, egg.t, egg.m)
	DinoModel.makeCarryable(model)
	model:PivotTo(rootPart.CFrame * CFrame.new(0, 4.5 + #list * 3, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Name = "CarriedEgg"
	model.Parent = character
	table.insert(list, { egg = { s = egg.s, t = egg.t, m = egg.m }, model = model })
	PlayerData.notify(player, "Got a " .. Dinos.displayName(egg.s, egg.t, egg.m) .. " egg! Run home!", "success")
	PlayerData.changed(player)
end

function Eggs.carryCount(player: Player): number
	local list = carried[player]
	return if list then #list else 0
end

-- Drops everything the player carries onto the ground around `position`.
function Eggs.dropCarried(player: Player, position: Vector3?)
	local list = carried[player]
	carried[player] = nil
	if not list or #list == 0 then
		return
	end
	if not position then
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		position = if rootPart then rootPart.Position else lastPosition[player]
	end
	for index, item in list do
		if item.model then
			item.model:Destroy()
		end
		if position then
			local angle = index * 2.1
			local spot = groundAt(position.X + math.cos(angle) * 4, position.Z + math.sin(angle) * 4)
			spawnWildEgg(item.egg, spot, nil)
		end
	end
	PlayerData.notify(player, "You dropped your eggs!", "error")
	PlayerData.changed(player)
end

local function deliverTick()
	for player, list in carried do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			lastPosition[player] = rootPart.Position
			if #list > 0 and Bases.isHome(player, rootPart.Position) then
				while #list > 0 and Bases.freeNests(player) > 0 do
					local item = table.remove(list, 1)
					if item.model then
						item.model:Destroy()
					end
					Bases.addEgg(player, item.egg)
					PlayerData.notify(player, "Egg placed in a nest!", "success")
				end
				if #list > 0 and (nestsFullWarned[player] or 0) < os.clock() then
					nestsFullWarned[player] = os.clock() + 10
					PlayerData.notify(player, "Your nests are full! Wait for eggs to hatch or buy More Nests.", "error")
				end
				PlayerData.changed(player)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Robux hooks
---------------------------------------------------------------------------

function Eggs.boostServerLuck(seconds: number)
	serverLuckUntil = math.max(serverLuckUntil, os.time()) + seconds
end

function Eggs.triggerBigEruption()
	local soon = os.time() + Config.BigEruptionWarning
	if nextBigEruption > soon then
		nextBigEruption = soon
		bigWarned = false
	end
end

-- Starts an eruption right away (used by DevTools).
function Eggs.eruptNow(big: boolean)
	erupt(if big then Config.BigEruptionEggs else Config.EggsPerEruption, big)
end

function Eggs.start()
	Tagged(Config.Tags.Volcano, function(instance)
		if instance:IsA("BasePart") then
			volcanoTop = instance.Position + Vector3.new(0, instance.Size.Y / 2 + 4, 0)
		end
		return nil
	end)

	Bases.hooks.onSteal = function(thief: Player, _owner: Player, egg)
		if Eggs.carryCount(thief) >= Mounts.carryCapacity(thief) then
			PlayerData.notify(thief, "Your hands are full!", "error")
			return false
		end
		Eggs.carry(thief, egg)
		return true
	end
	Bases.hooks.onGuardHit = function(thief: Player)
		Eggs.dropCarried(thief)
	end

	PlayerData.addStateProvider(function(player, state)
		state.carrying = Eggs.carryCount(player)
		state.serverLuckLeft = math.max(0, serverLuckUntil - os.time())
		state.bigEruptionIn = math.max(0, nextBigEruption - os.time())
	end)

	local function watchPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			Eggs.dropCarried(player, lastPosition[player])
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		Eggs.dropCarried(player, lastPosition[player])
		lastPosition[player] = nil
		nestsFullWarned[player] = nil
	end)

	nextEruption = os.time() + 5
	nextBigEruption = os.time() + Config.BigEruptionInterval
	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.time()
			if t >= nextEruption then
				nextEruption = t + Config.EruptionInterval
				erupt(Config.EggsPerEruption, false)
			end
			if not bigWarned and t >= nextBigEruption - Config.BigEruptionWarning then
				bigWarned = true
				announceRemote:FireAllClients(
					"The volcano is rumbling... BIG ERUPTION in " .. Format.duration(nextBigEruption - t) .. "!",
					Color3.fromRGB(255, 120, 40)
				)
			end
			if t >= nextBigEruption then
				nextBigEruption = t + Config.BigEruptionInterval
				bigWarned = false
				erupt(Config.BigEruptionEggs, true)
			end
			-- Old eggs crumble so the field doesn't fill up.
			for model, info in wild do
				if t - info.createdAt > Config.WildEggLifetime then
					wild[model] = nil
					model:Destroy()
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			deliverTick()
		end
	end)
end

return Eggs
