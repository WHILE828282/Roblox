-- Ground.luau
-- Finds walkable ground on the map. Eggs may only land on parts inside
-- Workspace.Map.Ground, and only where nothing else (rock, tree trunk,
-- river, lava pool) is above that spot.

local Ground = {}

local params: RaycastParams? = nil
local groundFolder: Instance? = nil

local function getParams(): RaycastParams?
	if params then
		return params
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	groundFolder = map:FindFirstChild("Ground")
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Include
	created.FilterDescendantsInstances = { map }
	params = created
	return created
end

-- The free ground point under (x, z), or nil if that spot is blocked.
function Ground.find(x: number, z: number): Vector3?
	local rayParams = getParams()
	if not rayParams then
		return nil
	end
	local result = workspace:Raycast(Vector3.new(x, 700, z), Vector3.new(0, -1400, 0), rayParams)
	if result and groundFolder and result.Instance:IsDescendantOf(groundFolder) then
		return result.Position
	end
	return nil
end

-- The first surface of the map right below `position` (any part), or the
-- position itself if there is none. Used for dropped eggs and empty saddles.
function Ground.below(position: Vector3): Vector3
	local rayParams = getParams()
	if rayParams then
		local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -80, 0), rayParams)
		if result then
			return result.Position
		end
	end
	return position
end

return Ground
