-- Main.client.luau
-- Client entry point. Builds the UI and connects it to the server remotes.
-- The client never changes coins or progress itself; it only shows what
-- the server sends and sends simple requests that the server validates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(script.Parent.UI.Hud)
local LeaderboardPanel = require(script.Parent.UI.LeaderboardPanel)
local CoinSpin = require(script.Parent.CoinSpin)

local player = Players.LocalPlayer
-- The empty ScreenGui comes from StarterGui (src/gui/ObbyHUD.model.json).
-- ResetOnSpawn is false there, so the UI survives respawns.
local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("ObbyHUD") :: ScreenGui

local hud = Hud.new(screenGui, function()
	Remotes.get("RequestReset"):FireServer()
end)
local leaderboard = LeaderboardPanel.new(screenGui)

Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
	hud:setState(state)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
	hud:notify(tostring(message), kind)
end)

Remotes.get("RunFinished").OnClientEvent:Connect(function(result)
	hud:showFinish(result)
end)

Remotes.get("LeaderboardChanged").OnClientEvent:Connect(function(entries)
	leaderboard:setEntries(entries)
end)

CoinSpin.start()

-- Ask for the current state now that we are listening.
Remotes.get("RequestSync"):FireServer()
