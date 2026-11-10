-- Main.server.luau
-- Server entry point. Creates the RemoteEvents and starts every service.
-- All game logic that matters (coins, stages, rewards, saving) lives on
-- the server; clients can only ask for things through validated remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Remotes must exist before any service or client uses them.
Remotes.createAll()

local Services = script.Parent.Services
local PlayerData = require(Services.PlayerData)
local Leaderboard = require(Services.Leaderboard)
local Checkpoints = require(Services.Checkpoints)
local Coins = require(Services.Coins)
local Hazards = require(Services.Hazards)
local RateLimiter = require(script.Parent.Lib.RateLimiter)

-- Map services first so checkpoints are known before players spawn.
Checkpoints.start()
Coins.start()
Hazards.start()
Leaderboard.start()
PlayerData.start()

-- The client asks for its state once its HUD is ready.
-- Rate limited and takes no arguments, so it cannot be abused.
local syncLimiter = RateLimiter.new(Config.SyncCooldown)
Remotes.get("RequestSync").OnServerEvent:Connect(function(player)
	if not syncLimiter:check(player) then
		return
	end
	PlayerData.changed(player) -- does nothing if data is still loading
	Leaderboard.sendTo(player)
end)

Players.PlayerRemoving:Connect(function(player)
	syncLimiter:forget(player)
end)

print("[Main] Obby server started")
