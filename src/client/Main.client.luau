-- Main.client.luau
-- Client entry point for Dino Raiders. Builds the UI, listens to the server
-- and sends simple requests that the server validates. The client never
-- changes money, eggs or dinosaurs itself.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(script.Parent.UI.Hud)
local Panels = require(script.Parent.UI.Panels)
local LeaderboardPanel = require(script.Parent.UI.LeaderboardPanel)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer
-- The empty ScreenGui comes from StarterGui (src/gui/GameHUD.model.json).
local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("GameHUD") :: ScreenGui

local panels
local hud = Hud.new(screenGui, {
	openPanel = function(name)
		panels:open(name)
	end,
	attack = function()
		Remotes.get("Attack"):FireServer()
	end,
	ability = function()
		Remotes.get("UseAbility"):FireServer()
	end,
	dismount = function()
		Remotes.get("Dismount"):FireServer()
	end,
	lock = function()
		Remotes.get("LockBase"):FireServer()
	end,
})
panels = Panels.new(screenGui, {
	sell = function(dinoId)
		Remotes.get("SellDino"):FireServer(dinoId)
	end,
	ride = function(dinoId)
		Remotes.get("Ride"):FireServer(dinoId)
	end,
	buyUpgrade = function(upgradeId)
		Remotes.get("BuyUpgrade"):FireServer(upgradeId)
	end,
})
local leaderboard = LeaderboardPanel.new(screenGui)

Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
	hud:setState(state)
	panels:setState(state)
end)
Remotes.get("BaseChanged").OnClientEvent:Connect(function(dinos, eggs)
	panels:setBase(dinos, eggs)
end)
Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
	hud:notify(tostring(message), kind)
end)
Remotes.get("Announce").OnClientEvent:Connect(function(message, color)
	hud:announce(tostring(message), if typeof(color) == "Color3" then color else nil)
end)
Remotes.get("Knockback").OnClientEvent:Connect(function(velocity)
	Effects.knockback(velocity)
	Effects.shake(0.5, 0.35) -- you got hit
end)
Remotes.get("Eruption").OnClientEvent:Connect(Effects.eruption)
Remotes.get("LeaderboardChanged").OnClientEvent:Connect(function(entries)
	leaderboard:setEntries(entries)
end)

-- PC controls: left click = hit, F = ability.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Remotes.get("Attack"):FireServer()
	end
end)
ContextActionService:BindAction("DinoAbility", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("UseAbility"):FireServer()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

Effects.start()

-- Ask for the current state now that we are listening.
Remotes.get("RequestSync"):FireServer()
