-- Leaderboard.luau
-- Global "Top hatchers" leaderboard stored in an OrderedDataStore.
-- Scores are submitted when player data is saved; the top list is
-- refreshed periodically and sent to every client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Leaderboard = {}

local leaderboardRemote = Remotes.get("LeaderboardChanged")

-- Latest top list: { { rank = 1, name = "Builderman", value = 123 }, ... }
local cachedEntries = {}
local nameCache: { [number]: string } = {}

local store: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Leaderboard] OrderedDataStore is unavailable: " .. tostring(result))
	end
end

-- Stores a player's score (total dinosaurs hatched). Safe to call often; errors are only logged.
function Leaderboard.submit(userId: number, value: number)
	if not store or userId <= 0 then
		return -- no store, or a Studio test account (negative id)
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), math.max(0, math.floor(value)))
	end)
	if not ok then
		warn("[Leaderboard] Submit failed: " .. tostring(err))
	end
end

local function getName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Player " .. userId
end

-- Downloads the current top list and broadcasts it to all clients.
function Leaderboard.refresh()
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.LeaderboardSize)
	end)
	if not ok then
		warn("[Leaderboard] Refresh failed: " .. tostring(pages))
		return
	end

	local entries = {}
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(entries, {
				rank = rank,
				name = getName(userId),
				value = entry.value,
			})
		end
	end
	cachedEntries = entries
	leaderboardRemote:FireAllClients(cachedEntries)
end

-- Sends the cached list to a single player (used when they join).
function Leaderboard.sendTo(player: Player)
	leaderboardRemote:FireClient(player, cachedEntries)
end

function Leaderboard.start()
	task.spawn(function()
		while true do
			Leaderboard.refresh()
			task.wait(Config.LeaderboardRefreshInterval)
		end
	end)
end

return Leaderboard
