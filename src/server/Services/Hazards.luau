-- Hazards.luau
-- Parts tagged "KillPart" (lava, spikes, laser beams) kill on touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TouchUtil = require(script.Parent.Parent.Lib.TouchUtil)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Hazards = {}

function Hazards.start()
	Tagged(Config.Tags.KillPart, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Hazards] 'KillPart' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		return instance.Touched:Connect(function(hit)
			local player, _, humanoid = TouchUtil.getLivingPlayer(hit)
			if player and humanoid then
				humanoid.Health = 0
			end
		end)
	end)
end

return Hazards
