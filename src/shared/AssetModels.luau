-- AssetModels.luau
-- Gives the game its creature, guardian and egg models.
--
-- Put models (for example from the Toolbox) into ReplicatedStorage.Assets:
--   Assets/Creatures/<creature id>   e.g. Clownfish, Crab, Leviathan (ids are in Sea.luau)
--   Assets/Bosses/Zone1 ... Zone5    the guardian of each depth zone
--   Assets/Eggs/Egg                  one egg, tinted by rarity in the game
-- Optional number attribute "Yaw" on a model turns it (degrees) so it looks along -Z.
--
-- Every model we return:
--   * is a copy with all scripts removed (protection against backdoors)
--   * is anchored, has no collisions and is scaled to a fixed height
--   * has an invisible "Root" part as PrimaryPart at the bottom center, so
--     model:PivotTo(CFrame.new(groundPoint)) stands it on the ground.
-- If a model is missing, a simple built-in one is used and a warning is printed once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sea = require(script.Parent.Sea)
local CreatureModel = require(script.Parent.CreatureModel)

local AssetModels = {}

AssetModels.CreatureHeight = 2.6 -- in the aquarium
AssetModels.EggHeight = { 2.4, 2.7, 3.0, 3.4, 3.8, 4.4 } -- by rarity index
AssetModels.BossHeight = { 9, 12, 15, 19, 26 } -- by zone

local warned: { [string]: boolean } = {}

local function findAsset(folderName: string, name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(folderName)
	local found = folder and folder:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found
	end
	local key = folderName .. "/" .. name
	if not warned[key] then
		warned[key] = true
		warn("[AssetModels] Missing ReplicatedStorage.Assets." .. folderName .. "." .. name .. ", using a simple stand-in model.")
	end
	return nil
end

-- Makes a clean, anchored, scaled copy with a Root part at the bottom center.
local function prepare(source: Model, height: number, name: string): Model
	local model = source:Clone()
	model.Name = name
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			item:Destroy()
		elseif item:IsA("Humanoid") or item:IsA("ProximityPrompt") or item:IsA("ClickDetector") or item:IsA("Tool") then
			item:Destroy()
		end
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		end
	end
	local yaw = source:GetAttribute("Yaw")
	if type(yaw) == "number" then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(yaw), 0))
	end
	local size = model:GetExtentsSize()
	if size.Y > 0.05 then
		model:ScaleTo(model:GetScale() * height / size.Y)
	end
	local box, boxSize = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new(box.Position - Vector3.new(0, boxSize.Y / 2, 0))
	root.Parent = model
	model.PrimaryPart = root
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- Put the model at the origin, standing on it.
	model:PivotTo(CFrame.new())
	return model
end

-- A creature for the aquarium.
function AssetModels.creature(creatureId: string): Model
	local source = findAsset("Creatures", creatureId) or CreatureModel.build(creatureId, 1)
	local model = prepare(source, AssetModels.CreatureHeight, creatureId)
	model:SetAttribute("Creature", creatureId)
	return model
end

-- An egg: glows and sparkles in the color of its rarity.
function AssetModels.egg(creatureId: string): Model
	local rarity = Sea.rarityOf(creatureId)
	local asset = findAsset("Eggs", "Egg")
	local model = prepare(asset or CreatureModel.buildEgg(creatureId), AssetModels.EggHeight[rarity.index], "Egg")
	if asset then
		for _, part in model:GetDescendants() do
			local textured = part:IsA("MeshPart") and part.TextureID ~= ""
			if part:IsA("BasePart") and part.Name ~= "Root" and not textured then
				part.Color = part.Color:Lerp(rarity.color, 0.65)
			end
		end
	end
	local root = model.PrimaryPart :: BasePart
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Position = Vector3.new(0, AssetModels.EggHeight[rarity.index] / 2, 0)
	center.Parent = root
	local light = Instance.new("PointLight")
	light.Color = rarity.color
	light.Range = 8 + rarity.index * 2
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = center
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rarity.color)
	sparks.LightEmission = 0.6
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 + rarity.index * 0.1), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(1, 2.5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 1 + rarity.index * 2
	sparks.Parent = center
	model:SetAttribute("Creature", creatureId)
	return model
end

-- The guardian of a zone.
function AssetModels.boss(zoneIndex: number): Model
	local source = findAsset("Bosses", "Zone" .. zoneIndex) or CreatureModel.buildGuard(zoneIndex)
	local model = prepare(source, AssetModels.BossHeight[zoneIndex] or 12, Sea.Zones[zoneIndex].guard)
	model:SetAttribute("Zone", zoneIndex)
	return model
end

-- Welds everything to the Root and unanchors it, so it can be carried.
function AssetModels.makeCarryable(model: Model)
	local root = model.PrimaryPart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			if part ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
end

return AssetModels
