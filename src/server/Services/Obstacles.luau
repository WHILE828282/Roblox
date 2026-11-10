-- Obstacles.luau
-- Moving and disappearing obstacles, driven by the server so every
-- player sees the same thing:
--   * "Spinner": rotates around its own vertical axis.
--     Optional number attribute "Speed" (degrees per second, negative = other way).
--     Usually also tagged "KillPart" so touching it kills.
--   * "FadingPlatform": after a player steps on it, it blinks, vanishes
--     for Config.FadeRespawnTime seconds and then comes back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local TouchUtil = require(script.Parent.Parent.Lib.TouchUtil)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Obstacles = {}

local spinners: { [BasePart]: true } = {}

local function setupFading(part: BasePart)
	local originalTransparency = part.Transparency
	local busy = false

	return part.Touched:Connect(function(hit)
		if busy or not TouchUtil.getLivingPlayer(hit) then
			return
		end
		busy = true
		-- Warn the player: half transparent while it is about to disappear.
		part.Transparency = 0.5
		task.wait(Config.FadeDelay)
		part.Transparency = 1
		part.CanCollide = false
		task.wait(Config.FadeRespawnTime)
		if part.Parent then
			part.Transparency = originalTransparency
			part.CanCollide = true
		end
		busy = false
	end)
end

function Obstacles.start()
	Tagged(Config.Tags.Spinner, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Obstacles] 'Spinner' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		instance.Anchored = true
		spinners[instance] = true
		return function()
			spinners[instance] = nil
		end
	end)

	Tagged(Config.Tags.FadingPlatform, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Obstacles] 'FadingPlatform' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		return setupFading(instance)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for part in spinners do
			local speed = part:GetAttribute("Speed")
			if type(speed) ~= "number" then
				speed = Config.SpinnerDefaultSpeed
			end
			part.CFrame *= CFrame.Angles(0, math.rad(speed) * dt, 0)
		end
	end)
end

return Obstacles
