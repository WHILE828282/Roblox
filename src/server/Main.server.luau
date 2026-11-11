-- Main.server.luau
-- Server entry point for Dino Raiders. Creates the RemoteEvents and starts
-- every service. All game logic that matters (money, eggs, dinosaurs,
-- damage, saving) runs on the server; clients can only send requests that
-- the services validate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Remotes must exist before any service or client uses them.
Remotes.createAll()

local Services = script.Parent.Services
local PlayerData = require(Services.PlayerData)
local Leaderboard = require(Services.Leaderboard)
local Bases = require(Services.Bases)
local Mounts = require(Services.Mounts)
local Eggs = require(Services.Eggs)
local Combat = require(Services.Combat)
local Shop = require(Services.Shop)
local RateLimiter = require(script.Parent.Lib.RateLimiter)

-- Map and gameplay services first, PlayerData last so every
-- ProfileLoaded listener is connected before the first player loads.
Bases.start()
Mounts.start()
Eggs.start()
Combat.start()
Shop.start()
Leaderboard.start()
PlayerData.start()

-- The client asks for its state once its UI is ready.
local syncLimiter = RateLimiter.new(Config.SyncCooldown)
Remotes.get("RequestSync").OnServerEvent:Connect(function(player)
	if not syncLimiter:check(player) then
		return
	end
	if PlayerData.get(player) then
		Bases.refresh(player)
	end
	Leaderboard.sendTo(player)
end)

Players.PlayerRemoving:Connect(function(player)
	syncLimiter:forget(player)
end)

print("[Main] Dino Raiders server started")
