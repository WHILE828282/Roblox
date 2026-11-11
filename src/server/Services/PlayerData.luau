-- PlayerData.luau
-- Loads, stores and saves every player's progress with DataStoreService.
-- All DataStore calls are wrapped in pcall with retries. Other services
-- change the data table and then call PlayerData.changed(player).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Animals = require(ReplicatedStorage.Shared.Animals)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Leaderboard = require(script.Parent.Leaderboard)

local PlayerData = {}

-- profiles[player] = {
--   data = saved table (see Config.DefaultData),
--   canSave = false if loading failed (never overwrite real data with defaults),
--   session = values for this server only (gamepasses, auto rescue toggle, ...)
-- }
local profiles = {}

local profileLoaded = Instance.new("BindableEvent")
PlayerData.ProfileLoaded = profileLoaded.Event -- fires (player)

-- Other services add fields to the HUD state with addStateProvider(fn(player, state)).
local stateProviders = {}
function PlayerData.addStateProvider(provider)
	table.insert(stateProviders, provider)
end

local stateRemote = Remotes.get("StateChanged")
local notifyRemote = Remotes.get("Notify")

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore is unavailable, progress will NOT be saved: " .. tostring(result))
	end
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function withRetries(label: string, fn: () -> any): (boolean, any)
	local lastError
	for attempt = 1, Config.DataStoreRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[PlayerData] %s failed (attempt %d/%d): %s", label, attempt, Config.DataStoreRetries, tostring(result)))
		if attempt < Config.DataStoreRetries then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastError
end

local function number(value: any, default: number, min: number, max: number?): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	value = math.max(min, value)
	if max then
		value = math.min(max, value)
	end
	return value
end

-- Turns whatever was saved (old, broken or tampered) into valid data.
local function reconcile(saved: any)
	saved = if type(saved) == "table" then saved else {}
	local data = {}
	data.Money = math.floor(number(saved.Money, 0, 0))
	data.TotalRescued = math.floor(number(saved.TotalRescued, 0, 0))
	data.NextId = math.floor(number(saved.NextId, 1, 1))
	data.LuckBoostUntil = number(saved.LuckBoostUntil, 0, 0)
	data.LastSeen = number(saved.LastSeen, 0, 0)

	data.Animals = {}
	if type(saved.Animals) == "table" then
		for _, animal in saved.Animals do
			if type(animal) == "table" and Animals.Species[animal.s] and Animals.Mutations[animal.m] and type(animal.id) == "number" then
				local zone = if type(animal.z) == "string" and Animals.ZoneById[animal.z] then animal.z else nil
				table.insert(data.Animals, { id = animal.id, s = animal.s, m = animal.m, z = zone })
				data.NextId = math.max(data.NextId, animal.id + 1)
			end
			if #data.Animals >= 200 then
				break
			end
		end
	end

	data.Zones = { "Forest" }
	if type(saved.Zones) == "table" then
		for _, zoneId in saved.Zones do
			if Animals.ZoneById[zoneId] and not table.find(data.Zones, zoneId) then
				table.insert(data.Zones, zoneId)
			end
		end
	end

	data.Upgrades = {}
	local savedUpgrades = if type(saved.Upgrades) == "table" then saved.Upgrades else {}
	for upgradeId, upgrade in Economy.Upgrades do
		data.Upgrades[upgradeId] = math.floor(number(savedUpgrades[upgradeId], 0, 0, upgrade.maxLevel))
	end

	data.Purchases = {}
	if type(saved.Purchases) == "table" then
		for _, purchaseId in saved.Purchases do
			if type(purchaseId) == "string" then
				table.insert(data.Purchases, purchaseId)
			end
		end
	end
	return data
end

local function createLeaderstats(player: Player, data)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats" -- this exact name shows values in the player list

	local money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Value = data.Money
	money.Parent = folder

	local rescued = Instance.new("IntValue")
	rescued.Name = "Rescued"
	rescued.Value = data.TotalRescued
	rescued.Parent = folder

	folder.Parent = player
end

function PlayerData.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function PlayerData.getSession(player: Player)
	local profile = profiles[player]
	return profile and profile.session
end

function PlayerData.canSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.canSave
end

-- Iterate over every loaded player: for player, data in PlayerData.all() do
function PlayerData.all()
	local list = {}
	for player, profile in profiles do
		list[player] = profile.data
	end
	return list
end

function PlayerData.hasZone(player: Player, zoneId: string): boolean
	local data = PlayerData.get(player)
	return data ~= nil and table.find(data.Zones, zoneId) ~= nil
end

-- Call after changing data: updates leaderstats and the player's HUD.
function PlayerData.changed(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Money.Value = profile.data.Money
		leaderstats.Rescued.Value = profile.data.TotalRescued
	end
	local state = {
		money = profile.data.Money,
		rescued = profile.data.TotalRescued,
		upgrades = profile.data.Upgrades,
		zones = profile.data.Zones,
		luckBoostLeft = math.max(0, profile.data.LuckBoostUntil - os.time()),
		saving = profile.canSave,
	}
	for _, provider in stateProviders do
		provider(player, state)
	end
	stateRemote:FireClient(player, state)
end

function PlayerData.notify(player: Player, message: string, kind: string?)
	notifyRemote:FireClient(player, message, kind or "info")
end

-- Saves one player. Returns true on success.
function PlayerData.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end
	profile.data.LastSeen = os.time()
	local snapshot = table.clone(profile.data)
	local ok = withRetries("Save " .. player.UserId, function()
		store:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)
	if ok then
		Leaderboard.submit(player.UserId, snapshot.TotalRescued)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local saved = nil
	local loadedOk = false
	if store then
		loadedOk, saved = withRetries("Load " .. player.UserId, function()
			return store:GetAsync(keyFor(player))
		end)
	end
	if player.Parent ~= Players then
		return -- left while loading
	end

	profiles[player] = {
		data = reconcile(if loadedOk then saved else nil),
		canSave = loadedOk,
		session = { passes = {}, autoRescue = true },
	}
	createLeaderstats(player, profiles[player].data)

	if not loadedOk then
		PlayerData.notify(player, "Could not load your progress. Progress will not be saved this session.", "error")
	end

	profileLoaded:Fire(player)
	PlayerData.changed(player)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		PlayerData.save(player)
		profiles[player] = nil
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerData.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
