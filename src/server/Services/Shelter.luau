-- Shelter.luau
-- Every player gets a shelter plot. Rescued animals live there and earn
-- money every second. Handles plot assignment, spawning at the plot,
-- the animal display, income, offline income and selling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Animals = require(ReplicatedStorage.Shared.Animals)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local AnimalModel = require(ReplicatedStorage.Shared.AnimalModel)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Shelter = {}

local GRID_SPACING = 5.5
local MAX_ANIMALS = 200 -- hard safety cap on saved animals

-- plots[i] = { part = BasePart, owner = Player?, folder = Folder, label = TextLabel }
local plots = {}
local playerPlot: { [Player]: any } = {}
local shelterRemote = Remotes.get("ShelterChanged")
local sellLimiter = RateLimiter.new(Config.ActionCooldown)

local displayRoot = Instance.new("Folder")
displayRoot.Name = "ShelterAnimals"
displayRoot.Parent = workspace

function Shelter.capacity(player: Player): number
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return 0
	end
	return Economy.capacity(data.Upgrades.Shelter, session.passes.BigShelter == true)
end

function Shelter.isFull(player: Player): boolean
	local data = PlayerData.get(player)
	return data == nil or #data.Animals >= Shelter.capacity(player)
end

-- Money per second from all of the player's animals.
function Shelter.income(player: Player): number
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return 0
	end
	local total = 0
	for _, animal in data.Animals do
		total += Economy.animalIncome(animal.s, animal.m, animal.z)
	end
	if session.passes.DoubleMoney then
		total *= 2
	end
	return total
end

local function updateSign(plot)
	if not plot.label then
		return
	end
	if plot.owner then
		plot.label.Text = string.format("%s's Shelter\n%s/s", plot.owner.DisplayName, Format.money(Shelter.income(plot.owner)))
	else
		plot.label.Text = "Free Shelter"
	end
end

-- Rebuilds the animal models standing on the player's plot.
local function refreshDisplay(player: Player)
	local plot = playerPlot[player]
	local data = PlayerData.get(player)
	if not plot or not data then
		return
	end
	plot.folder:ClearAllChildren()

	local sorted = table.clone(data.Animals)
	table.sort(sorted, function(a, b)
		return Economy.animalIncome(a.s, a.m, a.z) > Economy.animalIncome(b.s, b.m, b.z)
	end)

	local part: BasePart = plot.part
	local columns = math.max(1, math.floor((part.Size.X - 4) / GRID_SPACING))
	local rows = math.max(1, math.floor((part.Size.Z - 6) / GRID_SPACING))
	local topY = part.Size.Y / 2
	for index, animal in sorted do
		if index > columns * rows then
			break
		end
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		local x = (column - (columns - 1) / 2) * GRID_SPACING
		local z = -part.Size.Z / 2 + 6 + row * GRID_SPACING
		local model = AnimalModel.build(animal.s, animal.m)
		model:PivotTo(part.CFrame * CFrame.new(x, topY, z))
		model.Parent = plot.folder
	end
	updateSign(plot)
end

local function sendList(player: Player)
	local data = PlayerData.get(player)
	if data then
		shelterRemote:FireClient(player, data.Animals)
	end
end

-- Call after the player's animal list changed.
function Shelter.animalsChanged(player: Player)
	refreshDisplay(player)
	sendList(player)
	PlayerData.changed(player)
end

-- Adds a rescued animal. Returns the new entry, or nil if the shelter is full.
function Shelter.addAnimal(player: Player, speciesId: string, mutationId: string, zoneId: string?)
	local data = PlayerData.get(player)
	if not data or Shelter.isFull(player) or #data.Animals >= MAX_ANIMALS then
		return nil
	end
	local entry = { id = data.NextId, s = speciesId, m = mutationId }
	-- Mythic animals have no home zone: remember where they were found.
	if Animals.Species[speciesId].zone == nil then
		entry.z = zoneId
	end
	data.NextId += 1
	data.TotalRescued += 1
	table.insert(data.Animals, entry)
	Shelter.animalsChanged(player)
	return entry
end

local function onSellRequested(player: Player, animalId: any)
	if not sellLimiter:check(player) or type(animalId) ~= "number" then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	for index, animal in data.Animals do
		if animal.id == animalId then
			table.remove(data.Animals, index)
			local price = Economy.sellPrice(animal.s, animal.m, animal.z)
			data.Money += price
			PlayerData.notify(player, string.format("Sold %s for %s", Animals.displayName(animal.s, animal.m), Format.money(price)), "coin")
			Shelter.animalsChanged(player)
			return
		end
	end
end

local function spawnAtPlot(player: Player, character: Model)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or playerPlot[player] ~= plot then
		return
	end
	task.wait() -- let Roblox finish its own spawn positioning
	local part: BasePart = plot.part
	character:PivotTo(part.CFrame * CFrame.new(0, part.Size.Y / 2 + 3, -part.Size.Z / 2 - 4))
end

local function assignPlot(player: Player)
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			playerPlot[player] = plot
			plot.part:SetAttribute("Owner", player.UserId)
			refreshDisplay(player)
			if player.Character then
				task.spawn(spawnAtPlot, player, player.Character)
			end
			return
		end
	end
	warn("[Shelter] No free plot for " .. player.Name .. ". Set the server size to the number of ShelterPlot parts.")
end

local function releasePlot(player: Player)
	local plot = playerPlot[player]
	playerPlot[player] = nil
	if plot then
		plot.owner = nil
		plot.folder:ClearAllChildren()
		plot.part:SetAttribute("Owner", nil)
		updateSign(plot)
	end
end

local function giveOfflineIncome(player: Player)
	local data = PlayerData.get(player)
	if not data or data.LastSeen <= 0 then
		return
	end
	local away = math.min(os.time() - data.LastSeen, Config.OfflineIncomeMaxHours * 3600)
	if away < 60 then
		return
	end
	local amount = math.floor(Shelter.income(player) * away * Config.OfflineIncomeShare)
	if amount > 0 then
		data.Money += amount
		PlayerData.notify(player, string.format("Your animals earned %s while you were away!", Format.money(amount)), "coin")
	end
end

local function setupPlot(part: BasePart)
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. tostring(part:GetAttribute("PlotIndex") or #plots + 1)
	folder.Parent = displayRoot

	-- Floating sign above the front of the plot.
	local anchor = Instance.new("Part")
	anchor.Name = "ShelterSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 9, -part.Size.Z / 2)
	anchor.Parent = folder.Parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 70)
	gui.MaxDistance = 200
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	local plot = { part = part, owner = nil, folder = folder, label = label }
	table.insert(plots, plot)
	table.sort(plots, function(a, b)
		return (a.part:GetAttribute("PlotIndex") or 0) < (b.part:GetAttribute("PlotIndex") or 0)
	end)
	updateSign(plot)
	return nil
end

function Shelter.start()
	Tagged(Config.Tags.ShelterPlot, function(instance)
		if instance:IsA("BasePart") then
			return setupPlot(instance)
		end
		warn("[Shelter] 'ShelterPlot' tag must be on a Part: " .. instance:GetFullName())
		return nil
	end)

	PlayerData.addStateProvider(function(player, state)
		local data = PlayerData.get(player)
		state.income = Shelter.income(player)
		state.capacity = Shelter.capacity(player)
		state.animalCount = if data then #data.Animals else 0
	end)

	PlayerData.ProfileLoaded:Connect(function(player)
		giveOfflineIncome(player)
		assignPlot(player)
		sendList(player)
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawnAtPlot(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releasePlot(player)
		sellLimiter:forget(player)
	end)

	Remotes.get("SellAnimal").OnServerEvent:Connect(onSellRequested)

	-- Pay income every second.
	task.spawn(function()
		while true do
			task.wait(1)
			for player, data in PlayerData.all() do
				local income = Shelter.income(player)
				if income > 0 then
					data.Money += income
					PlayerData.changed(player)
				end
			end
		end
	end)

	-- Keep the "$/s" on shelter signs fresh.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, plot in plots do
				updateSign(plot)
			end
		end
	end)
end

-- Used by the Robux "cash" products.
function Shelter.sendList(player: Player)
	sendList(player)
end

return Shelter
