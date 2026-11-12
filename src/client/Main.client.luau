-- Main.client.luau
-- Client entry point. Builds the UI, listens to the server and sends simple
-- requests that the server validates. The client never changes money, eggs,
-- creatures or speed itself.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(script.Parent.UI.Hud)
local Panels = require(script.Parent.UI.Panels)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer
-- The empty ScreenGui comes from StarterGui (src/gui/GameHUD.model.json).
local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("GameHUD") :: ScreenGui

local function fire(name: string)
	return function(...)
		Remotes.get(name):FireServer(...)
	end
end

local function dash()
	Remotes.get("Dash"):FireServer()
	Effects.sound("dash")
end

local panels
local hud = Hud.new(screenGui, {
	openPanel = function(name)
		panels:open(name)
	end,
	dash = dash,
	drop = fire("DropEgg"),
	lock = fire("LockBase"),
})
panels = Panels.new(screenGui, {
	buyTrail = fire("BuyTrail"),
	equipTrail = fire("EquipTrail"),
	upgradeTreadmill = fire("UpgradeTreadmill"),
	upgradeAquarium = fire("UpgradeAquarium"),
	sell = fire("SellCreature"),
})

Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
	hud:setState(state)
	panels:setState(state)
	Effects.setGuide(if state.carrying then state.entrance else nil)
end)
Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
	hud:notify(tostring(message), kind)
	Effects.notifySound(tostring(message), kind)
end)
Remotes.get("Alert").OnClientEvent:Connect(function(message)
	hud:alert(tostring(message))
	Effects.sound("alert")
	Effects.shake(0.8, 0.8)
end)
Remotes.get("Knockback").OnClientEvent:Connect(Effects.knockback)
Remotes.get("OpenPanel").OnClientEvent:Connect(function(name)
	panels:open(tostring(name), true)
end)

-- Keyboard / gamepad: Q or X = dash.
ContextActionService:BindAction("SeaDash", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)

Effects.start()

-- Ask for the current state now that we are listening.
Remotes.get("RequestSync"):FireServer()
