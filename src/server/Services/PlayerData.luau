-- PlayerData.luau
-- Loads, stores and saves every player's progress with DataStoreService.
-- All DataStore calls are wrapped in pcall with retries. Other services
-- change the data table and then call PlayerData.changed(player).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
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
		warn(
			string.format(
				"[PlayerData] %s failed (attempt %d/%d): %s",
				label,
				attempt,
				Config.DataStoreRetries,
				tostring(result)
			)
		)
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

local function validDino(entry): boolean
	return type(entry) == "table"
		and type(entry.id) == "number"
		and Dinos.Species[entry.s] ~= nil
		and Dinos.TierById[entry.t] ~= nil
		and Dinos.Mutations[entry.m] ~= nil
end

-- Turns whatever was saved (old, broken or tampered) into valid data.
local function reconcile(saved: any)
	saved = if type(saved) == "table" then saved else {}
	local data = {}
	data.Money = number(saved.Money, 0, 0)
	data.Hatched = math.floor(number(saved.Hatched, 0, 0))
	data.NextId = math.floor(number(saved.NextId, 1, 1))
	data.LastSeen = number(saved.LastSeen, 0, 0)

	data.Dinos = {}
	if type(saved.Dinos) == "table" then
		for _, dino in saved.Dinos do
			if validDino(dino) and #data.Dinos < 100 then
				table.insert(data.Dinos, { id = dino.id, s = dino.s, t = dino.t, m = dino.m, g = number(dino.g, 0, 0) })
				data.NextId = math.max(data.NextId, dino.id + 1)
			end
		end
	end

	data.Eggs = {}
	if type(saved.Eggs) == "table" then
		for _, egg in saved.Eggs do
			if validDino(egg) and #data.Eggs < 20 then
				table.insert(
					data.Eggs,
					{ id = egg.id, s = egg.s, t = egg.t, m = egg.m, hatchAt = number(egg.hatchAt, 0, 0) }
				)
				data.NextId = math.max(data.NextId, egg.id + 1)
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
			if type(purchaseId) == "string" and #data.Purchases < 50 then
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

	local hatched = Instance.new("IntValue")
	hatched.Name = "Hatched"
	hatched.Value = data.Hatched
	hatched.Parent = folder

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

-- Call after changing data: updates leaderstats and the player's HUD.
function PlayerData.changed(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Money.Value = math.floor(profile.data.Money)
		leaderstats.Hatched.Value = profile.data.Hatched
	end
	local state = {
		money = profile.data.Money,
		hatched = profile.data.Hatched,
		upgrades = profile.data.Upgrades,
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
		Leaderboard.submit(player.UserId, snapshot.Hatched)
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
		session = { passes = {} },
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
