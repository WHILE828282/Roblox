-- TouchUtil.luau
-- Helpers for validating Touched events on the server.
-- Touched can be triggered by anything (hats, tools, unanchored parts),
-- so every handler first checks that a real, living player touched the part.

local Players = game:GetService("Players")

local TouchUtil = {}

-- If `hit` belongs to a living player's character, returns
-- player, character, humanoid, rootPart. Otherwise returns nil.
function TouchUtil.getLivingPlayer(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return player, character, humanoid, root
end

-- True if `root` is within `maxDistance` studs of the surface of `part`.
-- This stops exploiters from "touching" parts from far away.
function TouchUtil.isNear(root: BasePart, part: BasePart, maxDistance: number): boolean
	local localPos = part.CFrame:PointToObjectSpace(root.Position)
	local half = part.Size / 2
	local closest = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - closest).Magnitude <= maxDistance
end

return TouchUtil
