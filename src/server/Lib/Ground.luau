-- Ground.luau
-- Finds the walkable ground of the map (parts inside Workspace.Map.Ground).

local Ground = {}

local params: RaycastParams? = nil

local function getParams(): RaycastParams?
	if params then
		return params
	end
	local map = workspace:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("Ground")
	if not ground then
		return nil
	end
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Include
	created.FilterDescendantsInstances = { ground }
	params = created
	return created
end

-- The ground point under (x, z), or nil if there is no ground there.
function Ground.find(x: number, z: number): Vector3?
	local result = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), getParams())
	return if result then result.Position else nil
end

-- Like Ground.find, but falls back to height 0.
function Ground.at(x: number, z: number): Vector3
	return Ground.find(x, z) or Vector3.new(x, 0, z)
end

return Ground
