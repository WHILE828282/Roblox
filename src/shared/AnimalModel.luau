-- AnimalModel.luau
-- Builds a cute blocky animal Model from a species definition in
-- Animals.luau. No 3D files needed: every animal is made of Parts.
-- The model's pivot is the point on the ground under its center,
-- and it faces -Z, so `model:PivotTo(CFrame.new(position))` places it.

local CollectionService = game:GetService("CollectionService")

local Animals = require(script.Parent.Animals)
local Config = require(script.Parent.Config)

local AnimalModel = {}

local BLACK = Color3.fromRGB(25, 25, 30)
local BEAK = Color3.fromRGB(255, 170, 40)
local GOLD = Color3.fromRGB(255, 200, 40)

local function makePart(model: Model, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(position)
	part.Parent = model
	return part
end

local function addEyes(model: Model, headCenter: Vector3, headSize: number)
	local eyeSize = Vector3.new(0.22, 0.22, 0.08) * headSize / 1.1
	local z = headCenter.Z - headSize / 2 - 0.03
	local y = headCenter.Y + headSize * 0.12
	local x = headSize * 0.25
	makePart(model, "Eye", eyeSize, Vector3.new(-x, y, z), BLACK)
	makePart(model, "Eye", eyeSize, Vector3.new(x, y, z), BLACK)
end

local function buildQuad(model: Model, species, s: number)
	local legLength = (species.legs or 0.8) * s
	local bodySize = Vector3.new(1.6, 1.2, 2.4) * s
	local bodyY = legLength + bodySize.Y / 2
	makePart(model, "Body", bodySize, Vector3.new(0, bodyY, 0), species.color)
	makePart(model, "Chest", Vector3.new(1.1, 0.8, 0.1) * s, Vector3.new(0, bodyY - 0.1 * s, -bodySize.Z / 2 - 0.03), species.accent)

	for _, x in { -0.5, 0.5 } do
		for _, z in { -0.8, 0.8 } do
			makePart(model, "Leg", Vector3.new(0.4 * s, legLength, 0.4 * s), Vector3.new(x * s, legLength / 2, z * s), species.color)
		end
	end

	local headSize = 1.2 * s
	local head = Vector3.new(0, bodyY + 0.6 * s, -bodySize.Z / 2 - 0.2 * s)
	makePart(model, "Head", Vector3.new(headSize, headSize, headSize), head, species.color)
	makePart(model, "Snout", Vector3.new(0.5, 0.35, 0.25) * s, head + Vector3.new(0, -0.25 * s, -headSize / 2 - 0.1 * s), species.accent)
	addEyes(model, head, headSize)

	local top = head.Y + headSize / 2
	if species.ears == "long" then
		for _, x in { -0.25, 0.25 } do
			makePart(model, "Ear", Vector3.new(0.25, 1.1, 0.2) * s, Vector3.new(x * s, top + 0.55 * s, head.Z + 0.1 * s), species.color)
		end
	elseif species.ears == "pointy" then
		for _, x in { -0.35, 0.35 } do
			makePart(model, "Ear", Vector3.new(0.35, 0.45, 0.2) * s, Vector3.new(x * s, top + 0.22 * s, head.Z + 0.2 * s), species.color)
		end
	elseif species.ears == "round" then
		for _, x in { -0.45, 0.45 } do
			makePart(model, "Ear", Vector3.new(0.35, 0.35, 0.2) * s, Vector3.new(x * s, top + 0.12 * s, head.Z + 0.2 * s), species.accent)
		end
	end
	if species.antlers then
		for _, x in { -0.35, 0.35 } do
			makePart(model, "Antler", Vector3.new(0.15, 0.9, 0.15) * s, Vector3.new(x * s, top + 0.45 * s, head.Z + 0.3 * s), Color3.fromRGB(90, 60, 35))
			makePart(model, "Antler", Vector3.new(0.5, 0.15, 0.15) * s, Vector3.new(x * 1.6 * s, top + 0.75 * s, head.Z + 0.3 * s), Color3.fromRGB(90, 60, 35))
		end
	end
	if species.horns then
		for _, x in { -0.3, 0.3 } do
			makePart(model, "Horn", Vector3.new(0.2, 0.5, 0.2) * s, Vector3.new(x * s, top + 0.25 * s, head.Z + 0.25 * s), species.accent)
		end
	end
	if species.horn then
		makePart(model, "Horn", Vector3.new(0.18, 0.9, 0.18) * s, Vector3.new(0, top + 0.45 * s, head.Z - 0.2 * s), GOLD, Enum.Material.Neon)
	end
	if species.wings then
		for _, side in { -1, 1 } do
			makePart(model, "Wing", Vector3.new(0.15, 1.1, 1.8) * s, Vector3.new(side * (bodySize.X / 2 + 0.1 * s), bodyY + 0.7 * s, 0), species.accent)
		end
	end
	makePart(model, "Tail", Vector3.new(0.3, 0.3, 0.6) * s, Vector3.new(0, bodyY + 0.3 * s, bodySize.Z / 2 + 0.3 * s), species.accent)
end

local function buildBird(model: Model, species, s: number)
	local legLength = (if species.tall then 1.6 else 0.5) * s
	for _, x in { -0.3, 0.3 } do
		makePart(model, "Leg", Vector3.new(0.15 * s, legLength, 0.15 * s), Vector3.new(x * s, legLength / 2, 0), BEAK)
	end
	local bodySize = Vector3.new(1.4, 1.6, 1.3) * s
	local bodyY = legLength + bodySize.Y / 2
	local material = if species.glow then Enum.Material.Neon else nil
	makePart(model, "Body", bodySize, Vector3.new(0, bodyY, 0), species.color, material)
	makePart(model, "Belly", Vector3.new(0.9, 1.0, 0.1) * s, Vector3.new(0, bodyY - 0.15 * s, -bodySize.Z / 2 - 0.03), species.accent)
	for _, side in { -1, 1 } do
		makePart(model, "Wing", Vector3.new(0.2, 1.1, 0.9) * s, Vector3.new(side * (bodySize.X / 2 + 0.1 * s), bodyY, 0.1 * s), species.color, material)
	end
	local headSize = 1.1 * s
	local head = Vector3.new(0, bodyY + bodySize.Y / 2 + headSize / 2 - 0.1 * s, -0.1 * s)
	makePart(model, "Head", Vector3.new(headSize, headSize, headSize), head, species.color, material)
	makePart(model, "Beak", Vector3.new(0.3, 0.25, 0.5) * s, head + Vector3.new(0, -0.1 * s, -headSize / 2 - 0.2 * s), BEAK)
	addEyes(model, head, headSize)
	if species.glow then
		local light = Instance.new("PointLight")
		light.Color = species.accent
		light.Range = 12
		light.Brightness = 2
		light.Parent = model:FindFirstChild("Body")
	end
end

local function buildBlob(model: Model, species, s: number)
	local bodySize = Vector3.new(1.8, 0.8, 1.6) * s
	local bodyY = bodySize.Y / 2
	makePart(model, "Body", bodySize, Vector3.new(0, bodyY, 0), species.color)
	if species.shell then
		makePart(model, "Shell", Vector3.new(1.6, 0.6, 1.4) * s, Vector3.new(0, bodySize.Y + 0.3 * s, 0.1 * s), species.accent)
		makePart(model, "Head", Vector3.new(0.7, 0.6, 0.6) * s, Vector3.new(0, bodyY + 0.2 * s, -bodySize.Z / 2 - 0.3 * s), species.color)
		addEyes(model, Vector3.new(0, bodyY + 0.2 * s, -bodySize.Z / 2 - 0.3 * s), 0.6 * s)
		return
	end
	-- Eyes sit on top of the body (crab, frog style).
	for _, x in { -0.45, 0.45 } do
		makePart(model, "EyeBall", Vector3.new(0.4, 0.4, 0.4) * s, Vector3.new(x * s, bodySize.Y + 0.15 * s, -0.5 * s), Color3.new(1, 1, 1))
		makePart(model, "Eye", Vector3.new(0.2, 0.2, 0.08) * s, Vector3.new(x * s, bodySize.Y + 0.15 * s, -0.72 * s), BLACK)
	end
	makePart(model, "Belly", Vector3.new(1.2, 0.4, 0.1) * s, Vector3.new(0, bodyY - 0.1 * s, -bodySize.Z / 2 - 0.03), species.accent)
	if species.claws then
		for _, side in { -1, 1 } do
			makePart(model, "Claw", Vector3.new(0.5, 0.4, 0.5) * s, Vector3.new(side * (bodySize.X / 2 + 0.3 * s), bodyY, -0.6 * s), species.accent)
		end
	end
end

-- Recolors the model for its mutation.
local function applyMutation(model: Model, root: BasePart, mutationId: string)
	if mutationId == "Normal" then
		return
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root and part.Name ~= "Eye" then
			if mutationId == "Golden" then
				part.Color = GOLD
				part.Material = Enum.Material.Foil
				part.Reflectance = 0.15
			elseif mutationId == "Rainbow" then
				part.Material = Enum.Material.Neon
				CollectionService:AddTag(part, Config.Tags.RainbowPart)
			end
		end
	end
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = if mutationId == "Golden" then GOLD else Color3.fromRGB(255, 120, 255)
	sparkles.Parent = root
end

-- Returns a new Model (not parented) for the given species and mutation.
function AnimalModel.build(speciesId: string, mutationId: string?): Model
	local species = Animals.Species[speciesId]
	assert(species, "Unknown species: " .. tostring(speciesId))
	mutationId = mutationId or "Normal"

	local model = Instance.new("Model")
	model.Name = speciesId

	-- Invisible root on the ground: the model's pivot point.
	local root = makePart(model, "Root", Vector3.new(1, 0.2, 1), Vector3.new(0, 0.1, 0), Color3.new(1, 1, 1))
	root.Transparency = 1
	model.PrimaryPart = root

	local s = species.scale or 1
	if species.kind == "bird" then
		buildBird(model, species, s)
	elseif species.kind == "blob" then
		buildBlob(model, species, s)
	else
		buildQuad(model, species, s)
	end
	applyMutation(model, root, mutationId)

	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Mutation", mutationId)
	model:SetAttribute("Rarity", species.rarity)
	return model
end

-- Height of the model's top above its pivot (for signs above it).
function AnimalModel.height(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

return AnimalModel
