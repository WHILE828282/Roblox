-- PlayerData.luau
-- Loads, stores and saves every player's progress with DataStoreService.
-- All DataStore calls use pcall with retries. If loading fails, that session
-- is never saved, so real progress cannot be overwritten with defaults.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sea = require(ReplicatedStorage.Shared.Sea)

local PlayerData = {}

-- profiles[player] = { data = saved table, canSave = boolean, session = values for this server only }
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
	return if max then math.min(max, value) else value
end

-- Turns whatever was saved (old, broken or tampered) into valid data.
local function reconcile(saved: any)
	saved = if type(saved) == "table" then saved else {}
	local data = {
		Money = number(saved.Money, 0, 0),
		Pending = number(saved.Pending, 0, 0), -- income waiting on the collect plate
		Speed = number(saved.Speed, Config.StartSpeed, Config.StartSpeed, Config.MaxSpeed),
		Treadmill = math.floor(number(saved.Treadmill, 0, 0, Config.TreadmillMaxLevel)),
		Aquarium = math.floor(number(saved.Aquarium, 0, 0, Config.AquariumMaxLevel)),
		NextId = math.floor(number(saved.NextId, 1, 1)),
		Creatures = {}, -- { { id, c = creature id }, ... }
		Eggs = {}, -- incubators: { { id, c = creature id, hatchAt, slot }, ... }
		Trails = {}, -- owned trail ids
		Trail = nil, -- equipped trail id
		Index = {}, -- [creature id] = true once hatched
	}
	if type(saved.Creatures) == "table" then
		for _, entry in saved.Creatures do
			if type(entry) == "table" and type(entry.id) == "number" and Sea.Creatures[entry.c] and #data.Creatures < 60 then
				table.insert(data.Creatures, { id = entry.id, c = entry.c })
				data.NextId = math.max(data.NextId, entry.id + 1)
			end
		end
	end
	if type(saved.Eggs) == "table" then
		for _, entry in saved.Eggs do
			if type(entry) == "table" and type(entry.id) == "number" and Sea.Creatures[entry.c] and #data.Eggs < Config.Incubators then
				table.insert(data.Eggs, {
					id = entry.id,
					c = entry.c,
					hatchAt = number(entry.hatchAt, 0, 0),
					slot = math.floor(number(entry.slot, #data.Eggs + 1, 1, Config.Incubators)),
				})
				data.NextId = math.max(data.NextId, entry.id + 1)
			end
		end
	end
	if type(saved.Trails) == "table" then
		for _, trailId in saved.Trails do
			if Sea.TrailById[trailId] and not table.find(data.Trails, trailId) then
				table.insert(data.Trails, trailId)
			end
		end
	end
	if table.find(data.Trails, saved.Trail) then
		data.Trail = saved.Trail
	end
	if type(saved.Index) == "table" then
		for creatureId in saved.Index do
			if Sea.Creatures[creatureId] then
				data.Index[creatureId] = true
			end
		end
	end
	return data
end

function PlayerData.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function PlayerData.getSession(player: Player)
	local profile = profiles[player]
	return profile and profile.session
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
	local data = profile.data
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Money.Value = math.floor(data.Money)
		leaderstats.Speed.Value = math.floor(data.Speed)
	end
	local state = {
		money = data.Money,
		pending = data.Pending,
		speed = data.Speed,
		treadmill = data.Treadmill,
		aquarium = data.Aquarium,
		creatures = data.Creatures,
		eggs = data.Eggs,
		trails = data.Trails,
		trail = data.Trail,
		index = data.Index,
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

function PlayerData.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end
	local snapshot = table.clone(profile.data)
	local ok = withRetries("Save " .. player.UserId, function()
		store:UpdateAsync("Player_" .. player.UserId, function()
			return snapshot
		end)
	end)
	return ok
end

local function onPlayerAdded(player: Player)
	local saved, loadedOk = nil, false
	if store then
		loadedOk, saved = withRetries("Load " .. player.UserId, function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
	end
	if player.Parent ~= Players then
		return -- left while loading
	end
	local data = reconcile(if loadedOk then saved else nil)
	profiles[player] = { data = data, canSave = loadedOk, session = {} }

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Value = data.Money
	money.Parent = leaderstats
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Value = data.Speed
	speed.Parent = leaderstats
	leaderstats.Parent = player

	if not loadedOk then
		PlayerData.notify(player, "Could not load your progress. It will not be saved this session.", "error")
	end
	profileLoaded:Fire(player)
	PlayerData.changed(player)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			PlayerData.save(player)
			profiles[player] = nil
		end
	end)
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
