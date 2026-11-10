-- PlayerData.luau
-- Loads, stores and saves every player's progress with DataStoreService.
-- This is the ONLY place that changes saved values; other services call
-- the functions below. All DataStore calls are wrapped in pcall with retries.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Leaderboard = require(script.Parent.Leaderboard)

local PlayerData = {}

-- profiles[player] = {
--   data = saved table (see Config.DefaultData),
--   canSave = false if loading failed (so we never overwrite real data with defaults),
--   session = values that only live for this server session (not saved):
--     runStart = server time when the timed run began, or nil
--     lastAdvance = server time of the last checkpoint reached
--     maxStage = highest stage in the map (for the HUD)
-- }
local profiles = {}

local profileLoaded = Instance.new("BindableEvent")
-- Fires (player) once the player's data is ready to use.
PlayerData.ProfileLoaded = profileLoaded.Event

-- Set by Checkpoints so the HUD knows how many stages exist.
PlayerData.getMaxStage = function(): number
	return 0
end

local stateRemote = Remotes.get("StateChanged")
local notifyRemote = Remotes.get("Notify")

-- GetDataStore can throw (e.g. Studio without API access), so wrap it too.
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

-- Calls `fn` inside pcall up to Config.DataStoreRetries times with backoff.
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

-- Makes sure saved data has every expected key with the right type.
-- Protects against old/corrupted saves.
local function reconcile(saved: any): { [string]: any }
	local data = table.clone(Config.DefaultData)
	if type(saved) == "table" then
		for key, default in Config.DefaultData do
			local value = saved[key]
			if type(value) == type(default) then
				data[key] = value
			end
		end
	end
	data.Coins = math.max(0, math.floor(data.Coins))
	data.Stage = math.max(0, math.floor(data.Stage))
	data.Wins = math.max(0, math.floor(data.Wins))
	data.BestTime = math.max(0, data.BestTime)
	return data
end

local function createLeaderstats(player: Player, data)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats" -- this exact name shows values in the player list

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = folder

	local stage = Instance.new("IntValue")
	stage.Name = "Stage"
	stage.Value = data.Stage
	stage.Parent = folder

	folder.Parent = player
end

-- Returns the player's saved data table, or nil if it is not loaded yet.
function PlayerData.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

-- Returns the session-only table (run timer etc.), or nil.
function PlayerData.getSession(player: Player)
	local profile = profiles[player]
	return profile and profile.session
end

-- Builds the table sent to the client HUD.
local function buildState(player: Player)
	local profile = profiles[player]
	return {
		coins = profile.data.Coins,
		stage = profile.data.Stage,
		maxStage = PlayerData.getMaxStage(),
		bestTime = profile.data.BestTime,
		wins = profile.data.Wins,
		runStart = profile.session.runStart,
		saving = profile.canSave,
	}
end

-- Call after changing data: updates leaderstats and the player's HUD.
function PlayerData.changed(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Coins.Value = profile.data.Coins
		leaderstats.Stage.Value = profile.data.Stage
	end
	stateRemote:FireClient(player, buildState(player))
end

function PlayerData.addCoins(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Coins += math.floor(amount)
	PlayerData.changed(player)
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
	local snapshot = table.clone(profile.data)
	local ok = withRetries("Save " .. player.UserId, function()
		store:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)
	if ok then
		Leaderboard.submit(player.UserId, snapshot.Coins)
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

	-- The player may have left while we were waiting for the DataStore.
	if player.Parent ~= Players then
		return
	end

	profiles[player] = {
		data = reconcile(if loadedOk then saved else nil),
		canSave = loadedOk,
		session = {},
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
	-- Players who joined before this script ran (can happen in Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave so a server crash loses at most a couple of minutes.
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)

	-- When the server shuts down, save everyone before it closes.
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
