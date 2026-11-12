-- Main.server.luau
-- Server entry point of "Steal a Sea Monster". Everything that matters
-- (money, eggs, creatures, speed, saving) is decided here on the server;
-- clients only send requests that the services validate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.createAll() -- must exist before any service or client uses them

local Services = script.Parent.Services
local PlayerData = require(Services.PlayerData)
local Bases = require(Services.Bases)
local Ocean = require(Services.Ocean)
local Trails = require(Services.Trails)
local Movement = require(script.Parent.Lib.Movement)
local RateLimiter = require(script.Parent.Lib.RateLimiter)

Movement.setSpeedSource(function(player)
	local data = PlayerData.get(player)
	return data and data.Speed
end)

-- PlayerData last, so every ProfileLoaded listener is connected first.
Bases.start()
Ocean.start()
Trails.start()
PlayerData.start()

local syncLimiter = RateLimiter.new(1)
Remotes.get("RequestSync").OnServerEvent:Connect(function(player)
	if syncLimiter:check(player) then
		PlayerData.changed(player)
	end
end)

print("[Main] Steal a Sea Monster server started (" .. #Players:GetPlayers() .. " players)")
